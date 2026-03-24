import Foundation
import SwiftData

/// Parses `roam://` URLs and dispatches navigation actions.
///
/// Supported routes:
/// - `roam://connect/{hostAlias}` — Navigate to host and start connection
/// - `roam://workspace/{workspaceName}` — Navigate to workspace detail
/// - `roam://files` — Open the Files tab
/// - `roam://files/local` — Open Files tab on local mode
/// - `roam://files/remote` — Open Files tab on remote mode
/// - `roam://settings` — Open Settings
/// - `roam://notes` — Open Notes folder in local file browser
/// - `roam://sessions` — Open Sessions tab
/// - `roam://overview` — Open Overview
@Observable
final class URLSchemeHandler {
    enum DeepLinkAction: Equatable {
        case navigateToSection(String) // AppSection rawValue
        case connectHost(alias: String)
        case openWorkspace(name: String)
        case openNotes
        case openLocalFiles
        case openRemoteFiles
    }

    /// The most recent pending action. Consumed by the UI.
    var pendingAction: DeepLinkAction?

    func handle(url: URL) {
        guard url.scheme == "roam" else { return }

        let host = url.host() ?? url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "connect":
            if let alias = pathComponents.first {
                pendingAction = .connectHost(alias: alias)
            }
        case "workspace":
            if let name = pathComponents.first {
                pendingAction = .openWorkspace(name: name.removingPercentEncoding ?? name)
            }
        case "files":
            if pathComponents.first == "local" {
                pendingAction = .openLocalFiles
            } else if pathComponents.first == "remote" {
                pendingAction = .openRemoteFiles
            } else {
                pendingAction = .navigateToSection("files")
            }
        case "notes":
            pendingAction = .openNotes
        case "settings":
            pendingAction = .navigateToSection("settings")
        case "sessions":
            pendingAction = .navigateToSection("sessions")
        case "overview":
            pendingAction = .navigateToSection("overview")
        case "hosts":
            pendingAction = .navigateToSection("hosts")
        case "workspaces":
            pendingAction = .navigateToSection("workspaces")
        case "vault":
            pendingAction = .navigateToSection("vault")
        default:
            break
        }
    }

    func consumeAction() -> DeepLinkAction? {
        defer { pendingAction = nil }
        return pendingAction
    }
}
