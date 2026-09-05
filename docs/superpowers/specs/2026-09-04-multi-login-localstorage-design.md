# Multi-Login: LocalStorage-Isolation für alle Extensions

Datum: 2026-09-04

Status: **Implementiert** (2026-09-04)

## Ziel

Mehrere MoneyMoney-Bankzugänge derselben Extension mit **unterschiedlichen
Login-Daten** zuverlässig parallel betreiben: keine Session-/Cookie-/Cache-
Vermischung, Session-Persistenz pro Login bleibt erhalten.

## Kontext

`LocalStorage` der Web-Banking-Engine ist **pro Extension global** (nicht pro
Bankzugang). Bisherige `connectionAccountKey`-Checks verhindern Cross-Talk nur
teilweise: ein einzelner `storage.connection`-Slot überschreibt die andere
Session. Shareview nutzt eine feste Kontonummer. Amazon hält Order-Cache und
Harvest-State flach ohne Login-Namespace.

## Nicht-Ziele

- Kein Aufteilen der Holdings/Konten *innerhalb* eines Logins (außer bereits
  vorhandener `ListAccounts`-Logik).
- Kein gemeinsames Lua-Modul im Hub (Extensions bleiben einzelne `.lua`-Dateien).
- **Breaking nur Amazon erlaubt.** BoA, Fidelity, MLP, Presidential, Shareview
  dürfen bestehende MoneyMoney-Konten nicht ungültig machen (Refresh der
  bisherigen Kontonummern bleibt).

## Muster (alle Extensions)

### Connection-Map

```text
LocalStorage.connectionsByAccount[accountKey] = {
  connection = <Connection>,
  -- optional extension-spezifischer Session-State
}
LocalStorage.connection           -- Spiegel der *aktiven* Connection (Debug/Legacy)
LocalStorage.connectionAccountKey -- aktiver accountKey
```

- `accountKey` = Login-Identität aus `credentials[1]` / Username (Shareview:
  Username **ohne** DOB-Suffix).
- Wiederverwendung nur, wenn Map-Eintrag für denselben Key existiert.
- `EndSession`: bei aktivem Login-Bucket / persistierter Connection keinen
  remote Logout; Map-/Bucket-Eintrag behalten. Legacy-Felder auf aktiven Key
  spiegeln, nicht die ganze Map löschen.
  Amazon: `shouldPersistAmazonLoginSession` → kein `reallyLogout`-Abruf, wenn
  bereits ein **anderer** Login-Bucket existiert.

### Session-Beilagen (Cookies u. ä.)

Pro `accountKey` im Map-Eintrag speichern (nicht top-level überschreiben),
**außer** wo die Engine nested Tables nicht zuverlässig serialisiert:

| Extension | Persistenz über MM-Neustart |
| --- | --- |
| Shareview | `sessionCookies` als **Cookie-Header-String** + Restore via `connection:setCookie` (API: Jar stirbt mit Skriptlauf) |
| MLP | Cookie-**Tabelle** + `setCookie`; Connection oft zusätzlich (HttpOnly) |
| Presidential | Private-Device (`MAF_IB_*`): flacher String `presidentialPrivateDeviceCookieHeader` (+ Map-Spiegel); **kein** `Connection`-Userdata in LocalStorage |
| BoA / Fidelity | Connection-Jar / Cookie-Import |
| Amazon | siehe Login-Bucket |

**MM-API:** Cookie-Jar gilt nur für die Skriptlaufzeit; Dauerhaftes nur über
`LocalStorage` (serialisierbare Werte) und anschließendes `setCookie`.

**Presidential Private-Device:** Ein installationsweiter Slot (nicht streng
pro Multi-Login-Key). Restore darf Account-Key-Mismatch nicht blockieren —
sonst `dedicated=true` / `privateCount=0` und erneut TOTP.

## Shareview

- Neue Konten: Kontonummer `SV.<username>` (Username ohne `|DOB`);
  Name `Shareview (<username>)`.
- Bestehend: `shareview-portfolio` bleibt gültig und wird weiter refreshed
  (kein Forced Re-Setup).
- FedAuth-Persistenz: Cookie-Header-String in Map/`sessionCookies` (nicht nur
  Connection-Userdata).
- Version **1.04**.

## Amazon

- Login-Buckets: `LocalStorage.logins[loginKey]` hält den flachen Harvest-/Cache-
  State; `LocalStorage._activeLoginKey` markiert den aktiven Login.
- Beim Session-Start: aktiven Bucket suspendieren, Ziel-Bucket aktivieren
  (Felder wieder auf Top-Level legen, damit bestehender Code unverändert bleibt).
- Erstmigration: existierender flacher State ohne `_activeLoginKey` wandert in
  den ersten aktivierenden Login (Single-User-Upgrade).
- `loginKey` = normalisierte Login-E-Mail (`secUsername`).
- Version **2.01**.

## BoA / Fidelity / Presidential / MLP

- Connection-Map wie oben; bestehende Account-Discovery unverändert.
- Presidential: `persistSessionState` / `restore` schreiben Snapshot am
  Map-Eintrag **ohne** Connection-Userdata; Private-Device zusätzlich als
  `presidentialPrivateDeviceCookieHeader` (Shareview-Muster). Legacy-Top-Level-
  Fallback nur wenn **kein** Map-Eintrag für den Login existiert (leerer Eintrag
  darf fremde Session-Cookies nicht übernehmen; Private-Device-Slot ist
  ausgenommen, siehe oben).
- Versionen: BoA **0.92**, Fidelity **0.93**, Presidential **1.09**, MLP **0.92**.

## Tests

- Pro Extension: zwei verschiedene `accountKey`s → zwei Connections in der Map;
  Restore liefert jeweils die richtige Connection / Cookies / Cache.
  Evidence: Shareview, Presidential, BoA, Fidelity, MLP Unit-Tests; Amazon
  `test/test_multi_login_storage.lua`.
- Shareview: Nummern-Ableitung; Legacy-`shareview-portfolio` weiter refreshbar.
- Amazon: Bucket-Switch erhält getrennte `OrderCache`-Inhalte; Persistenz ohne
  remote Logout wenn `_activeLoginKey` gesetzt.

## Doku

- Hub `README.md` / `docs/LUA-EXTENSIONS.md`: Multi-Login kurz vermerken.
- Eigenrepo-READMEs: Version; Shareview: Legacy-Konten bleiben gültig.
