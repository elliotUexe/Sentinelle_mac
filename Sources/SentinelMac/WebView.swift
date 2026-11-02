import OSLog
import SwiftUI
import WebKit

/// Enrobage minimal de WKWebView : charge le dashboard Sentinel existant tel
/// quel (JS/CSS servis par l'orchestrateur, cache-busting déjà géré côté
/// serveur — cf. `app/api/dashboard.py::_asset_version()`). Aucune logique de
/// rendu dupliquée ici, l'app ne fait qu'afficher la même page que le
/// navigateur.
struct WebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(dashboardURL: url)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    /// Les liens du dashboard vers un service ("Ouvrir le service", export CSV)
    /// sont en `target="_blank"` : sans `uiDelegate`, WKWebView les ignore
    /// silencieusement. On les envoie au navigateur par défaut, comme tout
    /// lien cliqué qui sort du dashboard.
    ///
    /// Si le dashboard ne charge pas (Sentinel injoignable ou en redémarrage),
    /// WKWebView laisse une page blanche et ne réessaie jamais : on affiche un
    /// message et on recharge toutes les quelques secondes.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let dashboardURL: URL
        private var retryScheduled = false
        private static let retryDelaySeconds = 5.0
        private static let log = Logger(subsystem: "com.hitsnow.SentinelMac", category: "liens")

        init(dashboardURL: URL) {
            self.dashboardURL = dashboardURL
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            retryLater(webView, after: error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            retryLater(webView, after: error)
        }

        private func retryLater(_ webView: WKWebView, after error: Error) {
            // Navigation annulée (nouveau chargement, lien envoyé au
            // navigateur) : pas une panne.
            if (error as NSError).code == NSURLErrorCancelled { return }
            guard !retryScheduled else { return }
            retryScheduled = true
            Self.log.notice("dashboard injoignable, nouvel essai dans 5 s : \(error.localizedDescription, privacy: .public)")
            webView.loadHTMLString(Self.unreachablePage, baseURL: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryDelaySeconds) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.retryScheduled = false
                webView.load(URLRequest(url: self.dashboardURL))
            }
        }

        private static let unreachablePage = """
            <html><body style="font: 14px -apple-system; color: #888; display: flex; \
            align-items: center; justify-content: center; height: 90vh; margin: 0;">\
            Sentinel injoignable, nouvel essai dans quelques secondes…</body></html>
            """

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                openInBrowser(url)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url,
                  url.host != dashboardURL.host else { return .allow }
            openInBrowser(url)
            return .cancel
        }

        private func openInBrowser(_ url: URL) {
            Self.log.notice("ouverture externe \(url.absoluteString, privacy: .public)")
            NSWorkspace.shared.open(url)
        }
    }
}
