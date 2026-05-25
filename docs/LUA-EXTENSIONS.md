# Lua-Extensions — MoneyMoney Web Banking API

Referenz für die implementierten Einsprungspunkte. Spezifikation der Engine: [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/).

Installation: `.lua`-Dateien aus `extensions/` in das MoneyMoney-Extensions-Verzeichnis (siehe [README](../README.md)).

---

## Ablauf (Engine)

MoneyMoney ruft pro Lauf typischerweise auf:

1. `SupportsBank`
2. `InitializeSession` bzw. `InitializeSession2`
3. `ListAccounts`
4. pro Konto: `RefreshAccount`
5. optional: Kontoauszüge (`GetAvailableStatements`, `GetStatement`, …)
6. `EndSession`

Fehler erscheinen im Protokollfenster (**Fenster → Protokollfenster**).

---

## Cookie-Import (alle drei Banken)

Passwortfeld in MoneyMoney:

```
COOKIE:name=value;name2=value2
```

Cookies aus Browser exportieren: [README](../README.md) (Userscript, HAR, Extension).

---

## Bank of America

**Datei:** `extensions/Bank of America.lua`

### Registrierung

```lua
WebBanking {
  version = "1.0.0",
  url = "https://secure.bankofamerica.com",
  services = {"Bank of America"},
  description = "Bank of America - Cookie Import"
}
```

| Feld | Wert |
|------|------|
| `protocol` / Auswahl | `ProtocolWebBanking`, Service **Bank of America** |
| Währung | USD |
| Login | nur Cookie-Import (RSA-Login in Lua nicht möglich) |

### `SupportsBank(protocol, bankCode)`

- `true` wenn `protocol == ProtocolWebBanking` und `bankCode == "Bank of America"`

### `InitializeSession(protocol, bankCode, username, username2, password, username3)`

| Passwort | Verhalten |
|----------|-----------|
| beginnt mit `COOKIE:` | Session-Cookies setzen, Zugang zu `secure.bankofamerica.com` prüfen |
| sonst | Fehlertext (RSA-Login nicht unterstützt) |

Rückgabe: `nil` bei Erfolg, sonst Fehlerstring oder `LoginFailed`.

### `ListAccounts(knownAccounts)`

- HTML von `account-details.go`, Konten aus `TL_NPI_AcctName` / „Ending in“
- Felder: `name`, `accountNumber` (letzte 4 Ziffern), `bankCode`, `currency`, `type`, `attributes = {"statements"}`
- Typen: `AccountTypeCreditCard` oder `AccountTypeGiro`

Rückgabe: Konten-Array oder Fehlerstring.

### `RefreshAccount(account, since)`

| Parameter | Bedeutung |
|-----------|-----------|
| `account` | Konto aus `ListAccounts` |
| `since` | POSIX-Zeitstempel; Umsätze ab diesem Tag |

Rückgabe (Tabelle):

| Feld | Inhalt |
|------|--------|
| `balance` | Kontostand (Kreditkarte: Statement Balance negativ) |
| `transactions` | Array, neueste zuerst |

Umsatzfelder u. a.: `bookingDate`, `valutaDate`, `amount`, `purpose`, `name`, `bookingText`, `endToEndReference` (nach Detail-POST).

Datenquelle: HTML Activity-Seiten (`stmtFromDateList`), kein JSON-API.

### `EndSession()`

Kein Server-Logout (Session für Kontoauszüge erhalten).

### Kontoauszüge (Erweiterung)

| Funktion | Zweck |
|----------|--------|
| `GetAvailableStatements(account, since)` | Metadaten verfügbarer PDF-Auszüge |
| `GetStatement(account, statementId)` | PDF-Binary |
| `FetchStatements(accounts, knownIdentifiers)` | Batch-Download neuer Auszüge |
| `DownloadStatement(account, statement)` | Alias zu `GetStatement` |

`statementId`: `docId|adxToken`.

---

## Fidelity Investments

**Datei:** `extensions/Fidelity.lua`

### Registrierung

```lua
WebBanking {
  version = "1.0.0",
  url = "https://www.fidelity.com",
  services = {"Fidelity"},
  description = "Fidelity Investments - GraphQL, Cookie Import"
}
```

| Feld | Wert |
|------|------|
| Auswahl | Service **Fidelity** |
| Währung | USD |
| Kontotyp | Wertpapierdepot (`AccountTypePortfolio`, `portfolio = true`) |

### `SupportsBank(protocol, bankCode)`

- `true` für `ProtocolWebBanking` und `bankCode` **Fidelity** oder **Fidelity Investments**

### `InitializeSession(protocol, bankCode, username, username2, password, username3)`

| Passwort | Verhalten |
|----------|-----------|
| `COOKIE:…` | Cookies übernehmen, Portfolio-Seite testen |
| Klartext | Login-API (oft durch Bot-Schutz blockiert) |

Rückgabe: `nil` bei Erfolg, sonst Fehlerstring / `LoginFailed`.

### `ListAccounts(knownAccounts)`

- GraphQL `GetContext` → `person.assets`
- Felder: `name`, `accountNumber`, `portfolio`, `currency`, `type`, `bankCode`

### `RefreshAccount(account, since)`

Depot: `since` wird ignoriert (`nil` laut API üblich).

Rückgabe:

| Feld | Inhalt |
|------|--------|
| `balance` | Summe Marktwerte |
| `securities` | Positionen (`name`, `isin`, `quantity`, `amount`, …) |

GraphQL: `GetPositions`.

### `EndSession()`

Optional GET Logout-URL; Cookies bleiben für spätere Aufrufe erhalten.

---

## Presidential Bank

**Datei:** `extensions/Presidential Bank.lua`

### Registrierung

```lua
WebBanking {
  version = "1.0.0",
  url = "https://www.presidentialpcbanking.com",
  services = {"Presidential Bank"},
  description = "Presidential Bank - MFA and Cookie Import"
}
```

| Feld | Wert |
|------|------|
| Auswahl | Service **Presidential Bank** |
| `bankCode` | 255073345 (ABA) |
| Währung | USD |

### `SupportsBank(protocol, bankCode)`

- `true` für `ProtocolWebBanking` und `bankCode == "Presidential Bank"`

### `InitializeSession2(protocol, bankCode, step, credentials, interactive)`

Zwei-Faktor-Login laut [API](https://moneymoney.app/api/webbanking/#anmeldung-mit-zwei-faktor-authentifizierung).

| Schritt | Inhalt |
|---------|--------|
| 1 | Login oder `COOKIE:`; bei MFA Challenge-Objekt (`title`, `challenge`, `label`) |
| 2 | MFA-Code bzw. Methodenwahl |
| 3 | Cookie-Import falls `rftoken` nach MFA fehlt |

Cookie-Import (empfohlen): Passwort `COOKIE:…` in Schritt 1 — benötigt u. a. `SESSION_TOKEN`, `rftoken` (HttpOnly, aus Browser/HAR).

MFA-Login in MoneyMoney scheitert oft, weil HttpOnly-`rftoken` nach MFA nicht in der Engine ankommt.

### `ListAccounts(knownAccounts)`

- REST `accts-olb/live/v1/history`
- Felder: `name`, `accountNumber` (interne ID), `bankCode`, `currency`, `type`

### `RefreshAccount(account, since)`

Rückgabe:

| Feld | Inhalt |
|------|--------|
| `balance` | Kontostand |
| `transactions` | Umsätze ab `since` |

REST Transaktions-Endpoint; Beträge und Datum aus Bank-JSON.

### `EndSession()`

Session-Cookies löschen.

---

## Equiniti Shareview Portfolio

**Datei:** `extensions/Shareview.lua`

### Registrierung

```lua
WebBanking {
  version = "1.0.0",
  url = "https://portfolio.shareview.co.uk",
  services = {"Shareview"},
  description = "Equiniti Shareview Portfolio - Direct Login (Username + Password + DOB + MFA) oder Cookie Import"
}
```

| Feld | Wert |
|------|------|
| Auswahl | Service **Shareview** |
| Währung | GBP (GBX/Pence wird automatisch in GBP umgerechnet) |
| Kontotyp | Wertpapierdepot (`AccountTypePortfolio`, `portfolio = true`) |

### `SupportsBank(protocol, bankCode)`

- `true` für `ProtocolWebBanking` und `bankCode == "Shareview"`

### `InitializeSession2(protocol, bankCode, step, credentials, interactive)`

Direct-Login mit Zwei-Faktor-Authentifizierung gemäß [API](https://moneymoney.app/api/webbanking/#anmeldung-mit-zwei-faktor-authentifizierung). Das Geburtsdatum wird entweder schon im Benutzernamen mitgegeben (Komfort-Pfad, einmalig im Keychain gespeichert) oder als eigener Multi-Step nachgefragt.

| Schritt | Inhalt | Bedingung |
|---------|--------|-----------|
| 1 | Username + Passwort (Standard-Dialog) **oder** `COOKIE:`-Import | immer |
| 1a | Geburtsdatum (`TT.MM.JJJJ`) | nur wenn der Username **keinen** Pipe-Suffix enthält |
| 2 | 6-stelliger Authentication Code aus Shareview-App / E-Mail | bei Direct-Login |

**Username-Eingabe — zwei Varianten:**

| Variante | Username-Wert | Verhalten |
|----------|---------------|-----------|
| **Komfort (empfohlen)** | `max.mustermann\|01.01.1970` | Geburtsdatum wird aus dem Pipe-Suffix gelesen — kein extra Step. Geburtsdatum bleibt verschlüsselt im Keychain. |
| **Multi-Step** | `max.mustermann` | MoneyMoney fragt das Geburtsdatum als separaten Schritt nach (Tipp im Challenge-Text: Pipe-Format dauerhaft speichern). Funktioniert **nur interaktiv**, nicht für automatische Background-Syncs. |

| Feld | Beispiel |
|------|----------|
| `username` | `max.mustermann\|01.01.1970` (Komfort) oder `max.mustermann` (Multi-Step) |
| `password` | Shareview-Passwort **oder** `COOKIE:FedAuth=…;ASP.NET_SessionId=…` |

Hintergrund: Shareview verlangt Username, Passwort und Geburtsdatum (Tag, Monat, Jahr) auf der Login-Seite. Da MoneyMoney im Standard-Dialog nur Username und Passwort zeigt, wird das Geburtsdatum entweder via Pipe-Suffix im Username transportiert (statisches Datum → im Keychain speicherbar) oder als zusätzlicher interaktiver Step abgefragt. Intern wird es in die drei Dropdown-Felder (`drpDay`, `drpMonth`, `drpYear`) aufgeteilt.

Der State zwischen den Steps wird im Modul-`session` gehalten (`awaitingDob`, `awaitingMfa`, `pendingUsername`, `pendingPassword`) und in `EndSession` immer komplett verworfen.

#### Form-Handling (HTML/XPath-API)

`Shareview.lua` nutzt MoneyMoneys integrierte HTML/XPath-API (`HTML(content)`, `:xpath(...)`, `:submit()`) und überlässt dem Parser das Einsammeln aller hidden Inputs (insb. `__VIEWSTATE`, `__EVENTVALIDATION`, `wresult`-SAML-Token). ASP.NET vergibt dynamische Control-IDs mit GUIDs, daher arbeiten alle Locator mit `contains(@id, "...")`-Substring-Matches auf den stabilen Suffixen:

| Feld | XPath |
|---|---|
| Username | `//input[contains(@id, "UserLocate2UC1_rpt_ctl00_txtInput")]` |
| Passwort | `//input[contains(@id, "UserLocate2UC1_rpt_ctl02_txtInput")]` |
| DOB Tag/Monat/Jahr | `//select[contains(@id, "drpDay\|drpMonth\|drpYear")]/option[@value="…"]` |
| Locate-Button (`__EVENTTARGET`) | `//input[contains(@id, "btnLocate")]` → `:attr("name")` |
| OTP-Eingabe | `//input[contains(@id, "txtVerificationCode")]` |
| OTP-Submit | `//input[contains(@id, "btnSubmitOtp")]` → `:attr("name")` |
| ASP.NET-Form | `//form[@name="aspnetForm"]` (id ist dynamisch, z. B. `ctl31`) |
| Federation-Form | `//form[@name="hiddenform"]` |

#### Federation-Flow (Step 2 → Holdings)

Nach erfolgreicher OTP-Validierung antwortet Shareview mit einer `<form name="hiddenform">`-Auto-Post-Page, die im Browser per JavaScript an die ADFS-Endpoints weitergeleitet wird (WS-Federation/SAML 1.1):

1. `POST https://www.equiniti.com/adfs/ls/` mit `wa`, `wresult` (SAML-Token), `wctx`
2. ADFS antwortet mit weiterer Federation-Form an `https://portfolio.shareview.co.uk/_trust/`
3. Erst danach ist der `FedAuth`-Cookie gesetzt und `holdingssummary.aspx` zugänglich.

Da die Lua-`Connection` keine HTML-Form-Auto-Submits ausführt, fährt `followFederationHops()` diese Hops manuell nach (Heuristik auf `<title>Working...</title>` bzw. `name="hiddenform"`, max. 5 Hops). Das `:submit()` der HTML/XPath-API kümmert sich um literale `>`/`/>`-Zeichen im SAML-`wresult` zuverlässig.

#### Cookie-Import (empfohlen bei wiederholten MFA-Problemen)

Passwortfeld in MoneyMoney: `COOKIE:name=value;name2=value2`

**Pflicht-Cookies:** `FedAuth`, `ASP.NET_SessionId`, `SPStsAuthContext_7PortfolioDefault`

**Hinweis:** `FedAuth` ist HttpOnly — Export nur per Tampermonkey (`GM.cookie`), HAR-Export oder DevTools möglich. Siehe [README — Cookie-Import](../README.md#cookie-import).

Rückgabe: `nil` bei Erfolg, sonst Fehlerstring oder `LoginFailed`.

### `ListAccounts(knownAccounts)`

- Eine konsolidierte Position **„Shareview Portfolio"** mit allen Holdings als Wertpapiere
- Felder: `name`, `accountNumber` (`shareview-portfolio`), `portfolio = true`, `currency = "GBP"`, `type = AccountTypePortfolio`, `bankCode = "Shareview"`

### `RefreshAccount(account, since)`

Depot: `since` wird ignoriert (Wertpapierdepot ohne Transaktionsliste).

Rückgabe:

| Feld | Inhalt |
|------|--------|
| `balance` | Total Indicative Value aus `holdingssummary.aspx` (in GBP) |
| `securities` | Positionen aus allen drei Web-Parts (Equiniti-administriert, Self-maintained Funds, Self-maintained Holdings) |

**Pro Wertpapier:**

| Feld | Quelle |
|------|--------|
| `name` | `<strong>Companyname</strong>` + Sub-Account |
| `isin` | aus Morningstar-Link `externalid=<ISIN>` |
| `securityNumber` | Shareholder Reference Number |
| `quantity` | Spalte „Quantity" |
| `price` | Spalte „Price" (GBX → GBP, geteilt durch 100) |
| `amount` | Spalte „Value" (GBX → GBP) |
| `currencyOfPrice` / `currencyOfOriginalAmount` | Native Währung, GBX wird zu GBP normalisiert |

Datenquelle: HTML der `holdingssummary.aspx`-Seite (ASP.NET WebForms / SharePoint), kein JSON-API.

### `EndSession()`

Optionaler GET auf `Logoff.aspx`; lokale Session-Cookies werden zurückgesetzt.

### Bekannte Einschränkungen

- **Keine Transaktionen / Dividenden** in v1 — nur aktuelles Portfolio. Statements liegen unter `statement.aspx?sid=<refNo>` (HTML-Tabelle, künftige Erweiterung).
- **Sperre nach MFA-Fehlversuchen:** Drei aufeinanderfolgende falsche OTPs sperren das Konto temporär. Im Zweifel Cookie-Import nutzen.
- **Nur GBP-Anzeige getestet:** Andere Display-Währungen (USD, EUR) werden vom Format-Parser unterstützt, aber nicht mit Realdaten verifiziert.

---

## Entwicklung

Lokale Helper-Tests (Shareview):

```bash
lua tests/test_shareview.lua
```

Signatur: Die Extensions hier sind unsigniert (`-- SIGNATURE: <unsigned>` am Dateiende). In MoneyMoney die Signaturprüfung für Extensions deaktivieren oder die Datei selbst signieren lassen.

API-Vorlage (minimal):

```lua
WebBanking { version = 1.0, url = "…", services = {"…"}, description = "…" }

function SupportsBank(protocol, bankCode) … end
function InitializeSession(…) … end
function ListAccounts(knownAccounts) … end
function RefreshAccount(account, since) … end
function EndSession() … end
```

Siehe [Vorlage in der offiziellen Doku](https://moneymoney.app/api/webbanking/#vorlage).
