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
        Coordinator(dashboardHost: url.host)
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
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let dashboardHost: String?
        private static let log = Logger(subsystem: "com.hitsnow.SentinelMac", category: "liens")

        init(dashboardHost: String?) {
            self.dashboardHost = dashboardHost
        }

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
                  url.host != dashboardHost else { return .allow }
            openInBrowser(url)
            return .cancel
        }

        private func openInBrowser(_ url: URL) {
            Self.log.notice("ouverture externe \(url.absoluteString, privacy: .public)")
            NSWorkspace.shared.open(url)
        }
    }
}
