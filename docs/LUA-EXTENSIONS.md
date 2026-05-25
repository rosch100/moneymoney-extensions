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
  description = "Equiniti Shareview Portfolio - Direct Login (Username|DOB + Password + MFA) und Cookie Import"
}
```

| Feld | Wert |
|------|------|
| Auswahl | Service **Shareview** |
| Währung | GBP (GBX/Pence wird automatisch in GBP umgerechnet) |
| Kontotyp | Wertpapierdepot (`AccountTypePortfolio`, `portfolio = true`) |

### `SupportsBank(protocol, bankCode)`

- `true` für `ProtocolWebBanking` und `bankCode` **Shareview** oder **Equiniti Shareview**

### `InitializeSession2(protocol, bankCode, step, credentials, interactive)`

Direct-Login mit Zwei-Faktor-Authentifizierung gemäß [API](https://moneymoney.app/api/webbanking/#anmeldung-mit-zwei-faktor-authentifizierung).

| Schritt | Inhalt |
|---------|--------|
| 1 | Username + Geburtsdatum + Passwort **oder** `COOKIE:`-Import |
| 2 | 6-stelliger Authentication Code aus Shareview-App / E-Mail |

**Username-Format mit Geburtsdatum:** `username|TT.MM.JJJJ`

| Feld | Beispiel |
|------|----------|
| `username` | `max.mustermann\|01.01.1970` |
| `password` | Shareview-Passwort **oder** `COOKIE:FedAuth=…;ASP.NET_SessionId=…` |

Hintergrund: Shareview verlangt Username, Passwort und Geburtsdatum (Tag, Monat, Jahr) auf der Login-Seite. Da MoneyMoney standardmäßig nur ein Username-Feld zeigt, wird das Geburtsdatum mit `|` an den Username angehängt und intern in die drei Dropdown-Felder (`drpDay`, `drpMonth`, `drpYear`) aufgeteilt.

#### Federation-Flow (Step 2 → Holdings)

Nach erfolgreicher OTP-Validierung antwortet Shareview mit einer ASP.NET-`<form name="hiddenform">`-Auto-Post-Page, die im Browser per JavaScript an die ADFS-Endpoints weitergeleitet wird (WS-Federation/SAML 1.1):

1. `POST https://www.equiniti.com/adfs/ls/` mit `wa`, `wresult` (SAML-Token), `wctx`
2. ADFS antwortet mit weiterer Federation-Form an `https://portfolio.shareview.co.uk/_trust/`
3. Erst danach ist der `FedAuth`-Cookie gesetzt und `holdingssummary.aspx` zugänglich.

Da die Lua-`Connection` keine HTML-Form-Auto-Submits ausführt, fährt `Shareview.lua` diese Hops in `followAutoPostForms()` manuell nach (mit Heuristik auf `<title>Working...</title>` bzw. `name="hiddenform"`). Das `wresult`-XML enthält literale `>` und `/>` (HTML5-konformes Attribut), daher werden Form-Felder nicht über `<input ... />`-Tag-Boundaries, sondern direkt per `name="X" value="..." />`-Pattern extrahiert.

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

## Equiniti Shareview Portfolio (XPath-Variante, experimentell)

**Datei:** `extensions/Shareview-XPath.lua`
**Service:** `Shareview-XPath` (parallel zu `Shareview` installierbar)

Funktionsidentische Variante zu `Shareview.lua`, nutzt aber MoneyMoneys integrierte HTML/XPath-API (`HTML(content)`, `:xpath(...)`, `:submit()`) anstelle von manuellem Lua-Pattern-Parsing für Form-Handling. Inspiriert vom EquatePlus-Plugin ([neatc0der/equateplus-moneymoney](https://github.com/neatc0der/equateplus-moneymoney)), das das gleiche Equiniti-Backbone, aber unterschiedliche Endpunkte nutzt.

### Vorteile gegenüber `Shareview.lua`

| Bereich | Pattern-Variante (`Shareview.lua`) | XPath-Variante (`Shareview-XPath.lua`) |
|---|---|---|
| ASP.NET-Hidden-Inputs | manuell via `<input[^>]+>`-Pattern eingesammelt | automatisch durch `:submit()` |
| SAML-`wresult`-Wert (mit literalen `>`/`/>`) | spezialisiertes `name="X" value="(.-)" />`-Pattern | echter HTML-Parser, problemlos |
| MFA-Feld-Locator | Heuristik (`btnSubmitOtp`/`txtVerificationCode`) | XPath `contains(@id, "txtVerificationCode")` |
| Federation-Auto-Post | manuelle `followAutoPostForms()`-Schleife | `:submit()` der `<form name="hiddenform">` |
| Code-Umfang | ~640 Zeilen | ~550 Zeilen |

### Locator-Strategie

ASP.NET vergibt dynamische Control-IDs mit GUIDs (`ctl00$SPWebPartManager1$g_82244877_…$UserLocate2UC1$rpt$ctl00$txtInput`). Statt diese hart zu codieren, arbeitet `Shareview-XPath.lua` mit `contains(@id, "...")`-Substring-Matches:

| Feld | XPath |
|---|---|
| Username | `//input[contains(@id, "UserLocate2UC1_rpt_ctl00_txtInput")]` |
| Passwort | `//input[contains(@id, "UserLocate2UC1_rpt_ctl02_txtInput")]` |
| DOB Tag/Monat/Jahr | `//select[contains(@id, "drpDay")]/option[@value="…"]` etc. |
| Locate-Button (`__EVENTTARGET`) | `//input[contains(@id, "btnLocate")]` → `:attr("name")` |
| OTP-Eingabe | `//input[contains(@id, "txtVerificationCode")]` |
| OTP-Submit | `//input[contains(@id, "btnSubmitOtp")]` → `:attr("name")` |
| Federation-Form | `//form[@name="hiddenform"]` |

### Verifikation

**Wichtig:** Diese Variante ist nur in der MoneyMoney-Runtime verifizierbar. Der lokale Test-Harness (`test_shareview_live.lua`) basiert auf `curl` und kann die `HTML()`/`xpath()`/`:submit()`-API nicht stubben. Daher:

1. `Shareview-XPath.lua` ins MoneyMoney-Extensions-Verzeichnis kopieren.
2. In MoneyMoney *Konto hinzufügen → Wertpapierdepot → Service "Shareview-XPath"*.
3. Username `username|TT.MM.JJJJ`, Passwort wie gewohnt.
4. Bei Fehlern: Console-Log in MoneyMoney prüfen, ggf. `XPath`-Locator anpassen (ASP.NET-Control-IDs können sich ändern).

Die robuste Pattern-Variante (`Shareview.lua`) bleibt als Fallback unverändert verfügbar und ist live nachweislich funktionsfähig.

### Holdings-Parsing

Das Parsen der `holdingssummary.aspx`-Tabelle (HTML-Patterns) ist **identisch** zur Pattern-Variante — die Holdings-Page ist stabil und live verifiziert; ein zusätzlicher XPath-Refactor brächte hier keinen Mehrwert.

---

## Entwicklung

Lokaler Test BoA:

```bash
lua test_boa.lua
```

Signatur: BoA-Extension ist signiert (`SIGNATURE:` am Dateiende). Für eigene Builds Signaturprüfung in MoneyMoney deaktivieren oder neu signieren lassen.

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
