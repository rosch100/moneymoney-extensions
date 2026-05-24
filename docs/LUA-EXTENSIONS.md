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
