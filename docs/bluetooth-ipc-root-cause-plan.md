# Bluetooth-IPC: Root-Cause- und Bereinigungsplan

Status: **Root-Fix implementiert, Engineering-Audit ohne offene Findings und
live grün; physische Multi-Monitor-Abnahme bleibt wie vereinbart
zurückgestellt**

Arbeitsbereich: ausschließlich das Shibumi-Repository und die von der Shibumi-Suite verwaltete Installation

Nicht im Arbeitsbereich: Änderungen unter `/usr/share/omarchy`, Omarchy-Paketpatches, `GitHub.png`, `Qt.atob` und Portal-Warnungen

## Ziel

Der Produktionsprozess darf den IPC-Namen `omarchy.bluetooth` genau einmal
registrieren. Gleichzeitig müssen alle sechs öffentlichen Methoden erhalten bleiben:

- `open`
- `show`
- `toggle`
- `close`
- `hide`
- `toggleBluetooth`

Die Lösung muss außerdem die screen-lokale Shibumi-Anzeige, den einen
prozessweiten Bluetooth-Backend-Eigentümer, die Discovery-Leases und das
simulierte Multi-Output-Lifecycle-Verhalten erhalten. Die physische
Multi-Monitor-Abnahme ist mangels zweitem Monitor zurückgestellt und blockiert
diesen Bluetooth-Fix nicht. Das bloße Ausblenden der Warnung oder das Entfernen
eines Handlers ohne vollständigen Lifecycle-Nachweis ist keine Lösung.

## Bewiesener Ist-Zustand

### Produktionssymptom

Vor dem bereinigenden Shibumi-Repair waren seit dem aktuellen
Quickshell-Prozessstart vier fehlgeschlagene Registrierungen für
`omarchy.bluetooth` protokolliert. Der transaktionale Repair am 5. August 2026
um 21:22 Uhr lud die Plugins im unveränderten Produktionsprozess neu und
erzeugte drei weitere Ereignisse. Aktuell sind es damit sieben
Registrierungsereignisse durch Start/Reload, nicht sieben gleichzeitig aktive
IPC-Ziele.

`qs ipc show` zeigt am aktiven Ziel nur `open`, `show`, `toggle`, `close` und
`hide`. `toggleBluetooth` fehlt. Damit hat aktuell Shibumis Handler die
Registrierung gewonnen; der Handler des versteckten offiziellen Panels wurde
abgewiesen.

### Tatsächliche Eigentümer

1. Shibumi registriert in
   `hancore.shibumi.bluetooth/Service.qml` einen `IpcHandler` mit dem Ziel
   `omarchy.bluetooth`.
2. Shibumi lädt in
   `hancore.shibumi.bluetooth/BluetoothPanelBridge.qml` das vollständige
   offizielle Omarchy-Panel als versteckten prozessweiten Backend-Host.
3. Dieses offizielle Panel registriert in
   `/usr/share/omarchy/shell/plugins/panels/bluetooth/Panel.qml` selbst und
   bedingungslos einen zweiten `IpcHandler` mit demselben Ziel. Nur dieser
   Handler bietet zusätzlich `toggleBluetooth` an.

### Root Cause

Die unmittelbare Root Cause liegt in der Shibumi-Integration, nicht in der
Omarchy-Bar:

- Shibumi setzt beim Laden des offiziellen Panels `manageIpc: false` und nimmt
  an, damit sei dessen IPC vollständig abgeschaltet.
- `manageIpc` steuert aber nur den generischen Handler aus
  `/usr/share/omarchy/shell/Ui/Panel.qml`.
- Das Bluetooth-Panel setzt selbst bereits `manageIpc: false`, weil es statt
  des generischen Handlers einen eigenen erweiterten Handler mit
  `toggleBluetooth` besitzt.
- Dieser eigene Handler ist nicht an `manageIpc` gebunden und kann von
  Shibumis Bridge daher nicht deaktiviert werden.
- Shibumis Kommentar, der versteckte offizielle Eigentümer habe deaktiviertes
  IPC, beschreibt somit einen Vertrag, den das reale Omarchy-Panel nie erfüllt.

Omarchys Panel funktioniert für sich genommen vertragsgemäß. Erst Shibumi
lädt dieses vollständige Bar-Widget als verstecktes Backend und beansprucht
parallel dessen öffentlichen IPC-Namen. Deshalb muss die Korrektur in Shibumis
Adapter- und Ownership-Architektur erfolgen. An Omarchy wird nichts geändert.

### Warum die bisherigen Tests den Fehler nicht fanden

Der Fehler kam zusammen mit Shibumis Bluetooth-Ownership-Design in Commit
`8bdab3b` (`v0.1.0`) in das Repository. Die Test-Oracle bildet die falsche
Annahme ab:

- `tests/contract-regression.sh` verlangt derzeit ausdrücklich Shibumis
  `target: "omarchy.bluetooth"`.
- Derselbe Test betrachtet `manageIpc: false` fälschlich als Nachweis, dass der
  versteckte offizielle Eigentümer kein IPC mehr besitzt.
- `tests/fixtures/BluetoothTestPanel.qml` bildet das echte Omarchy-Panel nicht
  vollständig nach: Der bedingungslose eigene `IpcHandler` mit
  `toggleBluetooth` fehlt.
- Die Smoke-Tests prüfen UI-, Backend- und Discovery-Lifecycle, aber nicht die
  globale Quickshell-IPC-Registry und nicht die vollständige Methodentabelle.

Damit ist nicht nur die Implementierung fehlerhaft; auch das bisherige
Akzeptanzkriterium bestätigt das falsche Design. Beide Teile müssen gemeinsam
korrigiert werden.

## Nicht ausreichende Scheinlösungen

Folgende Änderungen dürfen nicht als Abschluss akzeptiert werden:

- die Warnzeile filtern oder den Logger leiser stellen;
- nur Shibumis Handler löschen und lediglich prüfen, dass die Warnung weg ist;
- `manageIpc: false` erneut setzen;
- den Omarchy-Handler unter `/usr/share/omarchy` ändern;
- einen zweiten, anders benannten Handler hinzufügen, während der öffentliche
  Lifecycle unvollständig bleibt;
- die vier historischen Warnzeilen mit vier dauerhaft aktiven Instanzen
  verwechseln;
- eine Lösung freigeben, bei der `open` funktioniert, aber `close`/`hide` das
  sichtbare Shibumi-Panel nicht mehr schließen;
- das versteckte Omarchy-Panel dauerhaft geöffnet halten, ohne unsichtbare
  Layer-Surface, Focus-, Input- und Popout-Nebenwirkungen zu prüfen.

## Arbeitsphasen

### Phase 0 – Reproduzierbare Baseline einfrieren

- [x] Commit, `origin/main`, Worktree und installierte Plugin-Digests erfassen.
- [x] Genau einen Produktionsprozess und dessen Startzeit nachweisen.
- [x] `qs ipc show` sichern und die fünf aktuell sichtbaren Methoden erfassen.
- [x] Runtime-Log ab Prozessstart sichern und die Duplicate-Target-Ereignisse
      mit Zeitstempel zählen.
- [x] Durch kontrollierten Plugin-Reload prüfen, ob pro Service-/Bridge-Aufbau
      genau ein weiterer Registrierungsfehler entsteht.
- [x] Bluetooth-Funkzustand bei dieser Phase nicht verändern.

Abbruchkriterium: Wenn sich der Konflikt mit exakt einer Shibumi-Serviceinstanz
und exakt einem versteckten offiziellen Panel nicht reproduzieren lässt, wird
nicht implementiert; zuerst wird die Ownership-Map korrigiert.

### Verbindlicher Bluetooth-Zustands- und Rollback-Vertrag

Vor jedem Test, der `toggleBluetooth` auslösen kann, muss ein vollständiger
Ausgangssnapshot vorliegen:

- [ ] Adapter vorhanden/nicht vorhanden;
- [ ] Radiozustand `enabled`;
- [ ] Discovery-Zustand `discovering`;
- [ ] Shibumi-Eigentum an Discovery (`discoveryOwned` und Generation);
- [ ] Anzahl und Identität der offenen Shibumi-Panel-Sessions;
- [ ] Adressen der verbundenen Geräte;
- [ ] aktive Bluetooth-Audio-Route, soweit der Host sie zuverlässig auslesen
      und wiederherstellen kann;
- [ ] aktiver IPC-Eigentümer und vollständige IPC-Methodentabelle;
- [ ] Prozess-ID, Payload-Commit und Zeitpunkt des Snapshots.

Für den isolierten Fixture-Test gilt eine harte Garantie:

- [ ] Zustand nach erfolgreichem Test exakt auf den Snapshot zurücksetzen;
- [ ] denselben Rollback nach Assertion-Fehler, Timeout, vorzeitigem Abbruch und
      Objektzerstörung ausführen;
- [ ] Rollback nicht nur aufrufen, sondern nach einem begrenzten Event-Loop-
      Settle erneut auslesen und byte-/wertgleich gegen den Snapshot prüfen;
- [ ] der Test schlägt fehl, wenn Cleanup oder Nachweis unvollständig bleibt.

Für die Live-Sitzung gilt:

- kein automatischer Funk-Toggle;
- ein manueller Funk-Toggle nur nach ausdrücklicher Nutzerfreigabe;
- vor der Mutation Snapshot und Wiederherstellbarkeit prüfen;
- bei ursprünglich aktivem Radio mit verbundenen Geräten nicht mutieren, wenn
  Reconnect und Audio-Routing nicht deterministisch wiederherstellbar sind;
- nach Erfolg oder Abbruch Radio, Discovery, Geräteverbindungen und Audio-Route
  erneut prüfen; jede Abweichung ist ein fehlgeschlagener Rollback und kein
  bestandener Test.

Damit ist der Fixture-Rollback deterministisch. Für echte Hardware wird keine
stärkere Wiederherstellung versprochen, als BlueZ, Geräte und Audio-Host
nachweislich erlauben; ist exakte Wiederherstellung nicht belegbar, findet die
Live-Mutation nicht statt.

### Phase 1 – Root Cause in einem isolierten Test beweisen

- [x] Eine produktionsnahe Fixture ergänzen, die wie das reale Omarchy-Panel
      einen eigenen bedingungslosen `IpcHandler` inklusive
      `toggleBluetooth` besitzt.
- [x] Shibumi-Service und diese Fixture in einem isolierten Quickshell-Prozess
      gemeinsam laden.
- [x] Vor der Korrektur automatisiert nachweisen:
  - [x] pro Lade-Reihenfolge genau ein Duplicate-Target-Fehler entsteht;
  - [x] nur einer der beiden Handler aktiv bleibt;
  - [x] bei Shibumi als Gewinner `toggleBluetooth` in der IPC-Tabelle fehlt.
- [x] Lade-Reihenfolge gezielt umkehren und beweisen, dass das Problem von der
      doppelten Eigentümerschaft und nicht zufällig vom Timing verursacht wird.
- [ ] Service-Neuladen und Bridge-Neuladen getrennt testen, um die
      Produktionsereignisse auf konkrete Lifecycle-Pfade zurückzuführen.

Ergebnis dieser Phase ist ein vor der Korrektur roter Regressionstest. Ohne
diesen roten Test wird keine Lösung implementiert.

### Phase 2 – Zielarchitektur anhand vollständiger Verträge wählen

Es wird genau ein IPC-Eigentümer festgelegt. Vor einer Entscheidung werden
mindestens diese beiden Shibumi-seitigen Varianten als Prototyp geprüft:

#### Variante A – offizielles Panel bleibt alleiniger IPC-Eigentümer

Shibumis zusätzlicher Handler entfällt. Öffnen, Schließen und Umschalten des
offiziellen Controllers werden bidirektional mit dem sichtbaren Shibumi-Panel
synchronisiert.

Pflichtprüfungen:

- `open`, `show` und `toggle` öffnen das richtige screen-lokale Shibumi-Panel;
- `close`, `hide` und das zweite `toggle` schließen genau dieses Panel;
- `toggleBluetooth` bleibt vorhanden;
- das unsichtbare offizielle Panel erzeugt keine sichtbare oder
  input-blockierende Layer-Surface, keinen Focus-Grab und keinen verwaisten
  Popout-Eigentümer;
- direkter Mausklick auf Shibumi und externer IPC-Aufruf führen denselben
  Lifecycle aus;
- bei zwei simulierten Outputs wird der fokussierte Output gewählt und kein
  zweites Backend erzeugt.

Diese Variante wird verworfen, sobald das Offenhalten/Synchronisieren des
versteckten offiziellen Panels eine unsichtbare Surface oder asymmetrische
Close-Semantik erzeugt.

#### Variante B – Shibumi besitzt IPC und einen eigenen Backend-Adapter

Shibumi lädt das vollständige offizielle Bar-Widget nicht mehr als Backend.
Stattdessen besitzt ein Shibumi-Adapter genau die erforderlichen
Quickshell-Bluetooth-/Audio-Modelle und Aktionen. Dadurch existiert der
offizielle selbstregistrierende Handler im Shibumi-Prozesspfad nicht.

Pflichtprüfungen:

- genau ein Bluetooth-/PipeWire-Modellpfad im Prozess;
- funktionale Parität für Adapterzustand, Discovery, bekannte/verbundene
  Geräte, Connect, Disconnect, Forget und Audio-Handoff;
- keine parallel instanziierte offizielle Bluetooth-Bar-Komponente;
- vollständiger Legacy-IPC-Vertrag inklusive `toggleBluetooth`;
- sauberer Discovery-Abbau nach der letzten Panel-Session;
- klar dokumentierte Wartungsgrenze gegenüber künftigen Omarchy-Änderungen.

Diese Variante ist invasiver, beseitigt aber die strukturelle Kopplung an ein
vollständiges UI-Objekt als angebliches Backend. Sie wird bevorzugt, falls
Variante A den unsichtbaren UI-Lifecycle nicht sicher eliminieren kann.

#### Externe Variante – neuer Omarchy-Hostvertrag

Ein upstream schaltbarer eigener Bluetooth-IPC-Handler oder ein separates
Omarchy-Service-Entry-Point wäre langfristig der sauberste Hostvertrag. Das ist
Sache der Omarchy-Entwickler und ausdrücklich **kein** Arbeitsschritt dieses
Plans. Shibumi darf davon erst Gebrauch machen, wenn ein solcher Vertrag in
der installierten, unterstützten Omarchy-Version tatsächlich vorhanden ist.

### Phase 3 – Entscheidung protokollieren

- [x] Für A und B eine kleine Entscheidungsmatrix erstellen: IPC-Vollständigkeit,
      UI-/Input-Sicherheit, Backend-Einzigkeit, Multi-Monitor-Verhalten,
      Upstream-Kopplung und Wartungsaufwand.
- [x] Gewählte Variante mit Beweisen statt Vermutungen begründen.
- [x] Nicht gewählte Variante samt konkretem Ausschlussgrund dokumentieren.
- [x] Vor Implementierung einen Go/No-Go-Punkt setzen.

Entscheidung: Variante B. Variante A behält gerade das vollständige fremde
UI-Objekt im Prozess, dessen eigener bedingungsloser IPC-Handler die Root Cause
bildet. Variante B entfernt diesen Lifecycle vollständig und ist durch den
grünen Ein-Eigentümer-Test in beiden Backend-Lade-Reihenfolgen belegt. Der
zusätzliche Wartungsaufwand ist auf einen klar abgegrenzten nativen Adapter und
ein Modellmodul begrenzt.

### Phase 4 – Implementierung ausschließlich in Shibumi

Abhängig von Phase 3 werden nur die betroffenen Shibumi-Quellen geändert.
Wegen der parallelen V1-/Plugin-Struktur sind mindestens diese Spiegel zu
prüfen und konsistent zu halten:

- `hancore.shibumi.bluetooth/Service.qml`
- `hancore.shibumi.bluetooth/BluetoothBackendAdapter.qml`
- `hancore.shibumi.bluetooth/BluetoothModel.js`
- `hancore.shibumi.bluetooth/BarWidget.qml`
- `services/BluetoothService.qml`
- `adapters/BluetoothBackendAdapter.qml`
- `adapters/BluetoothModel.js`
- `widgets/BluetoothWidget.qml`

Außerdem werden die falschen Verträge und Dokumentationsaussagen korrigiert:

- `tests/contract-regression.sh`
- `tests/bluetooth-plugin-regression.sh`
- `tests/bluetooth-plugin-smoke.qml`
- `tests/bluetooth-widget-smoke.qml`
- Bluetooth-Fixtures unter `tests/fixtures/`
- `docs/phase2-validation.md`
- `docs/phase2-ownership-map.md`

- [x] Keine Datei unter `/usr/share/omarchy` verändern.
- [x] Keine Runtime-Warnung unterdrücken.
- [x] Keine reale Bluetooth-Funkmutation in automatischen Produktionstests.
- [x] Quell- und Plugin-Spiegel über denselben Contract und denselben Smoke prüfen.

### Phase 5 – Testpyramide

#### Statisch

- [x] Repositoryweit genau einen beabsichtigten Shibumi-seitigen Besitzpfad
      für `omarchy.bluetooth` nachweisen.
- [x] Veraltete aktive Verträge über `manageIpc: false` entfernen; die
      historische Root-Cause-Erklärung bleibt bewusst erhalten.
- [ ] `qmllint` nur mit Qt 6 über `/usr/lib/qt6/bin/qmllint` ausführen;
      `/usr/bin/qmllint` ist auf diesem System Qt 5 und für diesen Bericht nicht
      maßgeblich.
- [ ] Den reproduzierbaren Aufruf protokollieren:
      `/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell hancore.shibumi.network/NetworkPanel.qml`.
- [ ] `qmllint` als Delta gegen `origin/main` auswerten; keine statische
      Linterzahl als Runtime- oder Health-Fehler interpretieren.
- [x] `git diff --check` und Contract-Tests ausführen.

Verbindliche Terminologie für den aktuellen Netzwerkpanel-Baseline-Bericht:

- 635 tatsächliche Ausgabezeilen;
- 200 Zeilen mit einem `Warning:`-Header;
- 198 eigenständige Top-Level-Diagnosen plus zwei eingebettete Importwarnungen;
- 99 normalisierte Interface-Befunde als bewusst ausgewiesene Teilmenge:
  - 61 Host-Interface-Befunde (`missing-property`);
  - 38 `Commons.Style.font`-Befunde;
- die 99 sind **nicht** die vollständige `qmllint`-Diagnosezahl und die 200 sind
  **nicht** die Anzahl der Ausgabezeilen;
- `Commons.Style` besitzt zusätzlich 41 `space`-Referenzen; deshalb darf die
  Zahl 38 nicht pauschal als Anzahl aller Style-Verwendungen bezeichnet werden.

#### Isolierter Runtime-Test

- [x] Der in Phase 1 rote Duplicate-Test wird grün.
- [x] Die IPC-Tabelle enthält exakt die sechs erwarteten Methoden.
- [x] Reihenfolgen `open -> close`, `show -> hide`, `toggle -> toggle` prüfen.
- [x] Service/Adapter in beiden Lade-Reihenfolgen sowie über wiederholte
      Produktions-Reloads prüfen; kein Duplicate und kein verwaistes Ziel.
- [x] Zwei simulierte Outputs, gemeinsames Backend und getrennte Panel-Sessions
      prüfen.
- [x] Discovery-Lease, fremden Discovery-Zustand und finalen Cleanup prüfen.
- [x] Den vor `toggleBluetooth` erfassten Fixture-Zustand nach Erfolg und einem
      simulierten Abbruch exakt wiederherstellen und nachprüfen; der
      Exit-Cleanup verwendet denselben Rollback-Pfad bei Fehler und Timeout.

#### Live-Abnahme

- [x] Bereitstellung ausschließlich mit `scripts/shibumi-suite`, nicht per
      direktem Kopieren.
- [x] Danach genau einen Quickshell-Produktionsprozess nachweisen.
- [x] Log-Cursor unmittelbar vor Reload/Restart setzen und ausschließlich neue
      Warnungen auswerten.
- [x] Keine neue Duplicate-Target-Warnung nach sauberem Start und zwei
      kontrollierten
      Reloads.
- [x] `qs ipc show` zeigt alle sechs Methoden.
- [x] Öffnen/Schließen per IPC auf dem fokussierten Monitor visuell prüfen.
- [x] Sichtbare Layer, Focus, Eingabe und Popout-Wechsel beim IPC-Roundtrip
      prüfen.
- [ ] Bluetooth-Funkzustand nur nach ausdrücklicher Freigabe manuell toggeln;
      automatisiert bleibt dieser Schritt gemockt.
- [ ] Wenn ein manueller Toggle freigegeben wird, Ausgangszustand vorher
      erfassen und Wiederherstellung nach Erfolg sowie Abbruch nachweisen.
- [ ] Physische Multi-Monitor-Abnahme bis zur Verfügbarkeit eines zweiten
      Monitors ausdrücklich als offen protokollieren; sie blockiert den
      aktuellen Bluetooth-Fix nicht.
- [x] `hancore.shibumi.control-center/manager/shibumi-health` endet ohne
      Managed-Plugin-Fehler.

### Phase 6 – Abschluss und Rollback

Erfolg ist erst erreicht, wenn alle folgenden Bedingungen gleichzeitig gelten:

- [x] null neue Duplicate-Target-Warnungen im sauberen Start und in zwei
      Reloads des neuen Payloads;
- [x] genau ein registrierter `omarchy.bluetooth`-Eigentümer;
- [x] sechs vollständige IPC-Methoden;
- [x] symmetrisches Öffnen und Schließen des sichtbaren Shibumi-Panels;
- [x] kein unsichtbarer Layer-/Input-/Focus-Nebeneffekt;
- [x] ein prozessweiter Backend-Eigentümer;
- [x] simulierter Multi-Output- und Discovery-Lifecycle grün;
- [x] Fixture-Ausgangszustand nach Erfolg und simuliertem Abbruch exakt
      wiederhergestellt; Fehler/Timeout laufen über denselben Exit-Cleanup;
- [x] vollständige Shibumi-Contract-Suite grün;
- [x] Health ohne Fehler.

Der Code-/Payload-Rollback erfolgt ausschließlich auf den letzten nachweislich
grünen Shibumi-Commit und anschließend über `scripts/shibumi-suite repair`.
Davon getrennt stellt der oben definierte Zustands-Rollback Radio, Discovery,
Sessions, Geräte und Audio-Route nachweislich wieder her. Es werden weder
Omarchy-Dateien zurückgeschrieben noch fremde Desktop-Dateien verändert.

## Bewusste Abgrenzung für diesen Arbeitsgang

Diese Punkte werden nicht vermischt und blockieren den Bluetooth-Fix nicht:

- `Qt.atob`: Omarchy-Upstream, keine Shibumi-Änderung;
- Desktop-Portal-Registrierung: beobachten, solange keine Funktion ausfällt;
- fehlendes `GitHub.png`: fremder Desktop-Eintrag, wird ignoriert;
- Public-IP-Reveal: vollständig entfernt und erst nach einem sauberen stabilen
  Gesamtstand neu zu entwerfen;
- allgemeine `qmllint`-Baseline: eigener technischer Schuldenblock;
- Arch-Update-Panel und physische Multi-Monitor-Hardwareabnahme: separate
  offene Akzeptanzpunkte; die Hardwareabnahme folgt erst mit einem zweiten
  Monitor und blockiert die aktuelle Bluetooth-Bereinigung nicht.

## Abarbeitungsprotokoll

Für jede Phase werden Datum, Commit, ausgeführter Befehl, Exit-Code und relevante
Logzeilen direkt in diesem Dokument ergänzt. Eine Phase wird erst abgehakt,
wenn ihr Abbruch- beziehungsweise Erfolgskriterium belegt ist.

### Initiale Evidenz vom 5. August 2026

- Lokaler Stand nach Entfernung des Public-IP-Commits: `d79a1f2`, gegenüber
  dem frisch abgefragten `origin/main` (`040da9b`) genau einen Commit voraus
  und keinen Commit zurück.
- `shibumi-suite repair --yes` war erfolgreich; alle 24 installierten Payloads
  stimmen mit ihren aufgezeichneten Digests überein.
- Der Produktionsprozess blieb PID `996588`; damit ist der Anstieg von vier
  auf sieben Duplicate-Ereignisse eindeutig einem Plugin-Reload und nicht
  einem zweiten Quickshell-Prozess zuzuordnen.
- Neue Duplicate-Ereignisse: `21:22:41`, `21:22:41` und `21:22:42`, jeweils am
  expliziten Handler des offiziellen
  `/usr/share/omarchy/shell/plugins/panels/bluetooth/Panel.qml`.
- Die aktive IPC-Tabelle enthält weiterhin nur `open`, `close`, `hide`, `show`
  und `toggle`; `toggleBluetooth` fehlt.
- Health nach Repair: null Fehler, eine erwartete Source-Warnung (`ahead 1`,
  dirty wegen ungetrackter Arbeitsdokumente), 24/24 Managed Plugins korrekt.
- Die vollständige bestehende Contract-Suite ist grün. Das ändert nichts am
  IPC-Befund, sondern bestätigt die oben beschriebene Lücke in Fixture und
  Test-Oracle.
- Der Qt-6-`qmllint`-Baseline-Bericht ist terminologisch festgelegt: 635
  Ausgabezeilen, 200 `Warning:`-Header, 198 Top-Level-Diagnosen und die separat
  benannte normalisierte Interface-Teilmenge von 99 Befunden (61 Host plus 38
  `Commons.Style.font`).
- Die physische Multi-Monitor-Abnahme ist mangels zweitem Monitor zurückgestellt;
  die simulierten Zwei-Output-Tests bleiben Bestandteil der Regression.

### Roter IPC-Ownership-Test vom 5. August 2026

- Neue produktionsnahe Fixture:
  `tests/fixtures/BluetoothIpcOwnerTestPanel.qml`. Sie setzt wie das echte
  Omarchy-Panel `manageIpc: false`, besitzt aber trotzdem einen eigenen
  expliziten Handler mit allen sechs Methoden.
- Neuer isolierter Harness:
  `tests/bluetooth-ipc-ownership-smoke.qml` und
  `tests/bluetooth-ipc-ownership-regression.sh`.
- Der Test ist in `tests/bluetooth-plugin-regression.sh` eingebunden und macht
  die fokussierte Suite bis zur Root-Cause-Korrektur absichtlich rot.
- Ergebnis `service-first`: ein sichtbares Ziel, fünf Methoden, eine
  Duplicate-Warnung; `toggleBluetooth` fehlt.
- Ergebnis `official-first`: ein sichtbares Ziel, sechs Methoden, eine
  Duplicate-Warnung.
- Gesamt: vier verletzte Invarianten; Exit-Code 1 wie für die Red-Phase
  erwartet. Damit sind sowohl die globale Doppel-Eigentümerschaft als auch die
  ladeordnungsabhängige Methodentabelle reproduziert.
- Der Test verwendet ausschließlich Fixtures, verändert kein echtes Bluetooth
  und hinterlässt keinen zusätzlichen Quickshell-Prozess.

### Grüner Root-Fix vom 5. August 2026

- Gewählt und implementiert ist Variante B: `BluetoothBackendAdapter.qml`
  greift direkt auf Quickshells Bluetooth-/PipeWire-Singletons zu; das
  vollständige Omarchy-Bluetooth-Panel wird nicht mehr aufgelöst oder geladen.
- `Service.qml` ist der einzige Eigentümer von `omarchy.bluetooth` und bietet
  alle sechs Methoden einschließlich `toggleBluetooth` an.
- Der Adapter erhält Gerätefilterung, Pair/Connect/Disconnect/Forget über den
  bestehenden argumentbasierten Omarchy-Helper, Pending-Actions und den
  Bluetooth-Audio-Handoff. Er besitzt selbst keinen IPC-Handler.
- Discovery wird nur noch als Shibumi-eigen markiert, wenn Shibumi den Zustand
  tatsächlich von aus auf an gesetzt hat. Ein bereits aktiver fremder Scan
  bleibt nach dem letzten Shibumi-Panel aktiv.
- `tests/bluetooth-ipc-ownership-regression.sh` ist in den grünen
  Architekturvertrag überführt: `service-first` und `backend-first` ergeben
  jeweils ein Ziel, sechs Methoden und null Duplicate-Warnungen.
- Der fokussierte Bluetooth-Smoke ist grün. Er prüft zusätzlich den
  Radio-/Discovery-Roundtrip, zwei simulierte Outputs, Geräteaktionen,
  Session-Cleanup und fremdes Discovery-Eigentum.
- `tests/contract-regression.sh` ist vollständig grün, einschließlich 24
  selbstenthaltener Plugin-Payloads, Runtime-Smokes und Health-Verträgen.
- `/usr/lib/qt6/bin/qmllint` meldet für den neuen Adapter ausschließlich drei
  bekannte Quickshell-Typmetadaten-Hinweise (`BluetoothAdapter` und
  `UntypedObjectModel`), keinen Syntax- oder Bindungsfehler.
- Es wurde weder committed noch gepusht und keine Datei unter
  `/usr/share/omarchy` geändert. Die Live-Bereitstellung ist zu diesem
  Protokollzeitpunkt noch nicht erfolgt.

### Live-Abnahme vom 5. August 2026

- `scripts/shibumi-suite repair --yes` installierte den Arbeitsbaum
  transaktional; 24/24 Payloads stimmen mit ihren aufgezeichneten Digests
  überein.
- Beim ersten Hot-Swap aus dem bereits lebenden alten Hidden-Panel-Payload
  entstanden um `22:48:29` noch genau zwei Übergangs-Duplicates. Nach dem
  unmittelbar folgenden vollständigen `Configuration Loaded` wiederholten sie
  sich nicht.
- Der vom Nutzer ausgeführte `omarchy restart shell` lieferte einen sauberen
  Kaltstart auf PID `1597226`: sechs Bluetooth-IPC-Methoden und keine
  Duplicate-Warnung.
- Zwei anschließende echte `shibumi-suite reloadPayload`-Vollreloads um
  `22:51:05` und `22:51:09` waren vollständig warnungsfrei. Beide endeten mit
  sechs IPC-Methoden und genau einem Ziel.
- Das sichtbare Shibumi-Bluetooth-Panel wurde per `omarchy.bluetooth open`
  geöffnet, per Screenshot auf dem fokussierten einzigen Output bestätigt und
  mit `close` wieder geschlossen. Danach: Radio an, Discovery aus, Audio-Sink
  weiterhin SteelSeries.
- Health: null Fehler, acht erfolgreiche Prüfungen und ausschließlich die
  erwartete Source-Warnung `ahead 1 · dirty`.
- Ein verbundenes iPhone erschien bereits im Zeitfenster des manuellen
  Shell-Neustarts (BlueZ-Audioaktivität ab `22:50:40`), also vor dem visuellen
  Panel-Open-Test. Es wurde mangels ausdrücklicher Freigabe nicht getrennt;
  Discovery und Audio-Route entsprechen dem Vorherzustand.

### Engineering-Audit und finale Live-Abnahme vom 5. August 2026

- Der Audit fand drei Shibumi-seitige Ownership-/Reaktivitäts-Randfälle und
  korrigierte sie am Ursprung:
  - Pending-Actions reagieren nun zusätzlich auf die abgeleiteten
    Connected-/Known-/Discovered-Signale. Quickshells `ScriptModel.values`
    signalisiert nur Collection-Änderungen; die Geräteflags besitzen eigene
    Property-Signale.
  - `restartDiscovery()` beobachtet einen bereits extern laufenden Scan, ohne
    ihn zu toggeln oder zu übernehmen. Refresh plus sofortiges Schließen lässt
    diesen Scan nachweislich aktiv.
  - Discovery-Eigentum ist an die konkrete Adapterinstanz gebunden. Bei einem
    Adapterwechsel wird der alte eigene Scan beendet, während ein bereits
    aktiver Scan des neuen Adapters unangetastet bleibt.
- Die Component-Smokes prüfen Connect-, Disconnect- und Forget-Transitions,
  externes Discovery-Refresh/Close, Adapterwechsel und zwei simulierte Outputs.
- Der IPC-Harness erfasst den Fixture-Ausgangszustand dynamisch. Beide
  Lade-Reihenfolgen enden nach dem normalen Doppel-Toggle wieder bei `1:0`;
  nach dem simulierten Abbruchzustand `0:1` stellt der Cleanup exakt `1:0`
  wieder her.
- Die vollständige Contract-/Runtime-Suite endet mit Exit-Code 0. `qmllint`
  endet ebenfalls mit Exit-Code 0; pro V1-/Plugin-Spiegel bleiben nur dieselben
  drei bekannten Quickshell-Typmetadaten-Hinweise, keine QML-Fehler.
- Der finale transaktionale Repair um `23:10:35` ließ PID `1597226` bestehen.
  Danach: genau ein `omarchy.bluetooth`-Ziel, sechs Methoden, null neue
  Duplicate-Warnungen und null Runtime-Fehler. Die einzige neue Warnung ist das
  ausdrücklich ausgeklammerte fremde `GitHub.png`.
- Radio (`on`), Discovery (`off`) und Standard-Audio-Sink (SteelSeries Chat)
  stimmen vor und nach dem Repair überein. Das iPhone wurde nicht getrennt.
- Health bleibt bei null Fehlern, acht erfolgreichen Prüfungen und nur der
  erwarteten Source-Warnung (`ahead 1 · dirty`). Die drei produktiven
  Bluetooth-Dateien stimmen bytegenau mit dem installierten Payload überein.
- Audit-Ergebnis: **0 offene Bluetooth-Findings**. Die physische
  Multi-Monitor-Abnahme bleibt wie vereinbart zurückgestellt und blockiert den
  Commit nicht.

### Korrigierendes Folgeaudit nach Pi-Review vom 5. August 2026

Die vorstehende Aussage „0 offene Bluetooth-Findings“ war nicht final: Ein
anschließendes unabhängiges Review fand zwei mittlere Funktionsrisiken und ein
niedriges Harness-Risiko. Diese Befunde wurden test-first erneut geöffnet und
am Ursprung bearbeitet; Commit `8ddbd77` bleibt dabei unverändert und wird
nicht gepusht.

- Rote Regressionen belegten vor der Korrektur:
  - ein abgelehnter Discovery-Start wurde nicht erneut versucht;
  - nach Ablauf des 20-Sekunden-UI-Pending ging ein später Audio-Connect-Intent
    verloren;
  - INT-, TERM-, HUP-, Prozessgruppen-Timeout- und Byte-Drift-Schutz fehlten.
- Discovery-Eigentum wird nun erst gesetzt, wenn `adapter.discovering` nach
  einer Shibumi-Anforderung beobachtet wahr wird. Ein 1,5-Sekunden-
  Korrelationsfenster verhindert, dass ein viel späterer externer Scan
  fälschlich übernommen oder gestoppt wird.
- Der Service versucht Discovery im Abstand von einer Sekunde ausschließlich
  bei offener Shibumi-Session, vorhandenem und eingeschaltetem Adapter sowie
  fehlender Discovery erneut. Ablehnung beim Einschalten, externes Ende und
  Wechsel zwischen zwei aktiven Adaptern sind durch Fixtures abgedeckt.
- Der Audio-Handoff besitzt genau einen 60-Sekunden-`latest intent`. Ein neuer
  expliziter Connect ersetzt jeden älteren noch nicht ausgeführten Intent und
  dessen geplanten Handoff. Direkt vor der Übergabe werden Radio, aktueller
  Adapter, Live-Gerät, Verbindung und der aktuell aufgelöste PipeWire-Sink
  erneut geprüft; Disconnect, Forget, Radio-off und Adapterwechsel verwerfen
  den Intent.
- Der IPC-Harness begrenzt jeden `qs`-Aufruf, startet Quickshell mit `setsid`
  in einer eigenen Prozessgruppe und prüft deren PGID bis zum vollständigen
  Ende. Eine absichtlich TERM-resistente Kindprozess-Fixture belegt den
  KILL-Fallback. Echte INT-, TERM- und HUP-Abbrüche lesen den dynamisch
  erfassten Fixture-Snapshot nach einem bestätigten Event-Loop-Turn erneut und
  hinterlassen weder Prozessgruppe noch Testverzeichnis.
- Root- und Plugin-Kopien von `BluetoothBackendAdapter.qml` und
  `BluetoothModel.js` sind byte-identisch. Beide fokussierten und vollständigen
  Verträge enthalten jetzt einen Drift-Guard.
- Die fokussierte Bluetooth-Suite und der abschließend erneut ausgeführte
  vollständige Contract enden mit Exit-Code 0; der Voll-Lauf endet mit
  `Shibumi contract regression passed`.
- Der transaktionale Live-Repair um `23:57:58` installierte 24/24 Payloads.
  Vor dem abschließenden `Configuration Loaded` traten zwei bestehende
  Shibumi-DragGhost- und eine ausgeklammerte Omarchy-Notification-
  Abbauwarnung auf. Im stabilen Nachlauf folgte keine Bluetooth-Warnung und
  kein Fehler.
- Live gelten weiterhin: PID `1597226`, genau ein `omarchy.bluetooth`-Ziel,
  sechs Methoden, Radio an, Discovery aus und SteelSeries Arctis 7 Chat als
  Standard-Sink. Das iPhone ist aktuell gekoppelt, aber nicht verbunden. Die
  drei installierten Bluetooth-Dateien sind byte-identisch zum Arbeitsbaum.
- Health meldet einen erwarteten Source-Hinweis (`ahead 3 · dirty`), acht
  erfolgreiche Prüfungen und keine Runtime-Fehler. Die physische
  Multi-Monitor-Abnahme bleibt mangels zweitem Monitor ausgenommen.

Der interne Follow-up-Stand besitzt damit keine bekannte offene
Bluetooth-Invariante. Die vereinbarte unabhängige Prüfung des gesamten
Commit-Bereichs bleibt dennoch ein eigener Gate nach dem separaten
Folgecommit; ein Push erfolgt ausschließlich nach ausdrücklicher Freigabe.

### Zweites Folgeaudit nach Gesamt-Review vom 6. August 2026

Der Gesamt-Review bestätigte ein mittleres Audio-Lifecycle- und zwei niedrige
Harness-/Nachweis-Findings. Vor der Korrektur wurden alle drei gezielt rot
belegt:

- Intent A konnte trotz eines 59 Sekunden späteren Intent B fast 119 Sekunden
  gültig bleiben und den Standard-Sink übernehmen.
- Eine TERM-resistente Kindprozess-Fixture überlebte den nur an der Leader-PID
  orientierten Cleanup.
- Der Rollback besaß keinen getrennten Read nach einem Event-Loop-Turn.

Die neuen Regressionen beweisen jetzt:

- Intent B ersetzt Intent A; eine spätere Verbindung von A ändert den Sink
  nicht; nur B darf den Handoff auslösen; nach seinem eigenen Ablauf ist auch B
  ungültig.
- Cleanup beobachtet die vollständige PGID, eskaliert nach begrenztem TERM-
  Polling auf KILL und ruft `wait` nur auf, nachdem Exit- oder Zombie-Zustand
  bereits festgestellt wurde.
- Der Rollback liefert eine Generation und gilt erst nach einem getrennten,
  generationsgebundenen Read nach `Qt.callLater` als wiederhergestellt.

Im produktiven Log existiert nach `Configuration Loaded` eine transiente
`Resource Not Ready`-Discovery-Warnung von `00:03:48`. Health klassifiziert sie
nicht als Runtime-Fehler. Die Fixture beweist die Reconciliation nach einer
Ablehnung; die historische Warnung lässt sich rückwirkend aber keinem
bestimmten späteren Retry-Erfolg zuordnen.

Die kontrollierte Live-Abnahme um `00:29:40` trennt deshalb beide Nachweise
sauber:

- Die produktionsnahe Fixture lehnt den ersten Discovery-Start ab und bestätigt
  einen späteren Versuch sowie beobachtete aktive Discovery.
- Live wurde Discovery nach `omarchy.bluetooth open` beim ersten 250-ms-Poll
  aktiv beobachtet und nach `close` beim zweiten Poll wieder inaktiv.
- Im Abnahmefenster entstand keine neue Bluetooth-Warnung. Radio blieb an,
  kein Gerät war verbunden und SteelSeries Arctis 7 Chat blieb Standard-Sink.

Damit sind Ablehnung/Reconciliation deterministisch und der aktuelle reale
Start-/Stop-Pfad separat belegt, ohne einen BlueZ-Fehler künstlich durch einen
Radio- oder Geräte-Eingriff zu erzwingen.

Der Remote wurde unmittelbar vor dem separaten Folgecommit per
`git ls-remote` geprüft: `origin/main = 040da9b`; der geprüfte lokale
Ausgangsstand war `ahead 3 / behind 0`. Der separate Folgecommit erhöht den
lokalen Abstand auf `ahead 4 / behind 0`. Es wurde nichts gepusht.

### Unabhängiger Gesamt-Review nach dem Folgecommit

Der read-only Gesamt-Review von `origin/main..f1f8cbd` fand keine High- oder
Medium-Befunde, aber zwei niedrige Nachweislücken:

- Der erfolgreiche Doppel-Toggle las den wiederhergestellten Fixture-Zustand
  zwar nach einem kurzen Zwischenschritt, jedoch ohne explizit bestätigten
  QML-Event-Loop-Turn.
- `phase2-validation.md`, `phase2-ownership-map.md` und
  `plugin-suite-inventory.md` beschrieben noch das entfernte vollständige
  Omarchy-Bluetooth-Backend. Eine repositoryweite Suche zeigte dieselbe
  veraltete Eigentumsaussage zusätzlich in `v1-widget-parity-audit.md` sowie
  eine veraltete Timerzahl in `ARCHITECTURE.md`.

Die Korrektur verwendet für Erfolgs- und Abbruchpfad denselben
generationsgebundenen `Qt.callLater`-Nachweis. Ein Dokumentations-Guard lehnt
die alten Eigentums- und Timerbehauptungen künftig ab. Alle aktiven Dokumente
benennen nun den einen nativen Shibumi-Adapter, Quickshells BlueZ/PipeWire-
Modelle, die begrenzten Omarchy-Hilfsbefehle und den einzelnen symmetrischen
Sechs-Methoden-IPC-Eigentümer.

Der dafür erstellte separate Audit-Korrekturcommit erhöht den lokalen Stand
auf `ahead 5 / behind 0`. `origin/main` bleibt `040da9b`; es wurde nichts
gepusht.

Der zweite read-only Review fand anschließend noch eine niedrige semantische
Altlast in der Control-Center-Test-Fixture: Ihre Bluetooth-Beschreibung nannte
weiterhin Omarchy als BlueZ-/Audio-Eigentümer. Der vertiefte Root-Abgleich
zeigte außerdem, dass der Gesamtvertrag weiterhin die Existenz und interne API
des nicht mehr verwendeten offiziellen Bluetooth-Panels verlangte. Beides ist
entfernt: Die Fixture beschreibt den nativen Shibumi-Adapter, der Guard umfasst
nun auch ownership-tragende Fixtures und die Bluetooth-Suite lehnt eine neue
Kopplung an `plugins/panels/bluetooth/Panel.qml` ausdrücklich ab. Der
Audit-Korrekturcommit wurde vor jedem Push kohärent amendiert; der Abstand
bleibt `ahead 5 / behind 0`.

Der finale Metadaten-Review fand dieselbe Altarchitektur außerdem noch als
`hostContracts: ["omarchy.bluetooth"]` im aktiven Suite-Vertrag. Diese Kante
war nicht operational ausgewertet, deklarierte aber weiterhin fälschlich ein
fremdes Host-Backend. Der Bluetooth-Eintrag besitzt nun wie sein Manifest
keinen Host-Contract; die fokussierte Bluetooth-Suite erzwingt diese Invariante.
Der ungepushte Audit-Korrekturcommit wurde erneut kohärent amendiert und bleibt
der fünfte lokale Commit vor `origin/main`.

### Drittes Folgeaudit: Discovery-Abbau und vollständiger Abbruchnachweis

Der Endreview vom 6. August 2026 öffnete ein mittleres und zwei niedrige
Findings erneut. Alle drei Aussagen waren korrekt:

- Ein noch ausstehendes BlueZ-`StartDiscovery` konnte den Abbau des
  `BluetoothBackendAdapter` überleben. Quickshells native
  `BluetoothAdapter::setDiscovering(false)` ruft bei intern noch falschem
  Discovery-Zustand kein `StopDiscovery` auf; der spätere D-Bus-Abschluss
  benötigte deshalb weiterhin eine lebende Überwachung.
- Der Stubborn-Child-Test bewies die PGID-Terminierung, aber weder den
  wiederhergestellten Bluetooth-/Discovery-Snapshot noch die Entfernung des
  isolierten Case-Roots für genau diesen Abbruchpfad.
- `ARCHITECTURE.md` behauptete fälschlich, die Service-Fassade besitze keinen
  Timer, obwohl sie den begrenzten `discoveryRetry`-Timer enthält.

Die rote Regression zerstört nun ein Backend unmittelbar nach einer
Discovery-Anforderung und lässt den verzögerten Start erst danach abschließen.
Vor der Korrektur blieb der Adapter auf Discovery `true`. Der Fix legt einen
engineweiten, aber zeitlich auf 30 Sekunden begrenzten QML-Singleton-Guard an
die native Adapterinstanz. `qmldir` stellt sicher, dass alte und neue Backend-
Komponenten dieselbe Registry verwenden; die erste JS-Library-Zwischenlösung
garantierte dies über dynamische Loader-Grenzen nicht. Signalverbindung und
Retry-/Ablauf-Timer überleben die einzelne Service-Komponente. Ein abgelehnter
Stop wird mit begrenztem exponentiellem Backoff erneut versucht; erst ein über
einen späteren Event-Loop-Turn stabil beobachteter Stop oder die harte Deadline
löst den Guard auf.

Ein neuer legitimer Shibumi-Start entwaffnet den alten Guard vor jedem
`discovering`-Frühreturn. Hat der alte Shibumi-Request bereits abgeschlossen,
übernimmt der Ersatzservice dessen Ownership kontrolliert. Innerhalb des
`discoveringChanged`-Turns wird dazu direkt der native Adapterzustand gelesen,
weil die abgeleitete QML-Binding-Property noch den vorherigen Wert tragen kann.
Die Regression widersteht zwei Stop-Versuchen, hält zwei Pending-Completions
getrennt und trifft den Abschluss unmittelbar vor der Ersatzanforderung. Der
Ersatzservice übernimmt Discovery noch im selben Signal-Turn und gibt sie
danach wieder frei.

Ein adaptergeparenteter Lifecycle-Watcher schließt außerdem den Hot-Unplug-
Pfad: Entfernt BlueZ die native Adapterinstanz während eines wartenden Guards,
wird der Watcher mit ihr zerstört und entfernt Guard-Eintrag und Singleton-
Timer sofort. Jeder Retry prüft die Adapterreferenz zusätzlich vor Lesen und
Schreiben und fällt bei einem ungültigen QObject in denselben Cleanup. Die
Regression zerstört einen Fixture-Adapter bei laufendem Deadline-Timer und
verlangt anschließend eine leere Guard-Registry.

Root- und Plugin-Kopie des Adapters sowie des neuen
`BluetoothDiscoveryGuard.qml` sind byte-identisch und durch fokussierten sowie
vollständigen Drift-Test geschützt. Der Stubborn-Child-Fall verlangt nun
zusammenhängend den ursprünglichen Snapshot, denselben nach Event-Loop-
Settlement gelesenen Rollback-Zustand, verschwundene Leader-PID und PGID sowie
das entfernte Case-Root. Die Architektur beschreibt getrennt den einen
Service-Retry-Timer, die vier Adapter-Lifecycle-Timer und maximal einen
temporären 30-Sekunden-Teardown-Guard-Timer je nativer Adapterinstanz; ein
Dokumentations-Guard sperrt die alte und eine künftig erneut unvollständige
Behauptung.

Der neue dauerhafte Kandidatennachweis steht in
`docs/audits/evidence/bluetooth-final-2026-08-06.md`. Die fokussierte Suite und
der danach ausgeführte vollständige Contract enden beide mit Exit-Code 0; der
Voll-Lauf endet mit `Shibumi contract regression passed`. Qt-6-`qmllint` endet
mit Exit-Code 0 und den drei bekannten Quickshell-Typmetadaten-Hinweisen.
Physische Multi-Monitor-Abnahme und reale Geräte-/Radio-Mutationen bleiben wie
vereinbart ausgenommen. Es wurde nichts gepusht.

### Viertes Folgeaudit: Adapter-Hotplug und installierter Hostnachweis

Der nächste unabhängige Review bestätigte den Funktionsfix, öffnete aber zwei
niedrige Nachweislücken. Beide Aussagen waren korrekt:

- Der bisherige Lifecycle-Test zerstörte einen direkt bewaffneten Adapter,
  führte aber keinen ausstehenden Discovery-Start über die produktive
  Backend-/Service-Kette durch und bewies weder `onAdapterChanged` noch einen
  anschließenden Replug.
- Die im Auditprotokoll genannten dynamischen Befehle setzten
  `OMARCHY_PATH=/usr/share/omarchy` nicht ausdrücklich. Dadurch war aus dem
  Protokoll allein nicht beweisbar, dass der installierte Omarchy-Host statt
  eines privaten Checkouts verwendet und der bedingte Runtime-Block der
  Vollsuite tatsächlich ausgeführt wurde.

Eine eigene Hotplug-Regression hält genau eine Discovery-Session offen, startet
über den realen `BluetoothBackendAdapter` asynchron auf Adapterinstanz A und
zerstört A vor dem Abschluss. Der alte Abschluss wird verworfen; anschließend
wird eine neue Adapterinstanz B geladen. Ein dem produktiven Service-Prädikat
entsprechender begrenzter Test-Retry muss für B genau einen frischen Start
auslösen; der Backend-Adapter muss beobachtete Discovery übernehmen und sie
beim Session-Ende wieder freigeben. Der Test verlangt zusätzlich eine leere
Guard-Registry und keine ausstehende Completion. Die finale kontrollierte
Mutation entfernte exakt `retirePendingDiscovery()` aus `onAdapterChanged`.
Die ältere Backend-Regression blieb grün; der neue Test scheiterte gezielt mit
`onAdapterChanged did not retire pending Discovery`. Nach bytegenauer
Wiederherstellung des Produktionscodes ist der Test grün.

Das Beweisprotokoll nennt nun für Fokus- und Vollsuite exakt
`OMARCHY_PATH=/usr/share/omarchy`; ein Dokumentations-Guard erzwingt beide
Befehle dauerhaft. Die installierte Hostbindung meldet
`omarchy-dev 4.0.0.r1508.g12af188-1`. Beide explizit hostgebundenen Läufe enden
mit Exit-Code 0, der Fokuslauf enthält
`bluetooth adapter hotplug regression passed`, und der vollständige Lauf endet
mit `Shibumi contract regression passed`. Reale Bluetooth-, Radio- und
Audiozustände wurden nicht verändert; es wurde nichts gepusht.
