# MoneyMoney Extensions

Web-Banking-Extensions für [MoneyMoney](https://moneymoney.app).

## Übersicht

| Extension | Version | Login | Status |
|-----------|---------|-------|--------|
| [Bank of America](extensions/Bank%20of%20America.lua) | **0.9 Beta** | Cookie-Import | Username/Passwort blockiert (Browser-Fingerprint) |
| [Fidelity](extensions/Fidelity.lua) | **0.9 Beta** | Cookie-Import | Username/Passwort blockiert (Akamai + MFA) |
| [MLP Versicherungen](extensions/MLP%20Versicherungen.lua) | **0.9 Beta** | Cookie-Import | JWE-Login blockiert (`MM.aes256gcm` fehlt) |
| [Presidential Bank](extensions/Presidential%20Bank.lua) | 1.0 | Username/Passwort + MFA | Cookie-Import optional |
| [Shareview](extensions/Shareview.lua) | 1.0 | Username/Passwort + MFA | Cookie-Import optional |

**Beta (0.9):** Nur Cookie-Import aus einer Browser-Session. Kein Direct-Login mit Benutzername/Passwort.

**MLP Bank vs. MLP Versicherungen:** FinTS-Giro (MLP Bank) ist ein separates MoneyMoney-Produkt. Diese Extension deckt nur Versicherungsverträge über `vue.mlp.de` ab.

Details pro Extension: [docs/LUA-EXTENSIONS.md](docs/LUA-EXTENSIONS.md).

## Installation

1. `.lua` nach `~/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/` kopieren
2. Signaturprüfung in MoneyMoney deaktivieren, App neu starten

## Cookie-Import (Beta-Extensions)

Passwortfeld in MoneyMoney:

```
COOKIE:name=value;name2=value2
```

Benutzername ist bei Beta-Extensions irrelevant.

### Ablauf

1. Im Browser vollständig einloggen (inkl. MFA)
2. Kontoseite / Vertragsübersicht öffnen
3. Cookies exportieren (HAR oder Tampermonkey)
4. `COOKIE:…`-String als Passwort einfügen

Session wird in `LocalStorage` persistiert; Folge-Syncs nutzen gespeicherte Cookies, solange die Session gültig ist.

### Export per HAR

DevTools → Network → **Save all as HAR**, dann:

| Bank | Befehl | Wichtige Cookies |
|------|--------|------------------|
| Bank of America | `python3 scripts/extract-boa-cookies.py export.har` | `SMSESSION`, `SSOTOKEN` |
| Fidelity | `python3 scripts/extract-fidelity-cookies.py export.har` | `ATC`, `FC`, `RC`, `SC`, `MC`, `_abck`, `bm_*` |
| MLP Versicherungen | `python3 scripts/extract-mlp-cookies.py export.har` | `VUSESSIONID` von `vue.mlp.de` |

### Fidelity: dauerhafte Session

Nach SMS-MFA **„Don't ask me again on this device“** aktivieren, erst nach **Portfolio Summary** exportieren.

### MLP: Vue-Session

Vertragsübersicht auf `vue.mlp.de` öffnen, bevor exportiert wird. Beim ersten Zugriff SSL-Zertifikat für `vue.mlp.de` in MoneyMoney bestätigen.

### Tampermonkey (optional)

`scripts/moneymoney-cookie-exporter.user.js` — **Alt+C** auf der Kontoseite. In Safari keine HttpOnly-Cookies; dann HAR verwenden.

## Direct-Login (Presidential Bank, Shareview)

### Presidential Bank

Username + Passwort → MFA (SMS, E-Mail, Voice oder TOTP). Session in `LocalStorage`; privates Gerät (`MAF_IB_*`) verlängert die Laufzeit.

### Shareview

Username + Passwort + Geburtsdatum + MFA. Für Background-Sync: `username|TT.MM.JJJJ` als Benutzername (Geburtsdatum im Keychain).

## Dokumentation

| Dokument | Inhalt |
|----------|--------|
| [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/) | Offizielle Extension-API |
| [docs/LUA-EXTENSIONS.md](docs/LUA-EXTENSIONS.md) | Extensions (Login, Cookie-Import, Abruf) |
| [docs/ENGINE-API-GAPS.md](docs/ENGINE-API-GAPS.md) | Fehlende Engine-APIs für Direct-Login |

## Entwicklung

Lokal: Lua 5.4, Python 3.11.

```bash
for f in tests/*.lua; do lua "$f"; done
python3 tests/test_external_scripts_conformance.py
```

CI: [`.github/workflows/ci.yml`](.github/workflows/ci.yml)

## Lizenz

MIT
