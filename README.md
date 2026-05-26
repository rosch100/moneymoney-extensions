# MoneyMoney Extensions

Inoffizielle Web-Banking-Extensions für [MoneyMoney](https://moneymoney.app).

## Extensions

| Datei | Service | Login |
|-------|---------|-------|
| `extensions/Bank of America.lua` | Bank of America | Cookie-Import |
| `extensions/Fidelity.lua` | Fidelity Investments | Cookie-Import |
| `extensions/Presidential Bank.lua` | Presidential Bank | Cookie-Import |
| `extensions/Shareview.lua` | Equiniti Shareview Portfolio (UK) | Direct-Login (Username + Passwort + Geburtsdatum + MFA) |
| `extensions/MLP Versicherungen.lua` | MLP Versicherungen | Cookie-Import (Login-API erfordert JOSE/JWE-Verschlüsselung) |

Cookie-Import ist bei den US-Banken und MLP erforderlich, da deren Web-Login Mechanismen nutzt (RSA-Verschlüsselung, Akamai-Bot-Schutz, JOSE/JWE), die in der Lua-Engine ohne Browser-Runtime nicht nachgebildet werden können. Shareview unterstützt Direct-Login mit MFA.

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

Bei falsch eingegebenem MFA-Code fragt MoneyMoney nur den Code erneut ab — Benutzername, Passwort und Geburtsdatum bleiben erhalten. Drei aufeinanderfolgende Fehleingaben sperren das Konto bei Shareview temporär.

## MLP Versicherungen-Login

| Feld | Eingabe | Hinweis |
|------|---------|---------|
| Benutzername | (leer lassen) | Bei Cookie-Import |
| Passwort | `COOKIE:name=value;...` | Siehe Cookie-Import unten |
| ODER Benutzername | MLP Benutzerkennung | Falls Username/Passwort versucht werden soll |
| ODER Passwort | MLP Passwort | Extension versucht automatisch Cookie-Fallback bei JOSE-Fehler |

**Hinweis:** Die MLP-Login-API erwartet Credentials im **JOSE/JWE-Format** (RSA-OAEP-512 mit A256GCM). Diese clientseitige Verschlüsselung ist in Lua nicht nachbildbar. Daher wird **Cookie-Import empfohlen**.

**Benötigte Cookies:** `VUSESSIONID` (von `vue.mlp.de`), `BIGipServervue.mlp.de`. Optional für Sitzungserneuerung: `CAS_SESSION`, `CAS_S_SESSION`, `CAS_DEVICE_SESSION`.

## Cookie-Import (BoA, Fidelity, Presidential, MLP)

Cookies aus eingeloggtem Browser exportieren und im MoneyMoney-Passwortfeld als Wert mit `COOKIE:`-Präfix eintragen:

```
COOKIE:name=value;name2=value2
```

Benutzername bleibt unverändert.

### Cookie-Export via Tampermonkey (Chrome / Edge / Firefox)

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

### Cookie-Export via HAR-Datei (alle Browser)

Falls Tampermonkey nicht verfügbar ist (z. B. in Safari) oder nicht alle Cookies erfasst, können die Cookies aus einer HAR-Datei (HTTP Archive) extrahiert werden.

1.  Im Browser bei der Bank anmelden.
2.  **Wichtig:** Die Seite mit den Kontodaten bzw. der Vertragsübersicht öffnen.
3.  DevTools öffnen (**F12** oder **Cmd+Alt+I**) → Tab **Network**.
4.  Seite neu laden (optional, um alle Cookies im Flow zu sehen).
5.  Rechtsklick in die Liste der Netzwerkanfragen → **Save all as HAR**.
6.  Passendes Skript aus dem `scripts/`-Ordner ausführen:

| Bank / Service | Befehl |
|----------------|--------|
| Bank of America | `python3 scripts/extract-boa-cookies.py export.har` |
| Fidelity | `python3 scripts/extract-fidelity-cookies.py export.har` |
| Presidential Bank | `python3 scripts/extract-presidential-cookies.py export.har` |
| MLP Versicherungen | `python3 scripts/extract-mlp-cookies.py export.har` |
| Shareview (Fallback) | `python3 scripts/extract-shareview-cookies.py export.har` |

Das Skript gibt den fertigen `COOKIE:...`-String aus und kopiert ihn (unter macOS) automatisch in die Zwischenablage. Diesen Wert in MoneyMoney als Passwort einfügen.

Cookies nach dem Login zeitnah exportieren — die Session läuft sonst ab.

### MLP Versicherungen

**Hinweis:** Diese Extension unterstützt ausschließlich **Versicherungsverträge**. Bank-Produkte werden separat abgedeckt.

Da der MLP-Login eine clientseitige **JOSE/JWE-Verschlüsselung** erfordert, ist ein direkter Login in Lua nicht möglich. **Cookie-Import wird zwingend empfohlen.**

**⚠️ SSL-Zertifikat bestätigen**
Beim ersten Zugriff muss das SSL-Zertifikat für `vue.mlp.de` in MoneyMoney dauerhaft bestätigt werden.

**Benötigte Cookies (nur für Vue API):**

| Cookie | Domain | Zweck |
|--------|--------|-------|
| **`VUSESSIONID`** ⚠️ | **`vue.mlp.de`** | **Session (ERFORDERLICH)** |
| `BIGipServervue.mlp.de` | `vue.mlp.de` | Load-Balancer |

**Wichtig:** `VUSESSIONID` wird nur unter der Domain **`vue.mlp.de`** gesetzt. Öffnen Sie im Browser zwingend die **Vertragsübersicht**, bevor Sie die Cookies exportieren. Falls `VUSESSIONID` mehrfach vorkommt, kopieren Sie alle Werte.

**1. Tampermonkey (empfohlen):**
`scripts/moneymoney-cookie-exporter.user.js` nutzen. Nach dem Login die Vertragsübersicht öffnen, dann "Cookies kopieren".

**2. HAR-Export:**
Siehe oben unter "Cookie-Export via HAR-Datei".

**3. Manuelles Kopieren:**
DevTools → Application → Cookies → `https://vue.mlp.de`: Alle `VUSESSIONID` und `BIGipServervue.mlp.de` kopieren.

## Entwicklung

### Lokale Tests

```bash
lua tests/test_shareview.lua
lua tests/test_mlp_kundenportal.lua
```

### CI

GitHub Actions führt bei jedem Push/Pull Request automatisch aus:

- Lua-Unit-Tests (alle `tests/*.lua`)
- Lua-Syntax-Check (alle `*.lua`)
- Python-Syntax-Check (alle `*.py`)
- JavaScript-Syntax-Check (alle `*.js`)

Siehe [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## API-Referenz

Pro Extension: [docs/LUA-EXTENSIONS.md](docs/LUA-EXTENSIONS.md).
Engine-Spezifikation: [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/).

## Lizenz

MIT
