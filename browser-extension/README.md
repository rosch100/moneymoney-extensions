# MoneyMoney Helper — Browser Extension

WebExtension (Manifest V3) für Chrome, Edge, Brave, Firefox und Safari.

## Warum Extension statt Userscript?

Session-Cookies wie `SMSESSION`, `ATC` oder `VUSESSIONID` sind **HttpOnly**. Userscripts sehen sie oft nicht (besonders in Safari). Die Extension nutzt die offizielle `cookies`-API des Browsers.

## Installation

### Chrome / Edge / Brave

1. `chrome://extensions` (bzw. `edge://extensions`)
2. **Entwicklermodus** aktivieren
3. **Entpackte Erweiterung laden** → Ordner `browser-extension/` wählen

### Firefox

1. `about:debugging#/runtime/this-firefox`
2. **Temporäres Add-on laden** → `browser-extension/manifest.json`

### Safari (macOS)

Safari benötigt ein Xcode-Projekt als Hülle. Voraussetzung: **Xcode** oder **Xcode-beta** (nicht nur Command Line Tools).

Zuerst WebExtension-Dateien nach Safari syncen (siehe [Entwicklung](#entwicklung)).

Falls `xcode-select` noch auf die Command Line Tools zeigt, auf die installierte Xcode-App umstellen (Pfad anpassen):

```bash
# Standard-Xcode:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# oder Xcode-beta:
sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer
```

Danach in Xcode:

1. `safari-extension/MoneyMoney Helper/MoneyMoney Helper.xcodeproj` öffnen
2. Signing → Team auswählen (Apple-ID reicht für lokale Entwicklung)
3. **Ziel/Destination:** `My Mac` (in der Xcode-Toolbar neben dem Scheme „MoneyMoney Helper“)
4. **Product → Run** (⌘R) — startet Safari mit temporärer Extension
5. Safari → **Einstellungen → Erweiterungen** → MoneyMoney Helper aktivieren

> Fehler *„Please select an available device…“* → Destination oben in Xcode auf **My Mac** stellen (nicht iPhone/iOS-Simulator).

Alternativ ohne bestehendes Projekt (Xcode installiert):

```bash
xcrun safari-web-extension-converter browser-extension \
  --app-name "MoneyMoney Helper" \
  --swift --copy-resources --project-location safari-extension
```

## Nutzung

Konfiguriert sind **Bank of America**, **Fidelity** und
**MLP Versicherungen**. Presidential Bank und Shareview werden von der
Browser-Extension derzeit nicht exportiert; deren optionaler Cookie-Import
erfolgt manuell.

1. Im Browser einloggen (inkl. MFA)
2. Kontoseite öffnen (siehe README: bank-spezifische Hinweise)
3. Extension-Icon → **Cookies kopieren**
4. In MoneyMoney Passwortfeld einfügen (`COOKIE:…`)

## Architektur

| Datei | Zweck |
|-------|--------|
| `cookie-export-banks.json` | SSOT: Banken, Origins, Cookie-Priorität |
| `config.js` | JSON laden, `browser`/`chrome`-API |
| `cookie-export.js` | Sammeln, Formatieren, Validierung |
| `popup.js` | UI-Logik |

Icons: `python3 scripts/generate-extension-icons.py`

## Berechtigungen (Minimalprinzip)

- `cookies` — lesen (kein Schreiben)
- `host_permissions` — konkrete Origins aus `cookie-export-banks.json` (keine `*.domain`-Wildcards; Safari 27 crasht sonst in Websites Preferences); Cookie-Abfrage nur über diese Origins
- Kein `activeTab`, kein `clipboardWrite` (Clipboard via Nutzerklick im Popup)

**Neue Bank oder Subdomain:** Jede Hostname, von der Session-Cookies gelesen werden müssen, braucht einen eigenen `https://`-Eintrag in `origins` (und damit in `host_permissions`). `session_host` muss in `origins` enthalten sein. Danach `python3 scripts/sync_safari_extension_resources.py` ausführen.

### Safari / macOS 27

Extension in **Safari → Einstellungen → Erweiterungen** aktivieren. **„Websites bearbeiten“ / Edit Websites** nicht öffnen (Safari-Bug). Website-Zugriff bei Bedarf über die Safari-Toolbar auf der Bank-Seite erlauben.

## Entwicklung

Konfiguration oder Logik in `browser-extension/` geändert:

```bash
python3 scripts/sync_safari_extension_resources.py
```

Danach Chrome/Firefox neu laden bzw. Safari per Xcode Run. Das Sync-Skript leitet `host_permissions` aus `cookie-export-banks.json` ab, kopiert Shared Resources und entfernt verwaiste Safari-Dateien.

Tests:

```bash
python3 tests/test_browser_extension_manifest.py
python3 tests/test_cookie_export_config.py
node tests/test_cookie_export.mjs
python3 tests/test_external_scripts_conformance.py
```
