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

### HttpOnly — was geht wo?

Session-Cookies (BoA `SMSESSION`, Presidential `rftoken`) sind **HttpOnly** — absichtlich unsichtbar für `document.cookie` und die Cookie Store API.

| Methode | HttpOnly | Browser |
|---------|----------|---------|
| Userscript + Tampermonkey `GM.cookie` | Ja | Chrome, Firefox, Edge (Einstellung nötig) |
| Userscript + Tampermonkey `GM.cookie` | **Nein** | Safari ([Tampermonkey #2252](https://github.com/Tampermonkey/tampermonkey/issues/2252)) |
| HAR + `scripts/extract-*-cookies.py` | Ja | Alle |
| [Get cookies.txt LOCALLY](https://github.com/kairi003/Get-cookies.txt-LOCALLY) | Ja | Chrome, Firefox |
| [crul](https://github.com/KieranHunt/crul) (CLI) | Ja | Chrome, Firefox, Safari (Cookie-DB) |

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

**Variante B — Userscript (Chrome/Firefox/Edge)**

Tampermonkey mit `GM.cookie` — liest HttpOnly über die Browser-Cookies-API.

1. [Tampermonkey](https://www.tampermonkey.net/) installieren.
2. `scripts/moneymoney-cookie-exporter.user.js` anlegen.
3. Tampermonkey → **Erweitert** → **Sicherheit** → **Cookie-Zugriff: Alle**.
4. Einloggen. BoA: **secure.bankofamerica.com** (Kontoübersicht).
5. **MM** (Alt+C) → **Cookies kopieren** → in MoneyMoney einfügen.

**Safari:** Userscript reicht nicht für HttpOnly → Variante A, C oder D.

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
