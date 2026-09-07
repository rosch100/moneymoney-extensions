# Extensions mit MoneyMoney Signatur

Drop-Ordner für von MoneyMoney signierte `.lua`-Dateien (Freigabe Michael Adams).
Beim Übernehmen in die Eigenrepos **diese Dateien bevorzugen** (nicht Mail-Anhänge).

| Datei hier | Ziel-Repo | Hinweis |
| --- | --- | --- |
| `amazon-bestellungen.lua` | Amazon-MoneyMoney | früher von Adams als `amazon-orders-2.lua` |
| `Presidential Bank.lua` | Presidential-Bank-MoneyMoney | 1:1 |
| `Pluxee Benefits.lua` | Pluxee-MoneyMoney | 1:1 |
| `Bank of America.lua` | Bank-of-America-MoneyMoney | **nicht** 1:1 übernehmen — enthält noch falsche Base64-APIs; Repo hat `MM.base64` / `MM.base64decode` und braucht Neusignierung |

Nach Neusignierung von BoA die Datei hier ersetzen und ins Eigenrepo kopieren.
