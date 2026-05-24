# MoneyMoney Extensions (US-Banken)

Inoffizielle [MoneyMoney](https://moneymoney.app)-Extensions für US-Finanzinstitute, die keinen normalen Login in Lua erlauben.

## Extensions

| Datei | Bank | Modus |
|-------|------|-------|
| `extensions/Bank of America.lua` | Bank of America | Cookie-Import |
| `extensions/Fidelity.lua` | Fidelity Investments | Cookie-Import |
| `extensions/Presidential Bank.lua` | Presidential Bank | Login + MFA oder Cookie-Import |
| `extensions/Fidelity NetBenefits.lua` | Fidelity NetBenefits | Klassischer Login (experimentell) |

## Installation

1. `.lua`-Dateien aus `extensions/` nach:

   `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/`

   (In MoneyMoney: **Hilfe → Zeige Datenbank im Finder** → Ordner `Extensions`)

2. **Einstellungen → Erweiterungen** → Signaturprüfung deaktivieren (Extensions sind unsigniert).

3. MoneyMoney neu starten.

## Cookie-Import (BoA, Fidelity, Presidential)

Diese Banken verschlüsseln Login-Daten im Browser (RSA/JavaScript) oder blockieren Bot-Traffic. Workaround: Session-Cookies aus dem Browser übernehmen.

**In MoneyMoney:**

- Benutzername: wie gewohnt
- Passwort: `COOKIE:` + Cookie-String (Semikolon-getrennt)

Beispiel: `COOKIE:SMSESSION=eyJ...;SSOTOKEN=eyJ...`

### Userscript: Browser und Erweiterungen

Das Skript `scripts/moneymoney-cookie-exporter.user.js` läuft **nur mit [Tampermonkey](https://www.tampermonkey.net/)**. Andere Userscript-Manager (**Violentmonkey**, **Greasemonkey**, Safari **Userscripts**) unterstützen `GM.cookie` nicht — damit fehlen HttpOnly-Session-Cookies.

| Browser | Erweiterung | HttpOnly (BoA/Fidelity/Presidential) | Voraussetzung |
|---------|-------------|--------------------------------------|---------------|
| **Google Chrome** | [Tampermonkey](https://chromewebstore.google.com/detail/tampermonkey/dhdgffkkebhmkfjojejmpbldmpobfkfo) | Ja | Cookie-Zugriff: **Alle** (siehe unten) |
| **Microsoft Edge** | [Tampermonkey](https://microsoftedge.microsoft.com/addons/detail/tampermonkey/iikmkjmpaadaobahmlepeloendndfphd) | Ja | Cookie-Zugriff: **Alle** |
| **Mozilla Firefox** | [Tampermonkey](https://addons.mozilla.org/firefox/addon/tampermonkey/) | Ja (meist) | Cookie-Zugriff: **Alle**; bei Problemen Tampermonkey-Beta testen |
| **Safari (macOS)** | [Tampermonkey](https://apps.apple.com/app/tampermonkey/id1482490089) | **Nein** | Safari blockiert HttpOnly-Zugriff — Userscript nur für sichtbare Cookies nutzlos ([Details](https://github.com/Tampermonkey/tampermonkey/issues/2252)) |

**Tampermonkey-Einstellung (Chrome/Firefox/Edge, Pflicht für Session-Cookies):**

1. Tampermonkey-Dashboard öffnen
2. **Einstellungen** → Konfigurationsmodus: **Erweitert**
3. **Sicherheit** → **Cookie-Zugriff für Skripte: Alle** (nicht „Nur sichtbare“)

Ohne diese Einstellung liefert das Skript nur `document.cookie` — bei BoA fehlen dann `SMSESSION`, `SSOTOKEN` usw.

#### So verwenden (Chrome, Firefox, Edge)

1. Tampermonkey installieren
2. Neues Skript → Inhalt von `scripts/moneymoney-cookie-exporter.user.js` einfügen → speichern
3. Cookie-Zugriff auf **Alle** stellen (s.o.)
4. Bei der Bank einloggen und die richtige Seite öffnen:
   - **BoA:** `secure.bankofamerica.com` (Kontoübersicht, z. B. `account-details.go`)
   - **Fidelity:** `digital.fidelity.com` (Portfolio)
   - **Presidential:** `www.presidentialpcbanking.com` (Dashboard nach Login)
5. Button **MM** oben rechts (oder **Alt+C**) → **Cookies kopieren**
6. In MoneyMoney als **Passwort** einfügen (`COOKIE:…` ist bereits im Export enthalten)

Das Skript erkennt die Bank automatisch anhand der URL.

#### Safari

Tampermonkey installierbar, aber **kein HttpOnly** → Session-Export schlägt fehl. Statt Userscript:

- **Variante A** (HAR + Python-Skripte) — empfohlen
- **Variante D** ([crul](https://github.com/KieranHunt/crul) CLI, liest Safari-Cookie-DB)

### HttpOnly — alle Methoden im Vergleich

Session-Cookies (BoA `SMSESSION`, Presidential `rftoken`) sind **HttpOnly** — unsichtbar für `document.cookie`.

| Methode | HttpOnly | Browser |
|---------|----------|---------|
| Userscript + Tampermonkey `GM.cookie` | Ja | Chrome, Firefox, Edge |
| Userscript + Tampermonkey `GM.cookie` | Nein | Safari |
| HAR + `scripts/extract-*-cookies.py` | Ja | Alle |
| [Get cookies.txt LOCALLY](https://github.com/kairi003/Get-cookies.txt-LOCALLY) | Ja | Chrome, Firefox |
| [crul](https://github.com/KieranHunt/crul) (CLI) | Ja | Chrome, Firefox, Safari |

### Cookies beschaffen

**Variante A — HAR (alle Banken)**

1. Einloggen, Konto/Portfolio öffnen.
2. DevTools → Network → HAR exportieren.
3. Skript ausführen:

   ```bash
   python3 scripts/extract-boa-cookies.py export.har
   python3 scripts/extract-fidelity-cookies.py export.har
   python3 scripts/extract-presidential-cookies.py export.har
   ```

4. Ausgabe als Passwort in MoneyMoney einfügen.

**Variante B — Userscript**

Siehe Abschnitt [Userscript: Browser und Erweiterungen](#userscript-browser-und-erweiterungen) oben.

**Variante C — Cookie-Extension (ohne HAR)**

[Get cookies.txt LOCALLY](https://github.com/kairi003/Get-cookies.txt-LOCALLY) installieren, auf der Bank-Seite JSON exportieren, relevante Cookies als `COOKIE:name=value;…` zusammenstellen. HttpOnly ist enthalten.

**Variante D — CLI crul (macOS, inkl. Safari)**

```bash
npx --yes @kieranhunt/crul --url https://secure.bankofamerica.com --browsers safari --output -
```

Ausgabe ist Netscape-Format; für MoneyMoney nur `name=value`-Paare mit `COOKIE:`-Prefix kombinieren, oder HAR-Skript als Vorlage nutzen.

**Variante E — Manuell (BoA)**

DevTools → Network → `account-details.go` → Request Headers → **Cookie** (vollständiger Header).

### Hinweise

- Cookies verfallen schnell. Direkt nach Login exportieren.
- Protokollfenster bei Fehlern: **Fenster → Protokollfenster**.
- Presidential Bank: MFA-Login liefert oft kein `rftoken` an MoneyMoney — Cookie-Import aus HAR/Extension zuverlässiger.

## Warum der Umweg?

MoneyMoney-Extensions laufen in Lua ohne JavaScript und ohne externe Programme:

| Fehlende Funktion | Auswirkung |
|-------------------|------------|
| JavaScript-Ausführung | Login mit clientseitiger Verschlüsselung (BoA, Fidelity) |
| Externe Prozesse | RSA-Verschlüsselung |
| HttpOnly nach MFA | Presidential: Session unvollständig |
| Offizieller Session-Import | Workaround über Passwortfeld `COOKIE:…` |

## Entwicklung

```bash
lua test_boa.lua
```

## Lizenz

MIT — siehe Extension-Dateien.

## Haftung

Inoffiziell, ohne Garantie. Nutzung auf eigenes Risiko.
