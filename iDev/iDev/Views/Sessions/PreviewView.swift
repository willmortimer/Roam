import SwiftUI
import WebKit

/// WKWebView wrapper for previewing forwarded ports (dev servers, etc.).
struct PreviewView: View {
    let localPort: Int
    let displayName: String
    var scheme: String = "http"

    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showPublicPreviewSheet = false
    @State private var previewService = PublicPreviewService()

    private var url: URL {
        URL(string: "\(scheme)://127.0.0.1:\(localPort)")!
    }

    var body: some View {
        ZStack {
            PreviewWebView(url: url, isLoading: $isLoading, errorMessage: $errorMessage)
                .ignoresSafeArea(edges: .bottom)

            if isLoading {
                ProgressView("Loading preview…")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if let errorMessage {
                ContentUnavailableView(
                    "Preview Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack {
                    Button("Share", systemImage: "square.and.arrow.up") {
                        showPublicPreviewSheet = true
                    }
                    Button("Reload", systemImage: "arrow.clockwise") {
                        errorMessage = nil
                        isLoading = true
                    }
                }
            }
        }
        .sheet(isPresented: $showPublicPreviewSheet) {
            PublicPreviewSheet(
                localPort: localPort,
                previewService: previewService,
                helperClient: nil,
                onDismiss: { showPublicPreviewSheet = false }
            )
        }
    }
}

// MARK: - WKWebView Representable

struct PreviewWebView: UIViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Reload if URL changed
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: PreviewWebView

        init(parent: PreviewWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.errorMessage = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.errorMessage = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.errorMessage = error.localizedDescription
        }

        // Allow self-signed certs for localhost dev servers
        func webView(
            _ webView: WKWebView,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            if challenge.protectionSpace.host == "127.0.0.1" || challenge.protectionSpace.host == "localhost",
               let serverTrust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}
