# MoneyMoney Helper — Browser-Erweiterung

Kopiert Session-Cookies aus dem Browser ins Passwortfeld von MoneyMoney
(`COOKIE:…`). Für Chrome, Edge, Brave, Firefox und Safari.

## Warum eine Erweiterung?

Viele Session-Cookies sind für Skripte unsichtbar. Die Erweiterung liest sie
über die Cookie-Schnittstelle des Browsers.

## Installation

### Chrome / Edge / Brave

1. `chrome://extensions` (bzw. `edge://extensions`)
2. **Entwicklermodus** aktivieren
3. **Entpackte Erweiterung laden** → Ordner `browser-extension/` wählen

### Firefox

1. `about:debugging#/runtime/this-firefox`
2. **Temporäres Add-on laden** → `browser-extension/manifest.json`

### Safari (macOS)

Voraussetzung: **Xcode** oder **Xcode-beta** (nicht nur Command Line Tools).

Falls `xcode-select` noch auf die Command Line Tools zeigt:

```bash
# Standard-Xcode:
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
# oder Xcode-beta:
sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer
```

Danach in Xcode:

1. `safari-extension/MoneyMoney Helper/MoneyMoney Helper.xcodeproj` öffnen
2. Signing → Team auswählen (Apple-ID reicht für lokale Entwicklung)
3. Ziel/Destination: **My Mac**
4. **Product → Run** (⌘R)
5. Safari → **Einstellungen → Erweiterungen** → MoneyMoney Helper aktivieren

Fehler *„Please select an available device…“* → Destination auf **My Mac**
stellen (nicht iPhone/Simulator).

Unter **macOS 26 und neuer:** Erweiterung aktivieren. **„Websites bearbeiten“**
nicht öffnen (Safari-Bug). Website-Zugriff bei Bedarf über die Safari-Toolbar
auf der Bank-Seite erlauben.

## Nutzung

Unterstützt: **Bank of America**, **Fidelity**, **MLP Versicherungen**.
Presidential Bank und Shareview: Cookies manuell oder über den Hub (HAR).

1. Im Browser einloggen (inkl. MFA)
2. Kontoseite bzw. Vertragsübersicht öffnen
3. Extension-Icon → **Cookies kopieren**
4. In MoneyMoney als Passwort einfügen (`COOKIE:…`)

Gemeinsamer Ablauf und HAR-Alternative:
[Hub — Cookie-Import](https://github.com/rosch100/moneymoney-extensions#cookie-import-beta-extensions).

Entwicklung und Tests: [Hub — Entwicklung](https://github.com/rosch100/moneymoney-extensions#entwicklung-hub).
