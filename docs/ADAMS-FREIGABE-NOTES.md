# Notizen: Antwort an Michael Adams (Freigabe)

Stand nach Umsetzung der Sicherheitsrückmeldungen.

## Amazon

- Neuer Service-Name: **Amazon** (nicht mehr „Amazon Orders“)
- Version: **2.0**
- Absolute `http(s)://`-URLs werden gegen `https://www.amazon.de` / `baseurl` geprüft; fremde Hosts lösen einen Fehler aus
- Repo: https://github.com/rosch100/Amazon-MoneyMoney

## Shareview

- Version: **1.02**
- Federation-Hosts als Konstanten (für Whitelist):
  - `portfolio.shareview.co.uk`
  - `www.equiniti.com` (ADFS: `https://www.equiniti.com/adfs/ls/`)
- Auto-Post `hiddenform` nur noch zu diesen Hosts; sonst Fehler ohne weiteren Request
- Repo: https://github.com/rosch100/Shareview-MoneyMoney

## Presidential Bank

- Eigenes Repo: https://github.com/rosch100/Presidential-Bank-MoneyMoney

## Weitere Eigenrepos

- https://github.com/rosch100/Bank-of-America-MoneyMoney
- https://github.com/rosch100/Fidelity-MoneyMoney
- https://github.com/rosch100/MLP-Versicherungen-MoneyMoney

Hub (Helper/Scripts/Docs): https://github.com/rosch100/moneymoney-extensions

## Hinweis Engine-API (Info, kein Blocker)

Zur Kenntnis: RSA-OAEP SHA-512 / Ed25519 im nächsten MM-Update;
`WebbankingBrowser` für Lua nicht geplant — vermerkt in `docs/ENGINE-API-GAPS.md`.
