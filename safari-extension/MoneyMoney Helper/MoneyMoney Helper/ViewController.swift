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

class ViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {

    @IBOutlet var webView: WKWebView!

    /// True only after Main.html (with Script.js) was loaded; guards show() calls.
    private var didLoadMainUI = false

    /// True, solange ein Aufruf der Safari-Einstellungen läuft; verhindert Doppelaufrufe.
    private var isOpeningSafariSettings = false

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

    /// Öffnet Safari → Einstellungen → Erweiterungen über die SafariServices-API.
    /// Das Schema `x-apple.systempreferences:` öffnet die Systemeinstellungen und
    /// enthält seit macOS 13 kein Safari-Pane mehr, deshalb ist es hier unzulässig.
    private func openSafariExtensionsSettings() {
        guard !isOpeningSafariSettings else {
            return
        }
        isOpeningSafariSettings = true
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { [weak self] error in
            DispatchQueue.main.async {
                self?.isOpeningSafariSettings = false
                if let error {
                    self?.showSafariSettingsOpenFailed(error: error)
                    return
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func showSafariSettingsOpenFailed(error: Error) {
        os_log(.error, "MoneyMoney Helper: Safari-Einstellungen nicht öffnbar: %@", error.localizedDescription)
        webView.loadHTMLString(
            """
            <!DOCTYPE html><html><body style="font: -apple-system-body; margin: 2rem;">
            <p><strong>MoneyMoney Helper</strong></p>
            <p>Safari-Einstellungen konnten nicht geöffnet werden.</p>
            <p>Bitte manuell öffnen: Safari → Einstellungen → Erweiterungen → MoneyMoney Helper aktivieren.</p>
            <p>Auf macOS&nbsp;26+ „Websites bearbeiten“ nicht verwenden (Safari-Bug).</p>
            </body></html>
            """,
            baseURL: nil
        )
    }

}
