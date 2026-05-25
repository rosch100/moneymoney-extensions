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

## Cookie-Import (BoA, Fidelity, Presidential)

Passwortfeld in MoneyMoney:

```
COOKIE:name=value;name2=value2
```

Export-Wege: siehe [README](../README.md#cookie-import-boa-fidelity-presidential).

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
| `bankCode` | 255073345 (ABA) |
| Währung | USD |

### `InitializeSession2(protocol, bankCode, step, credentials, interactive)`

Zwei-Faktor-Flow gemäß [Anmeldung mit Zwei-Faktor-Authentifizierung](https://moneymoney.app/api/webbanking/#anmeldung-mit-zwei-faktor-authentifizierung).

| Schritt | Inhalt |
|---------|--------|
| 1 | Login oder `COOKIE:`; bei MFA Challenge-Objekt (`title`, `challenge`, `label`) |
| 2 | MFA-Code bzw. Methodenwahl |
| 3 | Cookie-Import-Fallback, falls `rftoken` nach MFA fehlt |

MFA-Login scheitert in MoneyMoney häufig, weil der HttpOnly-`rftoken` nicht in die Engine übernommen wird. Cookie-Import (Passwort `COOKIE:…`) ist der empfohlene Weg und benötigt u. a. `SESSION_TOKEN` und `rftoken`.

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

Zwei-Faktor-Flow mit zusätzlichem Geburtsdatum-Step, falls dieses nicht im Benutzernamen mitgegeben wurde.

| Schritt | Inhalt | Bedingung |
|---------|--------|-----------|
| 1  | Username + Passwort | immer |
| 1a | Geburtsdatum (`TT.MM.JJJJ`) | nur wenn der Username keinen `\|TT.MM.JJJJ`-Suffix enthält |
| 2  | 6-stelliger MFA-Code | immer |

#### Username-Eingabe

| Variante | Wert | Verhalten |
|----------|------|-----------|
| Komfort | `max.mustermann\|01.01.1970` | Geburtsdatum wird aus dem Pipe-Suffix gelesen, im macOS-Keychain verschlüsselt abgelegt. Funktioniert für Background-Syncs. |
| Multi-Step | `max.mustermann` | MoneyMoney fragt das Geburtsdatum interaktiv nach. Funktioniert **nicht** für nicht-interaktive Background-Syncs. |

Shareview erwartet Username, Passwort und Geburtsdatum (Tag, Monat, Jahr) auf der Login-Seite. Da MoneyMoneys Standard-Dialog nur Username und Passwort kennt, wird das Geburtsdatum entweder als Pipe-Suffix im Username oder als zusätzlicher interaktiver Step übermittelt.

State zwischen den Steps wird im Modul-`session` gehalten (`awaitingDob`, `awaitingMfa`, `pendingUsername`, `pendingPassword`) und in `EndSession` zurückgesetzt.

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
| `currencyOfPrice` / `currencyOfOriginalAmount` | Native Währung, GBX wird zu GBP normalisiert |

Datenquelle: HTML der `holdingssummary.aspx`-Seite (ASP.NET WebForms / SharePoint), kein JSON-API.

### `EndSession()`

Optionaler GET auf `Logoff.aspx`; lokale Session-Cookies werden zurückgesetzt.

### Bekannte Einschränkungen

- Keine Transaktionen / Dividenden — nur aktuelles Portfolio.
- Drei aufeinanderfolgende falsche MFA-Codes sperren das Konto temporär.
- Nur GBP-Anzeige live verifiziert.

---

## Entwicklung

Lokale Helper-Tests (Shareview):

```bash
lua tests/test_shareview.lua
```

Signatur: Die Extensions hier sind unsigniert (`-- SIGNATURE: <unsigned>` am Dateiende). In MoneyMoney die Signaturprüfung für Extensions deaktivieren.

Minimal-Vorlage für neue Extensions:

```lua
WebBanking{ version = 1.0, url = "…", services = {"…"}, description = "…" }

function SupportsBank(protocol, bankCode) … end
function InitializeSession(…) … end
function ListAccounts(knownAccounts) … end
function RefreshAccount(account, since) … end
function EndSession() … end
```

Siehe [Vorlage in der offiziellen Doku](https://moneymoney.app/api/webbanking/#vorlage).
