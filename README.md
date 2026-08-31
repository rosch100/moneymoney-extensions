# MoneyMoney Extensions

Web-Banking-Extensions für [MoneyMoney](https://moneymoney.app).

## Übersicht

| Extension | Version | Login | Status |
|-----------|---------|-------|--------|
| [Bank of America](extensions/Bank%20of%20America.lua) | **0.91 Beta** | Username/Passwort + MFA; Cookie-Import | Sparta-Login mit RSA-Krypto-API; Cookie-Import als Alternative |
| [Fidelity](extensions/Fidelity.lua) | **0.92 Beta** | Cookie-Import | Username/Passwort blockiert (Akamai + MFA) |
| [MLP Versicherungen](extensions/MLP%20Versicherungen.lua) | **0.91 Beta** | Cookie-Import; JWE/SecureGo implementiert | Direct-Login, wenn die erforderlichen MoneyMoney-Krypto-APIs verfügbar sind |
| [Presidential Bank](extensions/Presidential%20Bank.lua) | 1.01 | Username/Passwort + MFA | Cookie-Import optional |
| [Shareview](extensions/Shareview.lua) | 1.01 | Username/Passwort + MFA | Cookie-Import optional |

**Beta:** Der Cookie-Import ist der unterstützte Anmeldeweg. Bei MLP ist der
JWE-/SecureGo-Login implementiert und wird verwendet, wenn MoneyMoney die
benötigten Zufalls-, Base64url-, RSA- und A256GCM-APIs bereitstellt; andernfalls
fordert die Extension den Cookie-Import an.

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

### Ablauf (empfohlen: Safari Extension)

1. Im Browser vollständig einloggen (inkl. MFA)
2. Kontoseite / Vertragsübersicht öffnen
3. Cookies mit der **MoneyMoney Helper**-Extension kopieren (siehe unten)
4. `COOKIE:…`-String als Passwort in MoneyMoney einfügen

Die Extensions persistieren die Verbindung und ihre bankspezifischen
Sessiondaten in `LocalStorage`. Folge-Syncs prüfen und verwenden diese Daten,
solange die jeweilige Bank die Session noch akzeptiert. Die gespeicherten
Felder sind unter [Lua-Extensions](docs/LUA-EXTENSIONS.md) aufgeführt.

### 1. Safari Extension (empfohlen)

**Empfohlene Methode:** Session-Cookies inkl. HttpOnly über die offizielle Browser-API — zuverlässig unter Safari (macOS).

1. Extension bauen/starten: siehe [browser-extension/README.md](browser-extension/README.md) (Safari: Xcode Run der Hüllen-App)
2. Safari → **Einstellungen → Erweiterungen** → **MoneyMoney Helper** aktivieren  
   (unter macOS 26 und neuer **nicht** „Websites bearbeiten“ öffnen — Safari-Bug)
3. Bank-Seite öffnen; ggf. Zugriff über die Safari-Toolbar erlauben
4. Extension-Icon → **Cookies kopieren**
5. In MoneyMoney ins Passwortfeld einfügen (`COOKIE:…`)

Dieselbe Extension funktioniert auch in Chrome, Edge, Brave und Firefox (Installation ohne Xcode, siehe README der Extension).

### 2. Export per HAR (Alternative)

DevTools → Network → **Save all as HAR**, dann:

| Bank | Befehl | Wichtige Cookies |
|------|--------|------------------|
| Bank of America | `python3 scripts/extract-boa-cookies.py export.har` | `SMSESSION`, `SSOTOKEN`, `LSESSIONID` |
| Fidelity | `python3 scripts/extract-fidelity-cookies.py export.har` | kritisch: `_abck`, `bm_sz`, `ATC`, `ET`, `SESSION_SCTX`, `PIT`; zusätzlich unter anderem `FC`, `RC`, `SC`, `MC`, `PORTSUM_XSRF-TOKEN`, `bm_*` |
| MLP Versicherungen | `python3 scripts/extract-mlp-cookies.py export.har` | `VUSESSIONID` von `vue.mlp.de` |
| Presidential Bank | `python3 scripts/extract-presidential-cookies.py export.har` | `SESSION_TOKEN`, `rftoken` |
| Shareview | `python3 scripts/extract-shareview-cookies.py export.har` | `FedAuth` |

### 3. Tampermonkey (optional)

`scripts/moneymoney-cookie-exporter.user.js` — **Alt+C** auf der Kontoseite. In Safari oft **keine** HttpOnly-Cookies; dafür die Safari Extension oder HAR verwenden.

### Fidelity: dauerhafte Session

Nach SMS-MFA **„Don't ask me again on this device“** aktivieren, erst nach **Portfolio Summary** exportieren.

### MLP: Vue-Session

Vertragsübersicht auf `vue.mlp.de` öffnen, bevor exportiert wird. Beim ersten Zugriff SSL-Zertifikat für `vue.mlp.de` in MoneyMoney bestätigen.

## Direct-Login (Presidential Bank, Shareview)

### Presidential Bank

Username + Passwort → MFA (SMS, E-Mail, Voice oder TOTP). Alternativ wird
`COOKIE:SESSION_TOKEN=…;rftoken=…;…` akzeptiert. Session, Refresh-/CSRF-Token
und die Kennung des privaten Geräts (`MAF_IB_*`) werden in `LocalStorage`
gespeichert. Ein als privat registriertes Gerät darf die persistierte Session
auch nach einer Änderung des MoneyMoney-Zugangsschlüssels wiederverwenden.

### Shareview

Username + Passwort + Geburtsdatum + sechsstelliger MFA-Code. Für
Background-Sync: `username|TT.MM.JJJJ` als Benutzername (Geburtsdatum im
Keychain); auch `/` und `-` sind als Datumstrenner zulässig. Alternativ kann
`COOKIE:FedAuth=…` manuell importiert werden.

## Dokumentation

| Dokument | Inhalt |
|----------|--------|
| [MoneyMoney Web Banking API](https://moneymoney.app/api/webbanking/) | Offizielle Extension-API |
| [browser-extension/README.md](browser-extension/README.md) | MoneyMoney Helper (Safari/Chrome/…) — Cookie-Export |
| [docs/LUA-EXTENSIONS.md](docs/LUA-EXTENSIONS.md) | Extensions (Login, Cookie-Import, Abruf) |
| [docs/ENGINE-API-GAPS.md](docs/ENGINE-API-GAPS.md) | Fehlende Engine-APIs für Direct-Login |

## Entwicklung

Repository: https://github.com/rosch100/moneymoney-extensions

Lokal: Lua 5.4, Python 3.11.

```bash
for f in tests/*.lua; do lua "$f"; done
python3 tests/test_extensions_conformance.py
python3 tests/test_external_scripts_conformance.py
python3 tests/test_workflow_security.py
python3 tests/test_cookie_export_config.py
python3 tests/test_browser_extension_manifest.py
node tests/test_cookie_export.mjs
```

CI: [`.github/workflows/ci.yml`](.github/workflows/ci.yml)

## Lizenz

MIT
