# MoneyMoney Extensions

Inoffizielle Web-Banking-Extensions für [MoneyMoney](https://moneymoney.app).

## Extensions

| Datei | Service | Login |
|-------|---------|-------|
| `extensions/Bank of America.lua` | Bank of America | Cookie-Import |
| `extensions/Fidelity.lua` | Fidelity Investments | Cookie-Import |
| `extensions/Presidential Bank.lua` | Presidential Bank | Cookie-Import |
| `extensions/Shareview.lua` | Equiniti Shareview Portfolio (UK) | Direct-Login (Username + Passwort + Geburtsdatum + MFA) |

Die US-Banken erfordern Cookie-Import, weil ihr Web-Login auf clientseitige Verschlüsselung (BoA), Bot-Schutz (Fidelity) oder HttpOnly-Cookies nach MFA (Presidential) angewiesen ist — Mechanismen, die in der MoneyMoney-Lua-Engine ohne Browser-Runtime nicht abbildbar sind. Shareview-Login funktioniert direkt aus MoneyMoney.

## Installation

1. `.lua` aus `extensions/` nach
   `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/`
2. In MoneyMoney die Signaturprüfung für Extensions deaktivieren, neu starten.

## Shareview-Login

| Feld | Eingabe |
|------|---------|
| Benutzername | `username` oder `username\|TT.MM.JJJJ` |
| Passwort | Shareview-Passwort |
| Geburtsdatum | nur Multi-Step: wird abgefragt, falls nicht im Benutzernamen enthalten |
| MFA-Code | 6-stellig aus Shareview-App oder E-Mail (von MoneyMoney abgefragt) |

Mit Pipe-Suffix (`name|01.01.1970`) speichert MoneyMoney das Geburtsdatum im Keychain. Nur diese Variante funktioniert für automatische Background-Syncs; ohne Pipe-Suffix fragt MoneyMoney das Geburtsdatum bei jedem Login interaktiv ab.

## Cookie-Import (BoA, Fidelity, Presidential)

Cookies aus eingeloggtem Browser exportieren und im MoneyMoney-Passwortfeld als Wert mit `COOKIE:`-Präfix eintragen:

```
COOKIE:name=value;name2=value2
```

Benutzername bleibt unverändert.

### Tampermonkey (Chrome / Edge / Firefox)

Nur Tampermonkey kann HttpOnly-Cookies lesen (`GM.cookie`).

| Browser | Erweiterung |
|---------|-------------|
| Chrome | [Tampermonkey](https://chromewebstore.google.com/detail/tampermonkey/dhdgffkkebhmkfjojejmpbldmpobfkfo) |
| Edge | [Tampermonkey](https://microsoftedge.microsoft.com/addons/detail/tampermonkey/iikmkjmpaadaobahmlepeloendndfphd) |
| Firefox | [Tampermonkey](https://addons.mozilla.org/firefox/addon/tampermonkey/) |
| Safari | [Tampermonkey](https://apps.apple.com/app/tampermonkey/id1482490089) — HttpOnly blockiert ([#2252](https://github.com/Tampermonkey/tampermonkey/issues/2252)) |

In Tampermonkey: **Erweitert → Sicherheit → Cookie-Zugriff: Alle**.

1. `scripts/moneymoney-cookie-exporter.user.js` installieren.
2. Bei der Bank einloggen, passende Seite öffnen:
   - BoA: `secure.bankofamerica.com` (Kontoübersicht)
   - Fidelity: `digital.fidelity.com`
   - Presidential: `www.presidentialpcbanking.com`
3. **Alt+C** → Cookies kopieren → in MoneyMoney als Passwort einfügen.

### Safari und Fallback

| Methode | Browser |
|---------|---------|
| HAR-Export + `scripts/extract-<bank>-cookies.py` | alle |
| [Get cookies.txt LOCALLY](https://github.com/kairi003/Get-cookies.txt-LOCALLY) | Chrome, Firefox |
| [crul](https://github.com/KieranHunt/crul) | Chrome, Firefox, Safari |
| DevTools → Network → Request Header `Cookie` | alle |

HAR-Variante:

```bash
python3 scripts/extract-boa-cookies.py export.har
python3 scripts/extract-fidelity-cookies.py export.har
python3 scripts/extract-presidential-cookies.py export.har
```

Cookies nach dem Login zeitnah exportieren — die Session läuft sonst ab.

## API-Referenz

Pro Extension: [docs/LUA-EXTENSIONS.md](docs/LUA-EXTENSIONS.md).
Engine-Spezifikation: [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/).

## Lizenz

MIT
