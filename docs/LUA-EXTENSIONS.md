# Lua-Extensions — MoneyMoney Web Banking API

Engine-Spezifikation: [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/). Installation: [README](../README.md).

## Versionierung

| Version | Bedeutung |
|---------|-----------|
| **0.9** | Beta — nur Cookie-Import, kein Username/Passwort-Login |
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
| Login | `COOKIE:SMSESSION=…;SSOTOKEN=…` |

**Cookie-Export:** Kontoübersicht im Browser → `python3 scripts/extract-boa-cookies.py login.har`

**Session:** `LocalStorage.connection`; gültige Session wird vor erneutem Import geprüft.

### API-Funktionen

- **ListAccounts** — HTML `account-details.go`, Konten „Ending in …"
- **RefreshAccount** — Umsätze ab `since` aus Activity-Seiten
- **Kontoauszüge** — PDF via `GetAvailableStatements` / `GetStatement`

Direct-Login blockiert (Browser-Fingerprint). Details: [ENGINE-API-GAPS.md](ENGINE-API-GAPS.md#bank-of-america).

---

## Fidelity Investments — Beta 0.9

**Datei:** `extensions/Fidelity.lua`

```lua
WebBanking{
  version     = 0.90,
  url         = "https://www.fidelity.com",
  services    = {"Fidelity"},
  description = "Fidelity Investments — Beta (Cookie-Import)"
}
```

| Feld | Wert |
|------|------|
| Kontotyp | `AccountTypePortfolio` |
| Login | `COOKIE:ATC=…;FC=…;RC=…;SC=…;MC=…` (+ Akamai `_abck`, `bm_*`) |

Direct-Login blockiert (Akamai + MFA). Details: [ENGINE-API-GAPS.md](ENGINE-API-GAPS.md#fidelity).

### API-Funktionen

- **ListAccounts** — GraphQL `GetContext`
- **RefreshAccount** — GraphQL `GetPositions` (`since` ignoriert)

---

## MLP Versicherungen — Beta 0.9

**Datei:** `extensions/MLP Versicherungen.lua`

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

Cookies von **`vue.mlp.de`** nach Öffnen der Vertragsübersicht. JWE-Login blockiert ohne `MM.aes256gcm`. Details: [ENGINE-API-GAPS.md](ENGINE-API-GAPS.md#mlp-versicherungen).

### API-Funktionen

- **ListAccounts** — ein Depot pro Versicherungsvertrag
- **RefreshAccount** — Rückkaufswert + Position (`since` ignoriert)

---

## Presidential Bank — 1.0

**Datei:** `extensions/Presidential Bank.lua`

```lua
WebBanking{
  version     = 1.00,
  url         = "https://www.presidentialpcbanking.com",
  services    = {"Presidential Bank"},
  description = "Presidential Bank — MFA Login"
}
```

| Feld | Wert |
|------|------|
| `bankCode` | 255073345 |
| Login | Username + Passwort + MFA; Fallback `COOKIE:…` |

`InitializeSession2` — MFA-Flow (SMS, E-Mail, Voice, TOTP). Session + privates Gerät in `LocalStorage`.

### Endpoints (Auszug)

| Endpoint | Zweck |
|----------|-------|
| `/auth-olb/live/v1/external-login` | Login |
| `/auth-olb/live/v1/mfa/submit` | MFA-Code |
| `/accts-olb/live/v1/history` | Konten + Umsätze |

---

## Shareview — 1.0

**Datei:** `extensions/Shareview.lua`

```lua
WebBanking{
  version     = 1.00,
  url         = "https://portfolio.shareview.co.uk",
  services    = {"Shareview"},
  description = "Shareview — Direct Login (MFA)"
}
```

| Feld | Wert |
|------|------|
| Währung | GBP |
| Login | Username + Passwort + Geburtsdatum + MFA |

Benutzername mit Pipe-Suffix für Background-Sync: `name|TT.MM.JJJJ`. Fallback `COOKIE:FedAuth=…`.

### API-Funktionen

- **ListAccounts** — konsolidiertes Portfolio
- **RefreshAccount** — Holdings aus `holdingssummary.aspx` (keine Transaktionen)
