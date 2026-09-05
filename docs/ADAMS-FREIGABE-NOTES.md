# Notizen: Antwort an Michael Adams (Freigabe)

Stand nach Umsetzung der Sicherheitsrückmeldungen und Folge-Härtung.

## Amazon

- Neuer Service-Name: **Amazon Bestellungen** (nicht „Amazon Orders“, nicht nur „Amazon“)
- Version: **2.0**
- Absolute `http(s)://`-URLs werden gegen `https://www.amazon.de` / `baseurl` geprüft; fremde Hosts lösen einen Fehler aus
- Runtime-Requests (inkl. Form-Actions) und Account-Note-Overrides laufen über dieselbe Host-Prüfung
- Repo: https://github.com/rosch100/Amazon-MoneyMoney

## Shareview

- Version: **1.02**
- Federation-Hosts als Konstanten (für Whitelist):
  - `portfolio.shareview.co.uk`
  - `www.equiniti.com` (ADFS: `https://www.equiniti.com/adfs/ls/`)
- Auto-Post `hiddenform` und Login/MFA-Form-Actions nur noch zu diesen Hosts; sonst Fehler ohne weiteren Request
- Repo: https://github.com/rosch100/Shareview-MoneyMoney

## Presidential Bank

- Version: **1.01**
- Absolute `resultURL` nur zu `www.presidentialpcbanking.com`
- Eigenes Repo: https://github.com/rosch100/Presidential-Bank-MoneyMoney

## Weitere Eigenrepos

- https://github.com/rosch100/Bank-of-America-MoneyMoney (Request-URL-Allowlist `secure.bankofamerica.com`)
- https://github.com/rosch100/Fidelity-MoneyMoney
- https://github.com/rosch100/MLP-Versicherungen-MoneyMoney (kein `load()` auf Server-JSON; JWKS/iframe Host-Allowlist)

Hub (Helper/Scripts/Docs): https://github.com/rosch100/moneymoney-extensions

## Hinweis Engine-API (Info, kein Blocker)

Zur Kenntnis: RSA-OAEP SHA-512 / Ed25519 im nächsten MM-Update;
`WebbankingBrowser` für Lua nicht geplant — vermerkt in `docs/ENGINE-API-GAPS.md`.
