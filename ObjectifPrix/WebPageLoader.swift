import Foundation
import WebKit

/// Charge une page avec le navigateur intégré de l'iPhone (le même moteur que Safari),
/// puis renvoie le HTML une fois que `accept` le trouve satisfaisant (ou au bout de 25 s).
@MainActor
final class WebPageLoader: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?
    private var pollTask: Task<Void, Never>?
    private var lastHTML = ""

    static func html(for url: URL, accept: @escaping (String) -> Bool) async throws -> String {
        let loader = WebPageLoader()
        return try await loader.load(url, accept: accept)
    }

    private func load(_ url: URL, accept: @escaping (String) -> Bool) async throws -> String {
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                             configuration: WKWebViewConfiguration())
        view.navigationDelegate = self
        webView = view

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            continuation = cont
            view.load(URLRequest(url: url))

            pollTask = Task { [weak self] in
                let started = Date()
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard let self = self, self.continuation != nil else { return }
                    if let html = await self.currentHTML() {
                        self.lastHTML = html
                        if accept(html) {
                            self.finish(.success(html))
                            return
                        }
                    }
                    if Date().timeIntervalSince(started) > 25 {
                        self.finish(.success(self.lastHTML))
                        return
                    }
                }
            }
        }
    }

    private func currentHTML() async -> String? {
        guard let view = webView else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            view.evaluateJavaScript("document.documentElement.outerHTML") { result, _ in
                cont.resume(returning: result as? String)
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        pollTask?.cancel()
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        cont.resume(with: result)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(FetchError(message: "Impossible de charger la page (\(error.localizedDescription)).")))
    }
}
