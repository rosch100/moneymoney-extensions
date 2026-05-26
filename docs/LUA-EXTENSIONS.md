# Lua-Extensions — MoneyMoney Web Banking API

API-Referenz pro Extension. Engine-Spezifikation: [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/). Installation: siehe [README](../README.md).

## Engine-Ablauf

1. `SupportsBank`
2. `InitializeSession` bzw. `InitializeSession2`
3. `ListAccounts`
4. `RefreshAccount` pro Konto
5. optional: Kontoauszüge (`GetAvailableStatements`, `GetStatement`, …)
6. `EndSession`

Fehler erscheinen im Protokollfenster (**Fenster → Protokollfenster**).

---

## Bank of America

**Datei:** `extensions/Bank of America.lua`

### Registrierung

```lua
WebBanking{
  version     = 1.00,
  url         = "https://secure.bankofamerica.com",
  services    = {"Bank of America"},
  description = "Bank of America - Cookie Import"
}
```

| Feld | Wert |
|------|------|
| Service | Bank of America |
| Währung | USD |
| Login | nur Cookie-Import (clientseitige RSA-Verschlüsselung im Browser nicht in Lua nachbildbar) |

### `InitializeSession(protocol, bankCode, username, username2, password, username3)`

Passwort mit `COOKIE:`-Präfix → Session-Cookies setzen, Zugang zu `secure.bankofamerica.com` prüfen. Sonst → Fehlertext (Login-API nicht unterstützt).

### `ListAccounts(knownAccounts)`

HTML von `account-details.go`. Konten aus `TL_NPI_AcctName` / „Ending in".  
Felder: `name`, `accountNumber` (letzte 4 Ziffern), `bankCode`, `currency`, `type`, `attributes = {"statements"}`.  
Typen: `AccountTypeCreditCard` oder `AccountTypeGiro`.

### `RefreshAccount(account, since)`

| Feld | Inhalt |
|------|--------|
| `balance` | Kontostand (Kreditkarte: Statement Balance negativ) |
| `transactions` | Umsätze ab `since`, neueste zuerst |

Umsatzfelder: `bookingDate`, `valutaDate`, `amount`, `purpose`, `name`, `bookingText`, `endToEndReference` (Detail-POST).  
Datenquelle: HTML Activity-Seiten (`stmtFromDateList`).

### Kontoauszüge

| Funktion | Zweck |
|----------|-------|
| `GetAvailableStatements(account, since)` | Metadaten verfügbarer PDF-Auszüge |
| `GetStatement(account, statementId)` | PDF-Binary |
| `FetchStatements(accounts, knownIdentifiers)` | Batch-Download neuer Auszüge |
| `DownloadStatement(account, statement)` | Alias zu `GetStatement` |

`statementId`-Format: `docId|adxToken`.

### `EndSession()`

Kein Server-Logout (Session für Kontoauszüge erhalten).

---

## Fidelity Investments

**Datei:** `extensions/Fidelity.lua`

### Registrierung

```lua
WebBanking{
  version     = 1.00,
  url         = "https://www.fidelity.com",
  services    = {"Fidelity"},
  description = "Fidelity Investments - GraphQL, Cookie Import"
}
```

| Feld | Wert |
|------|------|
| Service | Fidelity bzw. Fidelity Investments |
| Währung | USD |
| Kontotyp | Wertpapierdepot (`AccountTypePortfolio`) |
| Login | Cookie-Import (Login-API durch Akamai-Bot-Schutz blockiert) |

### `InitializeSession(...)`

`COOKIE:…` → Cookies übernehmen, Portfolio-Seite testen. Klartext-Passwort → Login-API (in der Praxis selten erfolgreich).

### `ListAccounts(knownAccounts)`

GraphQL `GetContext` → `person.assets`.  
Felder: `name`, `accountNumber`, `portfolio`, `currency`, `type`, `bankCode`.

### `RefreshAccount(account, since)`

GraphQL `GetPositions`. `since` wird ignoriert.

| Feld | Inhalt |
|------|--------|
| `balance` | Summe Marktwerte |
| `securities` | Positionen (`name`, `isin`, `quantity`, `amount`, …) |

### `EndSession()`

Optionaler GET Logout-URL; Cookies bleiben für Folge-Aufrufe.

---

## Presidential Bank

**Datei:** `extensions/Presidential Bank.lua`

### Registrierung

```lua
WebBanking{
  version     = 1.00,
  url         = "https://www.presidentialpcbanking.com",
  services    = {"Presidential Bank"},
  description = "Presidential Bank - MFA and Cookie Import"
}
```

| Feld | Wert |
|------|------|
| Service | Presidential Bank |
| `bankCode` | 255073345 (ABA Routing Number) |
| Währung | USD |

### `InitializeSession2(protocol, bankCode, step, credentials, interactive)`

Zwei-Faktor-Flow gemäß [Anmeldung mit Zwei-Faktor-Authentifizierung](https://moneymoney.app/api/webbanking/#anmeldung-mit-zwei-faktor-authentifizierung). Folge-Steps werden state-basiert dispatcht (`waitingForMethodSelection`, `waitingForMfaCode`, `waitingForCookieImport`), damit Retry-Challenges unabhängig vom `step`-Zähler im richtigen Handler landen.

| Eingabe | Inhalt |
|---------|--------|
| Username + Passwort | initialer POST `external-login`, danach `login/redirect` |
| Passwort `COOKIE:…` | überspringt MFA, übernimmt `SESSION_TOKEN` und `rftoken` direkt |
| Methodenwahl | Auswahl aus `mfaMethods` (TOTP, SMS, E-Mail, Voice). Ungültige Auswahl → Retry-Challenge, State bleibt erhalten |
| MFA-Code | POST `mfa/submit`. Abgelehnter Code → Retry-Challenge mit aktualisiertem CSRF-Token, kein Full-Login-Restart |

Der MFA-Submit selbst funktioniert. Das anschließende `finalizeLogin` blockiert aktuell, weil der Bank-Server `rftoken` als HttpOnly setzt und MoneyMoney es daher nicht an die Extension durchreicht; ohne `rftoken` schlagen die nachgelagerten REST-Calls fehl. Solange das so bleibt, ist Cookie-Import (Passwort `COOKIE:SESSION_TOKEN=…;rftoken=…`) der zuverlässige Weg. Sobald `rftoken` zugänglich wird, läuft der MFA-Login ohne Codeänderung bis zum Ende durch.

### `ListAccounts(knownAccounts)`

REST `accts-olb/live/v1/history`.  
Felder: `name`, `accountNumber` (interne ID), `bankCode`, `currency`, `type`.

### `RefreshAccount(account, since)`

REST Transaktions-Endpoint.

| Feld | Inhalt |
|------|--------|
| `balance` | Kontostand |
| `transactions` | Umsätze ab `since` |

### `EndSession()`

Session-Cookies löschen.

---

## Equiniti Shareview Portfolio

**Datei:** `extensions/Shareview.lua`

### Registrierung

```lua
WebBanking{
  version     = 1.00,
  url         = "https://portfolio.shareview.co.uk",
  services    = {"Shareview"},
  description = "Equiniti Shareview Portfolio - Direct Login (Username + Password + DOB + MFA)"
}
```

| Feld | Wert |
|------|------|
| Service | Shareview |
| Währung | GBP (GBX/Pence wird automatisch nach GBP umgerechnet) |
| Kontotyp | Wertpapierdepot (`AccountTypePortfolio`) |
| Login | Username + Passwort + Geburtsdatum + 6-stelliger MFA-Code |

### `InitializeSession2(protocol, bankCode, step, credentials, interactive)`

Zwei-Faktor-Flow mit zusätzlichem Geburtsdatum-Step, falls dieses nicht im Benutzernamen mitgegeben wurde. Folge-Steps werden state-basiert dispatcht (`awaitingDob`, `awaitingMfa`).

| Schritt | Inhalt | Bedingung |
|---------|--------|-----------|
| 1  | Username + Passwort | immer |
| 1a | Geburtsdatum (`TT.MM.JJJJ`) | nur wenn der Username keinen `|TT.MM.JJJJ`-Suffix enthält |
| 2  | 6-stelliger MFA-Code | immer; bei Reject wird die MFA-Seite mit frischem ASP.NET-`VIEWSTATE` als Basis für den nächsten Versuch behalten und nur der Code neu abgefragt |

#### Username-Eingabe

| Variante | Wert | Verhalten |
|----------|------|-----------|
| Komfort | `max.mustermannmann|01.01.1970` | Geburtsdatum aus Pipe-Suffix, im macOS-Keychain verschlüsselt abgelegt. Funktioniert für Background-Syncs. |
| Multi-Step | `username` | MoneyMoney fragt das Geburtsdatum interaktiv nach. Funktioniert **nicht** für nicht-interaktive Background-Syncs. |

### `ListAccounts(knownAccounts)`

Eine konsolidierte Position „Shareview Portfolio" mit allen Holdings als Wertpapiere.  
Felder: `name`, `accountNumber = "shareview-portfolio"`, `portfolio = true`, `currency = "GBP"`, `type = AccountTypePortfolio`, `bankCode = "Shareview"`.

### `RefreshAccount(account, since)`

`since` wird ignoriert (Wertpapierdepot ohne Transaktionsliste).

| Feld | Inhalt |
|------|--------|
| `balance` | Total Indicative Value aus `holdingssummary.aspx` (in GBP) |
| `securities` | Positionen aus allen Web-Parts (Equiniti-administriert, Self-maintained Funds, Self-maintained Holdings) |

Pro Wertpapier:

| Feld | Quelle |
|------|--------|
| `name` | Companyname + ggf. Sub-Account |
| `isin` | Morningstar-Link `externalid=<ISIN>` |
| `securityNumber` | Shareholder Reference Number |
| `quantity` | Spalte „Quantity" |
| `price` | Spalte „Price" (GBX → GBP, geteilt durch 100) |
| `amount` | Spalte „Value" (GBX → GBP) |

Datenquelle: HTML der `holdingssummary.aspx`-Seite (ASP.NET WebForms / SharePoint), kein JSON-API.

### `EndSession()`

Optionaler GET auf `Logoff.aspx`; lokale Session-Cookies werden zurückgesetzt.

### Bekannte Einschränkungen

- Keine Transaktionen / Dividenden — nur aktuelles Portfolio.
- Drei aufeinanderfolgende falsche MFA-Codes sperren das Konto bei Shareview temporär.
- Nur GBP-Anzeige live verifiziert.

### Tests

```bash
lua tests/test_shareview.lua
```

---

## MLP Versicherungen

**Datei:** `extensions/MLP Versicherungen.lua`

### Registrierung

```lua
WebBanking{
  version     = 1.00,
  url         = "https://kundenportal.mlp.de",
  services    = {"MLP Versicherungen"},
  description = "MLP Versicherungen - Cookie-Import (VUSESSIONID von vue.mlp.de)"
}
```

| Feld | Wert |
|------|------|
| Service | MLP Versicherungen |
| Kontotyp | Wertpapierdepot (`AccountTypePortfolio`) |
| Login | Cookie-Import (JOSE/JWE-Verschlüsselung nicht in Lua umsetzbar) |

### Unterstützte Vertragstypen

| Typ | Name | Beschreibung |
|-----|------|--------------|
| `FLV` | Fondsgebundene Lebensversicherung | Aktienbasierte Lebensversicherung |
| `KLV` | Kapitallebensversicherung | Klassische Kapital-Lebensversicherung |
| `LV` | Lebensversicherung | Allgemeine Lebensversicherung |
| `REN` | Rentenversicherung | Rente im Alter |
| `BU` | Berufsunfähigkeitsversicherung | Absicherung bei BU |
| `BUZ` | Berufsunfähigkeits-Zusatz | Zusatzdeckung BU |
| `BAV` | Betriebliche Altersvorsorge | Arbeitgeberfinanziert |
| `RIESTER` | Riester-Rente | Geförderte Altersvorsorge |
| `RUERUP` | Rürup-Rente | Basisrente |
| *weitere* | Vorsorgevertrag | Alle weiteren Verträge |

### Login-API Limitation

Die MLP-Authentifizierungs-API (`/services_auth/auth-backend/api/authentication/login`) erfordert **JOSE/JWE-verschlüsselte Credentials** (`application/jose`, RSA-OAEP-512, A256GCM). Da die Lua-Engine keine native JWE-Unterstützung bietet, ist ein direkter Login technisch nicht möglich.

**Lösung:** Cookie-Import aus einer authentifizierten Browser-Sitzung.

### `InitializeSession(protocol, bankCode, username, username2, password, username3)`

`password` mit `COOKIE:`-Präfix → Session-Cookies übernehmen, API-Zugang prüfen.

Erforderliche Cookies für die Vertrags-API (`vue.mlp.de`):
- `VUSESSIONID` – Session-Token (⚠️ kann mehrfach vorkommen - beide kopieren!)
- `BIGipServervue.mlp.de` – Load-Balancer

Optional (für automatische Sitzungserneuerung via Consent-Call):
- `CAS_SESSION` – Auth-Session-Token
- `CAS_DEVICE_SESSION` – Geräte-Token

Beispiel:
```
COOKIE:VUSESSIONID=abc123;VUSESSIONID=def456;BIGipServervue.mlp.de=xyz789
```

### `ListAccounts(knownAccounts)`

Pro Versicherung ein Depot-Konto.  
Felder: `name`, `accountNumber`, `portfolio = true`, `currency`, `type = AccountTypePortfolio`, `bankCode`.

Der Kontoname enthält: `Unternehmen Vertragsnummer (Tarif) | Beitrag bis DD.MM.YYYY`.

### `RefreshAccount(account, since)`

`since` wird ignoriert (Wertpapierdepot ohne Transaktionsliste).

| Feld | Inhalt |
|------|--------|
| `balance` | Aktueller Rückkaufswert |
| `securities` | Eine Position pro Versicherung |

Pro Wertpapier:

| Feld | Wert |
|------|------|
| `name` | Versicherungstyp + Tarif + Todesfallsumme + Erlebensfallsumme + Beitrag |
| `isin` | "" (Lebensversicherungen haben keine ISIN) |
| `securityNumber` | Vertragsnummer |
| `quantity` | 1 (ein "Stück" Versicherung) |
| `price` | Aktueller Rückkaufswert |
| `amount` | Wert der Depotposition |
| `purchasePrice` | Geschätzte Summe aller bisherigen Beiträge |

### Bekannte Einschränkungen

- **Login nur via Cookie-Import:** Direkter Login scheitert an JOSE/JWE-Verschlüsselung.
- **Keine Transaktionen:** Nur aktueller Rückkaufswert/Bestand sichtbar.
- **Session-Management:** Kein expliziter Logout, um Browser-Sitzung nicht zu stören.
- **Datenverarbeitung:** Nutzt native `JSON`-Klasse für maximale Stabilität.

### Tests

```bash
lua tests/test_mlp_kundenportal.lua
```

---

## Entwicklung

Extensions sind unsigniert — in MoneyMoney die Signaturprüfung deaktivieren. Alle Extensions in `extensions/` verwenden `version = 1.00`.

Lokal wie in CI: **Lua 5.4**, **Python 3.11**, **Node 24**.

### Lokale Tests

```bash
# Alle Lua-Unit-Tests
for f in tests/*.lua; do lua "$f"; done

# Cookie-Exporter (scripts/extract-*.py, Tampermonkey .user.js)
python3 tests/test_external_scripts_conformance.py
```

Getrackte Lua-Tests:

| Datei | Extension |
|-------|-----------|
| `tests/test_shareview.lua` | Shareview |
| `tests/test_mlp_kundenportal.lua` | MLP Versicherungen |
| `tests/test_presidential_bank.lua` | Presidential Bank |
| `tests/test_fidelity_cookie_import.lua` | Fidelity |

### CI

Bei Push und Pull Request laufen vier GitHub-Actions-Workflows:

| Workflow | Datei | Prüfungen |
|----------|-------|-----------|
| Extension tests | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) | Lua-Unit-Tests (`tests/*.lua`), Lua-Syntax (`*.lua`), Python-Syntax (`*.py`), JavaScript-Parse-Check (`*.js`) |
| MoneyMoney Script Conformance | [`.github/workflows/moneymoney-script-conformance.yml`](../.github/workflows/moneymoney-script-conformance.yml) | `tests/test_external_scripts_conformance.py` |
| Lua rockspec build | [`.github/workflows/lua-rockspec.yml`](../.github/workflows/lua-rockspec.yml) | `luarocks make moneymoney-dev-1.rockspec` |
| Security | [`.github/workflows/security.yml`](../.github/workflows/security.yml) | gitleaks (Secrets), bandit (Python SAST in `scripts/`, `tests/`) |

Der Security-Workflow läuft zusätzlich wöchentlich per Cron (`0 3 * * 0`).

