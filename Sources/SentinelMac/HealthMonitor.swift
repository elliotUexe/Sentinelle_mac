import Foundation
import SwiftUI

/// Statuts miroir de `HealthStatus` côté Sentinel (`app/models/state.py`).
/// `muted` : silence manuel temporaire posé par l'utilisateur sur un service
/// down/degraded — masque l'alerte sans changer la réalité du problème, donc
/// traité comme non alarmant ci-dessous (ni down ni degraded).
enum ServiceStatus: String, Decodable {
    case up, down, degraded, suppressed_down, unknown, muted

    /// Un statut inconnu côté app (nouveau `HealthStatus` ajouté au serveur)
    /// ne doit pas faire échouer le décodage de tout le snapshot, sinon l'app
    /// reste figée sur son dernier état : on retombe sur `.unknown`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ServiceStatus(rawValue: raw) ?? .unknown
    }
}

private struct ServiceSummary: Decodable {
    let id: String
    let status: ServiceStatus
}

private struct StateChangePayload: Decodable {
    let service_id: String
    let to_status: ServiceStatus
}

/// Niveau de santé agrégé affiché dans la barre de menu. Reproduit
/// exactement la sémantique de `dashboard.js` (`DOWNISH`, Jalon e) :
/// down/suppressed_down -> rouge, degraded -> orange, sinon -> vert.
enum OverallHealth {
    case healthy, degraded, down, unknown

    var symbolName: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .down: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var tintColor: Color {
        switch self {
        case .healthy: return .green
        case .degraded: return .orange
        case .down: return .red
        case .unknown: return .secondary
        }
    }
}

@MainActor
final class HealthMonitor: ObservableObject {
    @Published private(set) var overall: OverallHealth = .unknown
    @Published private(set) var downCount = 0
    @Published private(set) var degradedCount = 0
    @Published private(set) var connected = false

    /// Icône affichée dans la barre de menu : le jaune prime sur le statut de
    /// santé quand on est déconnecté, car les données affichées (`overall`)
    /// sont alors potentiellement périmées — pas fiable de continuer à
    /// afficher un vert/rouge qu'on ne peut plus garantir à jour.
    var displaySymbolName: String { connected ? overall.symbolName : "wifi.slash" }
    var displayColor: Color { connected ? overall.tintColor : .yellow }

    private var statuses: [String: ServiceStatus] = [:]
    private var sseTask: Task<Void, Never>?
    private let sse = SSEClient(url: Config.eventsURL)

    /// Démarre immédiatement : ce moniteur doit tourner pour toute la durée
    /// de vie de l'app (l'icône de la barre de menu doit refléter l'état
    /// réel même si le popover n'est jamais ouvert), pas seulement quand une
    /// vue SwiftUI apparaît.
    init() {
        start()
    }

    func start() {
        Task { await refreshSnapshot() }
        sseTask?.cancel()
        sseTask = Task {
            await sse.run(
                onEvent: { [weak self] event in
                    guard event.event == "state_change" else { return }
                    Task { @MainActor in self?.applyStateChange(event.data) }
                },
                onConnectionChange: { [weak self] isConnected in
                    Task { @MainActor in
                        self?.connected = isConnected
                        // (Re)connexion : snapshot immédiat, comme dashboard.js,
                        // plutôt que d'attendre le poll de 30 s. Couvre un
                        // premier snapshot raté au lancement (serveur en
                        // redémarrage) et les deltas manqués pendant la coupure.
                        if isConnected { await self?.refreshSnapshot() }
                    }
                }
            )
        }
        // filet de sécurité, comme le setInterval(30000) de dashboard.js :
        // rattrape tout événement manqué pendant une reconnexion SSE.
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await refreshSnapshot()
            }
        }
    }

    func stop() {
        sseTask?.cancel()
    }

    private func refreshSnapshot() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: Config.servicesURL)
            let services = try JSONDecoder().decode([ServiceSummary].self, from: data)
            statuses = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0.status) })
            recomputeOverall()
        } catch {
            // Sentinel injoignable : on garde le dernier état connu plutôt
            // que de basculer en "unknown" sur un simple accroc réseau.
        }
    }

    private func applyStateChange(_ jsonData: String) {
        guard let data = jsonData.data(using: .utf8),
              let payload = try? JSONDecoder().decode(StateChangePayload.self, from: data) else { return }
        statuses[payload.service_id] = payload.to_status
        recomputeOverall()
    }

    private func recomputeOverall() {
        let values = Array(statuses.values)
        downCount = values.filter { $0 == .down || $0 == .suppressed_down }.count
        degradedCount = values.filter { $0 == .degraded }.count
        if downCount > 0 {
            overall = .down
        } else if degradedCount > 0 {
            overall = .degraded
        } else if values.isEmpty {
            overall = .unknown
        } else {
            overall = .healthy
        }
    }
}
