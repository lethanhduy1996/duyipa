import Foundation
import SwiftUI
import UIKit
import WebKit

struct OfflineWebTab: View {
    @State private var output: ShaderExportItem?
    @State private var error: String?
    var body: some View {
        OfflineWebView(onExport: { url in
            output = ShaderExportItem(url: url)
        }, onError: { error = $0 })
            .sheet(item: $output) { item in
                ShaderExportPicker(url: item.url) { _ in output = nil }
            }
            .alert("Web offline", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
}

struct OfflineWebView: UIViewRepresentable {
    let onExport: (URL) -> Void
    let onError: (String) -> Void
    private static let handler = "localFileExport"
    private static let bridge = """
    (() => {
      const channel = window.webkit.messageHandlers.localFileExport;
      document.addEventListener("click", async (event) => {
        const anchor = event.target instanceof Element ? event.target.closest("a[download]") : null;
        if (!anchor || !anchor.href.startsWith("blob:") || !event.isTrusted) return;
        event.preventDefault();
        if (anchor.dataset.saving === "1") return;
        anchor.dataset.saving = "1";
        try {
          const blob = await (await fetch(anchor.href)).blob();
          if (blob.size > 32 * 1024 * 1024) throw new Error("File vượt giới hạn 32 MB.");
          const result = await new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(reader.result);
            reader.onerror = () => reject(new Error("Không đọc được dữ liệu tải xuống."));
            reader.readAsDataURL(blob);
          });
          const base64 = String(result).split(",")[1];
          if (!base64) throw new Error("Dữ liệu tải xuống trống.");
          channel.postMessage({ filename: anchor.download, base64: base64 });
        } catch (error) {
          channel.postMessage({ error: String(error.message || error) });
        } finally {
          delete anchor.dataset.saving;
        }
      }, true);
    })();
    """
    func makeCoordinator() -> Coordinator {
        Coordinator(onExport: onExport, onError: onError)
    }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.websiteDataStore = .nonPersistent()
        config.userContentController.add(context.coordinator, name: Self.handler)
        config.userContentController.addUserScript(WKUserScript(
            source: Self.bridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        guard let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WebResources") else {
            DispatchQueue.main.async { onError("Thiếu index.html trong IPA.") }
            return view
        }
        context.coordinator.index = index
        let rules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "BluOfflineWeb", encodedContentRuleList: rules) { list, _ in
            DispatchQueue.main.async {
                if let list = list {
                    view.configuration.userContentController.add(list)
                    view.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
                } else {
                    onError("Không tạo được bộ lọc kết nối ngoại tuyến.")
                }
            }
        }
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: handler)
        uiView.stopLoading()
        uiView.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let onExport: (URL) -> Void
        let onError: (String) -> Void
        var index: URL?
        init(onExport: @escaping (URL) -> Void, onError: @escaping (String) -> Void) {
            self.onExport = onExport
            self.onError = onError
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            let allowed = url.standardizedFileURL == index?.standardizedFileURL || url.absoluteString == "about:blank"
            decisionHandler(allowed ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError(error.localizedDescription)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError(error.localizedDescription)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == OfflineWebView.handler,
                  message.frameInfo.isMainFrame,
                  message.frameInfo.request.url?.standardizedFileURL == index?.standardizedFileURL,
                  let payload = message.body as? [String: Any] else { return }
            if let error = payload["error"] as? String {
                onError(error)
                return
            }
            guard let filename = payload["filename"] as? String, !filename.isEmpty,
                  filename.utf8.count <= 255, filename != ".", filename != "..",
                  !filename.contains("/"), !filename.contains("\\"),
                  !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  let b64 = payload["base64"] as? String, b64.utf8.count <= 45_000_000,
                  let bytes = Data(base64Encoded: b64), !bytes.isEmpty,
                  bytes.count <= 32 * 1024 * 1024 else {
                onError("Tên tệp hoặc dữ liệu xuất không hợp lệ.")
                return
            }
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(filename)
                try bytes.write(to: url, options: .atomic)
                onExport(url)
            } catch {
                onError(error.localizedDescription)
            }
        }
    }
}
