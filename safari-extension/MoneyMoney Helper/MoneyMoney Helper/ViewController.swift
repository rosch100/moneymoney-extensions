//
//  ViewController.swift
//  MoneyMoney Helper
//
//  Created by Roland Schramme on 27.06.26.
//

import Cocoa
import os.log
import SafariServices
import WebKit

private let extensionBundleIdentifier = "com.yourCompany.MoneyMoney-Helper.Extension"
private let safariSettingsURLs = [
    "x-apple.systempreferences:com.apple.Safari-Settings.extension",
    "x-apple.systempreferences:com.apple.Safari-Settings",
]

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    /// True only after Main.html (with Script.js) was loaded; guards show() calls.
    private var didLoadMainUI = false

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.navigationDelegate = self
        webView.configuration.userContentController.add(self, name: "controller")
        loadMainInterface()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard didLoadMainUI else {
            return
        }
        refreshExtensionState(in: webView)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String, body == "open-preferences" else {
            return
        }
        // Avoid Safari 27 WebsitesPreferences crash path from showPreferencesForExtension deep-link.
        openSafariExtensionsSettings()
    }

    private func loadMainInterface() {
        guard let mainURL = Bundle.main.url(forResource: "Main", withExtension: "html"),
              let resourceURL = Bundle.main.resourceURL else {
            didLoadMainUI = false
            showMissingResources()
            return
        }
        didLoadMainUI = true
        webView.loadFileURL(mainURL, allowingReadAccessTo: resourceURL)
    }

    private func showMissingResources() {
        os_log(.error, "MoneyMoney Helper: Main.html oder Resource-URL fehlt im Bundle")
        webView.loadHTMLString(
            """
            <!DOCTYPE html><html><body style="font: -apple-system-body; margin: 2rem;">
            <p><strong>MoneyMoney Helper</strong></p>
            <p>App-Ressourcen fehlen (Main.html). Bitte die App neu bauen und installieren.</p>
            </body></html>
            """,
            baseURL: nil
        )
    }

    private func refreshExtensionState(in webView: WKWebView) {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: extensionBundleIdentifier) { state, error in
            let enabled: Bool? = (error == nil) ? state?.isEnabled : nil
            DispatchQueue.main.async {
                self.applyExtensionState(enabled, in: webView)
            }
        }
    }

    private func applyExtensionState(_ enabled: Bool?, in webView: WKWebView) {
        let enabledJS: String
        if let enabled {
            enabledJS = enabled ? "true" : "false"
        } else {
            enabledJS = "null"
        }
        let useSettingsJS: String
        if #available(macOS 13, *) {
            useSettingsJS = "true"
        } else {
            useSettingsJS = "false"
        }
        webView.evaluateJavaScript("show(\(enabledJS), \(useSettingsJS))")
    }

    private func openSafariExtensionsSettings() {
        for candidate in safariSettingsURLs {
            guard let url = URL(string: candidate) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                NSApplication.shared.terminate(nil)
                return
            }
        }
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

}
