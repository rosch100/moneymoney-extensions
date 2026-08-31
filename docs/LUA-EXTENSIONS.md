# Lua-Extensions — MoneyMoney Web Banking API

Engine-Spezifikation: [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/). Installation: [README](../README.md).

## Versionierung

| Version | Bedeutung |
|---------|-----------|
| **0.9 / 0.91** | Beta — Cookie-Import ist der unterstützte Anmeldeweg |
| **1.0** | Direct-Login mit MFA (optional Cookie-Import als Fallback) |

## Engine-Ablauf

1. `SupportsBank`
2. `InitializeSession` / `InitializeSession2`
3. `ListAccounts`
4. `RefreshAccount`
5. optional Kontoauszüge
6. `EndSession`

---

## Bank of America — Beta 0.9

**Datei:** `extensions/Bank of America.lua`

**Erkennung:** `SupportsBank(ProtocolWebBanking, "Bank of America")`.
**Session-API:** `InitializeSession2`.

```lua
WebBanking{
  version     = 0.90,
  url         = "https://secure.bankofamerica.com",
  services    = {"Bank of America"},
  description = "Bank of America — Beta (Cookie-Import)"
}
```

| Feld | Wert |
|------|------|
| Währung | USD |
| Kontotypen | Girokonto oder Kreditkarte |
| Login | `COOKIE:SMSESSION=…;SSOTOKEN=…` |
| Konten-`bankCode` | `BOA` |

**Cookie-Export:** Kontoübersicht im Browser → `python3 scripts/extract-boa-cookies.py login.har`.
Erforderlich sind `SMSESSION`, `SSOTOKEN` und `LSESSIONID`.

**Session:** `LocalStorage.connection` und `LocalStorage.connectionAccountKey`;
`verifyActiveSession` prüft eine persistierte Session vor einem erneuten
Cookie-Import.

### API-Funktionen

- **ListAccounts** — HTML `account-details.go`; Konten aus „Ending in …" oder
  `TL_NPI_AcctName`, einschließlich Giro-/Kreditkarten-Zuordnung
- **RefreshAccount** — Umsätze ab `since` aus Activity-Seiten
- **Kontoauszüge** — PDF via `GetAvailableStatements` / `GetStatement`

Direct-Login blockiert — [ENGINE-API-GAPS.md](ENGINE-API-GAPS.md).

---

## Fidelity Investments — Beta 0.91

**Datei:** `extensions/Fidelity.lua`

**Erkennung:** `SupportsBank(ProtocolWebBanking, "Fidelity")` sowie
`"Fidelity Investments"`. **Session-API:** `InitializeSession`.

```lua
WebBanking{
  version     = 0.91,
  url         = "https://www.fidelity.com",
  services    = {"Fidelity"},
  description = "Fidelity Investments — Beta (Cookie-Import)"
}
```

| Feld | Wert |
|------|------|
| Kontotyp | `AccountTypePortfolio` |
| Login | `COOKIE:_abck=…;bm_sz=…;ATC=…;ET=…;SESSION_SCTX=…;PIT=…;…` |
| Session | `LocalStorage.connection` und `LocalStorage.connectionAccountKey` |

Direct-Login blockiert — [ENGINE-API-GAPS.md](ENGINE-API-GAPS.md).

### API-Funktionen

- **ListAccounts** — REST-POST auf `portfolio/api/GetContext`
- **RefreshAccount** — GraphQL `GetPositions`; falls dort keine
  Asset-Allokation vorliegt, REST-POST auf `performance-api/v1/asset-allocation`
  (`since` wird ignoriert)
- **Umsätze und Kontoauszüge** — nicht implementiert

Für den Holdings-Abruf werden je nach Fidelity-Antwort außerdem CSRF-Cookies
wie `PORTSUM_XSRF-TOKEN` oder `portsum_.csrf` benötigt. Weitere Sessioncookies
wie `FC`, `RC`, `SC`, `MC`, `ATT` und `bm_*` nimmt der Cookie-Export mit.
Für den Export gelten `_abck`, `bm_sz`, `ATC`, `ET`, `SESSION_SCTX` und `PIT`
als kritisch.

---

## MLP Versicherungen — Beta 0.9

**Datei:** `extensions/MLP Versicherungen.lua`

**Erkennung:** `SupportsBank(ProtocolWebBanking, "MLP Versicherungen")`.
**Session-API:** `InitializeSession2`.

```lua
WebBanking{
  version     = 0.90,
  url         = "https://kundenportal.mlp.de",
  services    = {"MLP Versicherungen"},
  description = "MLP Versicherungen — Beta (Cookie-Import)"
}
```

| Feld | Wert |
|------|------|
| Kontotyp | `AccountTypePortfolio` (Versicherungsdepots) |
| Login | `COOKIE:VUSESSIONID=…;BIGipServervue.mlp.de=…` |

Cookies von **`vue.mlp.de`** werden nach dem Öffnen der Vertragsübersicht
benötigt. Der Username-/Passwort-Pfad ist einschließlich JWE-Verschlüsselung
und SecureGo-Plus-MFA implementiert. Er wird nur verwendet, wenn MoneyMoney die
benötigten Zufalls-, Base64url-, RSA- und A256GCM-APIs bereitstellt; andernfalls
fordert die Extension den Cookie-Import an. SecureGo Plus kann als
App-Bestätigung oder als anschließende TAN-Abfrage erscheinen.

**Session:** `LocalStorage.connection`, `LocalStorage.connectionAccountKey` und
`LocalStorage.sessionCookies`.

### API-Funktionen

- **ListAccounts** — ein Depot pro Versicherungsvertrag
- **RefreshAccount** — Rückkaufswert + Position (`since` ignoriert)

---

## Presidential Bank — 1.0

**Datei:** `extensions/Presidential Bank.lua`

**Erkennung:** `SupportsBank(ProtocolWebBanking, "Presidential Bank")`.
**Session-API:** `InitializeSession2`.

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
| `bankCode` des erzeugten Kontos | 255073345 |
| Login | Username + Passwort + MFA; Fallback `COOKIE:SESSION_TOKEN=…;rftoken=…;…` |
| Kontotypen | Giro, Savings, Kreditkarte, Darlehen oder Wertpapierkonto |

`InitializeSession2` bietet SMS, E-Mail, Voice und TOTP an. Für einen
Cookie-Import sind `SESSION_TOKEN` und `rftoken` verpflichtend; `CSRFToken`
kann zusätzlich enthalten sein.
HAR-Export: `python3 scripts/extract-presidential-cookies.py login.har`.

**Session:** `LocalStorage.presidentialSessionCookies`,
`presidentialRftoken`, `presidentialCsrfToken`,
`presidentialDevicePrivate` und `presidentialLoginComplete`. Ein privates Gerät
darf die gespeicherte Session auch dann wiederverwenden, wenn sich der
MoneyMoney-Zugangsschlüssel geändert hat.

Kontoauszüge sind nicht implementiert.

### Endpoints (Auszug)

| Endpoint | Zweck |
|----------|-------|
| `/auth-olb/live/v1/external-login` | Login |
| `/auth-olb/live/v1/mfa/submit` | MFA-Code |
| `/accts-olb/live/v1/history` | Konten + Umsätze |

---

## Shareview — 1.0

**Datei:** `extensions/Shareview.lua`

**Erkennung:** `SupportsBank(ProtocolWebBanking, "Shareview")`.
**Session-API:** `InitializeSession2`.

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
| Währung | GBP |
| Kontotyp | `AccountTypePortfolio` |
| Login | Username + Passwort + Geburtsdatum + sechsstelliger numerischer MFA-Code |
| Session | `LocalStorage.connection` und `LocalStorage.connectionAccountKey` |

Benutzername mit Pipe-Suffix für Background-Sync:
`name|TT.MM.JJJJ`, `name|TT/MM/JJJJ` oder `name|TT-MM-JJJJ`.
Fallback: `COOKIE:FedAuth=…`. Shareview ist nicht in MoneyMoney Helper
konfiguriert; das FedAuth-Cookie muss deshalb manuell importiert werden.
HAR-Export: `python3 scripts/extract-shareview-cookies.py login.har`.

### API-Funktionen

- **ListAccounts** — ein konsolidiertes Portfolio mit der internen Kontonummer
  `shareview-portfolio`
- **RefreshAccount** — Holdings aus `holdingssummary.aspx` (keine Transaktionen)
- **Kontoauszüge** — nicht implementiert
