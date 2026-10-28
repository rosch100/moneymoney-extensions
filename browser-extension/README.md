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

### Safari (macOS) — empfohlen: DMG

1. [MoneyMoney Helper 0.9 DMG](https://github.com/rosch100/moneymoney-extensions/releases/tag/v0.9) laden und öffnen
2. **MoneyMoney Helper.app** nach Programme ziehen und einmal starten
3. Safari → **Einstellungen → Erweiterungen** → MoneyMoney Helper aktivieren
4. Auf der Bank-/Amazon-Seite Website-Zugriff erlauben (Toolbar)

Ohne Notarisierung ggf. *Systemeinstellungen → Datenschutz & Sicherheit → Trotzdem öffnen*.

#### Alternative: aus Xcode (Entwicklung)

Voraussetzung: **Xcode** (nicht nur Command Line Tools).

1. `safari-extension/MoneyMoney Helper/MoneyMoney Helper.xcodeproj` öffnen
2. Signing → Team; Destination **My Mac**
3. **Product → Run** (⌘R)
4. Safari → Erweiterungen → MoneyMoney Helper aktivieren

Unter **macOS 26 und neuer:** **„Websites bearbeiten“** nicht öffnen (Safari-Bug);
Zugriff über die Safari-Toolbar auf der Bank-Seite.

## Nutzung

Unterstützt: **Bank of America**, **Fidelity**, **MLP Versicherungen**, **Amazon.de**.
Presidential Bank und Shareview: Cookies manuell oder über den Hub (HAR).

1. Im Browser einloggen (inkl. MFA)
2. Kontoseite bzw. Vertragsübersicht öffnen
3. Extension-Icon → **Cookies kopieren**
4. In MoneyMoney als Passwort einfügen (`COOKIE:…`)

Gemeinsamer Ablauf und HAR-Alternative:
[Hub — Cookie-Import](https://github.com/rosch100/moneymoney-extensions#cookie-import-beta-extensions).

Entwicklung und Tests: [Hub — Entwicklung](https://github.com/rosch100/moneymoney-extensions#entwicklung-hub).
