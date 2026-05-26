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

Cookie-Import ist bei den US-Banken und MLP nötig, weil ihr Web-Login auf clientseitige RSA-Verschlüsselung (BoA), Akamai-Bot-Schutz (Fidelity), HttpOnly-Cookies nach MFA (Presidential) oder JOSE/JWE-Verschlüsselung (MLP) angewiesen ist — Mechanismen, die ohne Browser-Runtime in der Lua-Engine nicht nachbildbar sind. Shareview funktioniert direkt aus MoneyMoney heraus mit MFA.

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

**Benötigte Cookies:** `VUSESSIONID` (von `vue.mlp.de`), `BIGipServervue.mlp.de`, optional `CAS_SESSION`, `CAS_S_SESSION`, `CAS_DEVICE_SESSION` (für Consent)

## Cookie-Import (BoA, Fidelity, Presidential, MLP)

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
python3 scripts/extract-mlp-cookies.py export.har
```

Cookies nach dem Login zeitnah exportieren — die Session läuft sonst ab.

### MLP Versicherungen

**Hinweis:** Diese Extension unterstützt nur **Versicherungsverträge** (Lebensversicherung, BU, etc.) aus dem MLP Kundenportal. Bank-Produkte (Konten, Depots) werden über separate Schnittstellen abgedeckt.

Die MLP-API erfordert **JOSE/JWE-Verschlüsselung** für Username/Passwort-Login. Daher wird **Cookie-Import** empfohlen.

**⚠️ SSL-Zertifikat bestätigen**

Beim ersten Zugriff fragt MoneyMoney nach dem SSL-Zertifikat für `vue.mlp.de`. Bitte auf **"Immer"** klicken.

**Benötigte Cookies (nur für Vue API):**

| Cookie | Domain | Zweck | Gültigkeit |
|--------|--------|-------|------------|
| **`VUSESSIONID`** ⚠️ | **`vue.mlp.de`** | **Vue-App-Session (ERFORDERLICH)** | Session |
| `BIGipServervue.mlp.de` | `vue.mlp.de` | Load-Balancer | Session |

**Hinweis:** Die `CAS_SESSION`, `CAS_S_SESSION`, `CAS_DEVICE_SESSION` Cookies werden für die **Vue API nicht benötigt** - diese verwendet eine separate `VUSESSIONID`-Session!

**⚠️ Wichtig:** `VUSESSIONID` wird unter der Domain **`vue.mlp.de`** gesetzt (nicht `kundenportal.mlp.de`!). Daher muss im Browser die **Vertragsübersicht** geöffnet werden, damit dieses Cookie verfügbar ist.

**1. Tampermonkey (empfohlen):**

Tampermonkey installieren, `scripts/moneymoney-cookie-exporter.user.js` hinzufügen. Nach Login auf kundenportal.mlp.de **und Öffnen der Vertragsübersicht** erscheint ein "MM"-Button → "Cookies kopieren".

**2. HAR-Export:**

```bash
# 1. Im Browser anmelden: https://kundenportal.mlp.de
# 2. Vertragsübersicht öffnen (wichtig für VUSESSIONID!)
# 3. DevTools → Network → Rechtsklick → "Save all as HAR"
python3 scripts/extract-mlp-cookies.py export.har
```

**3. Manuelles Kopieren:**

1. Im Browser anmelden: `https://kundenportal.mlp.de`
2. **Vertragsübersicht öffnen** (wichtig für `VUSESSIONID`!)
3. DevTools → Application → Cookies → `https://vue.mlp.de`:
   - **`VUSESSIONID`** (⚠️ kann mehrfach vorkommen - beide kopieren!)
   - `BIGipServervue.mlp.de`

In MoneyMoney als **Passwort** eintragen:
```
COOKIE:VUSESSIONID=xxx;BIGipServervue.mlp.de=yyy
```

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
