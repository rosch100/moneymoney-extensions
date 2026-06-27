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

Falls `xcode-select` noch auf CLT zeigt, reicht oft:

```bash
sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer
```

(`build-safari-extension.sh` findet Xcode/Xcode-beta alternativ automatisch über `DEVELOPER_DIR`.)

```bash
./scripts/build-safari-extension.sh
```

Danach in Xcode:

1. `safari-extension/MoneyMoney Helper/MoneyMoney Helper.xcodeproj` öffnen
2. Signing → Team auswählen (Apple-ID reicht für lokale Entwicklung)
3. **Ziel/Destination:** `My Mac` (in der Xcode-Toolbar neben dem Scheme „MoneyMoney Helper“)
4. **Product → Run** (⌘R) — startet Safari mit temporärer Extension
5. Safari → **Einstellungen → Erweiterungen** → MoneyMoney Helper aktivieren

> Fehler *„Please select an available device…“* → Destination oben in Xcode auf **My Mac** stellen (nicht iPhone/iOS-Simulator).

Das generierte Projekt liegt in `safari-extension/` (gitignored, bei Bedarf neu erzeugen).

Alternativ ohne Build-Skript (Xcode installiert):

```bash
xcrun safari-web-extension-converter browser-extension \
  --app-name "MoneyMoney Helper" \
  --swift --copy-resources --project-location safari-extension
```

## Nutzung

1. Im Browser einloggen (inkl. MFA)
2. Kontoseite öffnen (siehe README: bank-spezifische Hinweise)
3. Extension-Icon → **Cookies kopieren**
4. In MoneyMoney Passwortfeld einfügen (`COOKIE:…`)

## Architektur

| Datei | Zweck |
|-------|--------|
| `cookie-export-banks.json` | SSOT: Banken, Domains, Cookie-Priorität |
| `config.js` | JSON laden, `browser`/`chrome`-API |
| `cookie-export.js` | Sammeln, Formatieren, Validierung |
| `popup.js` | UI-Logik |

Icons: `python3 scripts/generate-extension-icons.py`

## Berechtigungen (Minimalprinzip)

- `cookies` — lesen (kein Schreiben)
- `host_permissions` — nur Fidelity, BoA, MLP-Domains
- Kein `activeTab`, kein `clipboardWrite` (Clipboard via Nutzerklick im Popup)

## Entwicklung

Konfiguration oder Logik geändert → Extension in `chrome://extensions` neu laden.

Tests:

```bash
python3 tests/test_cookie_export_config.py
python3 tests/test_external_scripts_conformance.py
```
