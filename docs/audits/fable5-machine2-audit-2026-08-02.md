# Fable 5 Audit — Shibumi Shell auf Machine2 (2026-08-02) — Abschlussbericht

> Beweisgestützte Qualitätsprüfung des veröffentlichten Stands `eb1ac69` auf Machine2. Durchgeführt allein, ohne Agenten/Verifier, ohne Code-, Git- oder Paketänderungen. **Ergebnis: 1 bestätigter Bug (BUG-1, Health-Fehlalarm), 5 nicht bestätigte Verdachtsfälle, Ausgangszustand byte-genau wiederhergestellt.**

## 1. Audit-Metadaten und bestätigter Ausgangsstand

- Datum: 2026-08-02, ca. 13:29–14:45 Uhr lokal. Auditor: Fable 5 (claude-fable-5), vollständig allein.
- Quellmaschine: `/home/hancore/Projects/shibumi`; `main` == `origin/main` == `eb1ac699e3bb800327727bfcbc453c829854ebf4` (per `git rev-parse` bestätigt); Arbeitsbaum sauber bis auf das erwartete untracked `docs/project-state-2026-08-02.md`.
- Machine2 per DHCP-Discovery verifiziert: `192.168.2.205`, Hostname `machine2`, User `drdeltree`, Interface `wlp59s0` meldet die Adresse selbst; eDP-1 1920×1080@60, Scale 1.0, aktive Hyprland-Sitzung (Signatur `5c9377c1…`). Evidenz: `01-preconditions.txt`.
- Host: `omarchy-dev 4.0.0.r1508.g12af188-1`, `omarchy-settings-dev 4.0.0.r1508.g12af188-1`, `hyprland 0.56.1-3`, `OMARCHY_PATH=/usr/share/omarchy` ✓.
- `omarchy-shell shell ping` → `ok`; keine failed System-/User-Services; `hyprctl configerrors` leer ✓.
- Exakt **25** `hancore.shibumi.*`-Manifeste unter `~/.config/omarchy/plugins/`. Third-party separat: `glafeara.wireguard` (enabled=false), `io.github.oldjobobo.thpm` (enabled=true) ✓.
- **Payload = veröffentlichter Stand**: Alle 326 veröffentlichten Plugin-Dateien byte-identisch mit `eb1ac69` (SHA-256-Vollvergleich, `02-payload-*.sha256`, `02-payload-diff.txt`). Laufzeitbestätigung: `shibumi-suite verifyPayload d932df70…` → `ok`; Gegenprobe mit Bogus-Digest → `not-ready`. Machine2-Workspace: 764/764 getrackte `eb1ac69`-Dateien byte-identisch (`sha256sum -c` rc=0; Workspace-HEAD `6576697` ist älter, Inhalt entspricht dennoch exakt `eb1ac69` — rsync-Deployment).
- **Dokumentierte Abweichung (nicht invalidierend)**: Streudatei `hancore.shibumi.bar/core/ThirdPartyPanelConnector.qml` (4219 B, mtime 2026-07-30 22:13) existiert installiert und im Workspace (`core/…`), aber in keinem Git-Commit. Kein Verweis in irgendeiner installierten Datei; der dynamische Loader lädt ausschließlich Manifest-Entry-Points, alle Manifeste byte-identisch → unerreichbar/inert. Provenienz: WireGuard-Panel-Session vom 30.07.
- Initialzustand: V2 Notch, Top, Launcher-Wordmark „OMARCHY", Accent FG; `shell.json` SHA-256 `5961657b…` (Backup `/tmp/fable5-audit/shell.json.initial` auf Machine2); Idle-Service enabled, stayAwake false.
- **Vorbefund am Ausgangszustand**: Die laufende Shell (PID 1106) war eine crash-relaunchte Instanz (Environ: `__QUICKSHELL_CRASH_SIGNAL=11`, Crash heute 10:46 Uhr, vor Auditbeginn) mit argumentloser cmdline. Details in Abschnitt 5.1; Auswirkung auf Health in Abschnitt 4.

## 2. Verwendete Quellen und Verträge

`docs/project-state-2026-08-02.md`; `docs/control-center-v4.md`; `ARCHITECTURE.md`; GitHub Issue #3 (read-only gelesen; Notch-Akzeptanzkriterien); Code des byte-identisch verifizierten Payloads: `hancore.shibumi.bar/Bar.qml` (IPC-Vertrag `shibumi-suite`), `hancore.shibumi.state/Service.qml` + `core/ShibumiConfig.js` (Zustandsmodell), `hancore.shibumi.control-center/manager/shibumi-health` und `shibumi-manager` (Health/Switch), `hancore.shibumi.control-center/{ControlSettings,ControlCenterPanel,PluginCatalogPage,PluginProviderSummary,WidgetAppearanceWorkbench}.qml` (Zähl- und Interaktionsgrammatik), `scripts/shibumi_suite/*` (Deploy-Mechanik), Host `/usr/share/omarchy/shell/shell.qml` (read-only, Loader-/IPC-Dispatch). Referenzbäume `Quickshell-Dots/versions/V1|V2` wurden nicht angefasst.

## 3. Testmatrix

| ID | Prüfpunkt | Ergebnis | Evidenz |
|---|---|---|---|
| A1 | Voller Contract-Test `tests/contract-regression.sh` (OMARCHY_PATH=/usr/share/omarchy) auf Machine2 | **PASS** (exit 0, „Shibumi contract regression passed") | `A1-contract-regression.log` |
| A2 | Split-CLI (9× `omarchy-plugin-*` vorhanden) + `shell rescanPlugins` | **PASS** (rescan ok, Ping ok, Log-Delta 1 Zeile fehlerfrei, weiterhin 25 Plugins, `shell.json` unverändert) | `01-preconditions.txt` |
| A3a | Host-Hot-Reload `shell reloadConfig` | **PASS** (Konfiguration + Bar-Geometrie vor/nach identisch, Log-Delta fehlerfrei) | `logs/R1-reload-logdelta.txt` |
| A3b | Shell-Neustart (`omarchy-restart-shell`) | **PASS** (genau 1 neuer Prozess, cmdline `quickshell -n -p /usr/share/omarchy/shell`, Ping ok, V2 Notch Top erhalten, `shell.json`-Hash unverändert; einzige Auffälligkeit im Startlog: benigne Portal-DBus-Meldung „Could not register app ID", Host-/Portal-Ebene) | `cycle/after-restart.png` |
| A3c | Suite-Synchronisierung | **NICHT AUSGEFÜHRT** (ein `shibumi-suite sync` hätte den Payload neu geschrieben; der Payload-Beweis erfolgte stattdessen zerstörungsfrei per SHA-Vollvergleich + `verifyPayload`-IPC) | `02-payload-*` |
| A4 | 25 Manifeste, Services, Entry-Points | **PASS** (Registry: 25 registriert, Bar aktiv; Suite-Services im Host-`plugins`-Array aktiv, IPC-Targets `hancore.shibumi.update-center`, `shibumi-media-spectrum`, `shibumi-picker`, `shibumi-suite`, `shibumi-suite-runtime`, `shibumi-reactor` vorhanden; Entry-Points über A1-Smokes und Live-Rendering aller 14 sichtbaren Gruppen) | `03-ipc-surface.txt`, `R1-baseline-v2-notch-top.png` |
| A5 | Runtime-Logs auf neue Fehler, Binding-Loops, wiederholte Reloads, verlorene Owner | **PASS** in allen 7 erfassten Test-Deltas (0 echte Fehler, 0 Binding-Loops, 0 Reload-Schleifen, 0 verlorene Owner). Einziger `error`-Grep-Treffer: Layoutname der wtype-Virtualtastatur in einem Hyprland-Event-String (Artefakt der Testeingabe). Crash-Historie vor Auditbeginn: Abschnitt 5.1 | `logs/R*-logdelta.txt` |
| B1 | Wechsel V1 → V2 → Omarchy → vorheriges Shibumi-Profil (Produktpfad `shibumi-manager request`) | **PASS** (v1: `style=shibumi`; v2: `notch`; omarchy: `bar=null` Stock-Bar; `request shibumi`: zurück zu V2 Notch = vorheriges Profil; jede Phase `complete` nach ≤3 s) | `cycle/*.png`, R7-Ausgabe |
| B2 | Unabhängige Profilpersistenz | **PASS mit Vorbehalt**: `order`, `v1SlotRoles`, `v2Layout`, `v2Boundaries`, `presentation` vor/nach dem Vierfach-Zyklus identisch. Einzige Differenz: `splits`-Booleans — nachweislich durch den eigenen `setAllSplits`-Roundtrip des Audits verursacht (Testresiduum, durch finale Byte-Wiederherstellung behoben) | `cycle/state-pre.json` / `state-post.json` |
| B3 | Top und Bottom | **PASS** (beide Positionen in der 16er-Matrix inkl. Persistenz `bar.position`; andere Styles nur Top getestet) | `notch-matrix/` |
| B4 | V1: Islands, Slots, Split/Merge | **TEILWEISE PASS**: Islands rendern korrekt (Pill-Inseln mit Border), `addV1Slot`/`removeV1Slot` und `setAllSplits` Roundtrips per IPC ok, Logs sauber. **NICHT GEPRÜFT**: Radius-12/6-Pixelmessung, Surface-Effekte, Edit-Drag (keine Pointer-Injektion), Restore-Flow, Gap/Reactor | `cycle/v1-bar.png`, `cycle/v1-splits-on.png` |
| B5 | V2 Full, Fit, Dock, Notch + Border/Panel/Tooltip/Divider/Spacing | **PASS** für die 4 Formen (setzen, rendern, persistieren, Logs sauber; Border-Linie in B6 pixelverifiziert; Panel-Anschluss in E). Divider/Tooltip nicht separat vermessen | `v2styles/crop-*.png` |
| B6 | V2-Notch-16er-Matrix (Top/Bottom × Text/Icon × Auto/None/Compact/Roomy), Kante pixelbasiert | **PASS** — Bottom 8/8: Differenzbild-Silhouette 0 Lücken, max. Spaltensprung 3 px, Schulter-Symmetrie 0.0, Schulterform über alle Spacings identisch (maxdiff 0). Top 8/8: Border-Linie über die gesamte innere Spannweite uniform (Luminanz min=mean=68, null Einbrüche ≥3 Spalten); Schulternaht bei 900 %-Zoom kontinuierlich verschmolzen. Gemessene „Dips" liegen ausschließlich unterhalb der Bar (Schattenzone, Zeilen 33–36) bzw. im designbedingten Fade an der Bildschirmkante. Spacing verändert die Quellradien nicht (Issue-#3-Kriterium erfüllt) | `notch-matrix/*` inkl. `analysis-output.txt`, `notch_analyze2.py`, `zoom-shoulder-contrast.png` |
| B7 | Neutrale Shibumi-Rückkehrschaltfläche unter Omarchy Bar | **PASS (statisch)**: flacher neutraler Glyph ganz links auf der Stock-Bar, keine Pill-Fläche, kein geerbter V1-/V2-Border. Hover-Animation **nicht geprüft** (keine Pointer-Injektion auf Machine2) | `cycle/zoom-return-icon.png`, `cycle/omarchy-bar.png` |
| B8 | Omarchy-Update-Schaltfläche öffnet direkt den Terminal-Updateflow (V1+V2) | **TEILWEISE/BLOCKED**: Verkabelung im byte-identischen Payload belegt (`SystemUpdateWidget.activate()` → `runUpdate()` → `omarchy-launch-floating-terminal-with-presentation omarchy-update`; Commit `4d1079e` entfernte den Panel-Umweg; `omarchy-update` ist durch `omarchy-update-confirm` gated). Runtime-Klick nicht ausführbar (keine Pointer-Injektion; wtype = nur Tastatur). Kompensation: `center-plugin-smoke` in A1 PASS. Kein Update ausgeführt | Code `eb1ac69`, `A1-contract-regression.log` |
| C1 | Routen Quick, Configure, Bars, Icons, Logo, Workspaces, Pickers, Plugins, Health | **PASS** (alle 9 öffnen per `openControlCenterPage` und rendern korrekt) | `cc/route-*.png` |
| C2 | Start-/Rückkehrroute, Route nach Owner-Neuaufbau, Escape, Reopen | **PASS** (Escape schließt: `connectedPanelState` inactive; Reopen ok; Radius-Wechsel bei offenem Bars-Panel: Owner-Rebuild mit Widget-Restore, Wert korrekt zurückgesetzt) | `cc/after-escape.png`, `cc/reopen.png`, `cc/after-owner-rebuild.png` |
| C3 | Tastaturfokus, Hover, Auswahl, Search | **TEILWEISE**: Tab/Pfeiltasten verändern den Fokuszustand (Screenshots differieren nachweislich); Streueingaben lösen keine ungewollten Aktionen aus. **NICHT GEPRÜFT**: Hover (Pointer), Suche (Hotkey ist CTRL K; der getestete „/“-Shortcut ist keiner — Suchinteraktion offen) | `cc/keyboard-*.png`, `cc/search-*.png` |
| C4 | Panelhöhe, Scrollbars, Clipping, Überlappung | **PASS** auf allen 9 gesichteten Routen (kompakt im Ruhezustand, keine Scrollbars, kein Clipping/Überlappen sichtbar) | `cc/route-*.png` |
| C5 | Semantische Configure-Vorschauen, stabiles Umschalten | **PASS (statisch)**: Configure landet auf der Landing-Route (nicht Bars vorselektiert), semantische Previews vorhanden (u. a. Mini-Notch in Quick/ACTIVE BAR, Bars-Formkacheln). Flicker-Freiheit beim Umschalten nicht per Videomessung geprüft | `cc/route-configure.png`, `cc/route-bars.png` |
| C6 | V1/V2-Isolation in Bars und Icons | **INDIREKT PASS** (Bars zeigt im V2-Zustand nur V2-Formen; V1-Einstellungen überlebten den Zyklus unverändert — B2). Icons-Seite nicht interaktiv geprüft | `cc/route-bars.png`, B2 |
| C7 | Logo: Wordmark/Icon unabhängig von Icons-Presentation | **NICHT GEPRÜFT** (Interaktionstest hätte Logo-Zustand mutiert; statisch: Logo-Route rendert, aktuelle Wordmark „OMARCHY“ ist legitime Wahl bei `identityVersion: 2`) | `cc/route-logo.png` |
| D1 | Provider-Zusammenfassung: 3 gestapelte Zeilen, semantische Farben | **PASS** (drei Zeilen „18 INSTALLED SHIBUMI / 20 COMPATIBLE OMARCHY / 1 THIRD-PARTY“ mit distinkten Icons/Farben; Kopf-Chip „24 S · 33 O · 2 EXT“ — Zählbasen geklärt, siehe Abschnitt 6) | `route-plugins.png` |
| D2/D3 | Add/Check-plugin-Layout, Updateprüfung read-only | **NICHT GEPRÜFT** (Dialog-Interaktion hätte Klickpfade erfordert; bewusst kein Installations-/Updateflow angestoßen) | — |
| D4 | Active/Inactive/Available, Filter, Suche, Dropdowns | **TEILWEISE** (statisch: „ACTIVE 14“ / „AVAILABLE 25“ Sektionen, Filterleiste All/Active/Shibumi/Omarchy Quattro/Third-party, Suchfeld vorhanden; Interaktion nicht getestet) | `route-plugins.png` |
| D5 | Health: PASS-Wording, Attention-Zähler, Copy, Open issue, Scrollverhalten | **TEILWEISE**: PASS-Wording ✓ (3 grüne RUNTIME-Checks), Attention-Zähler konsistent (Chip „HEALTH · 1“ = 1 Error; Karte listet 1 Error + 1 Warnung), collapsed ohne Scrollbar ✓. Copy-Feedback und „Open issue“-Breite nicht interaktiv geprüft. **Inhaltlich: BUG-1** (Abschnitt 4) | `route-health.png` |
| D6 | Open-issue-Dialog bis vor Absenden | **NICHT GEPRÜFT** (bewusst; kein Issue-Risiko eingegangen) | — |
| E1/E2 | Gehostete Widgets/Panels, Panelspitze, Bar-Anschluss, Escape, Rückkehr | **PASS (Stichprobe Audio, V2 Notch)**: `openWidgetPanel` → `connectedPanelState {active:true, screen:eDP-1, x:786, reveal:1}` (Panel-Caret an der Bar), Escape → inactive. Vollmatrix aller Gruppen nicht ausgeführt | `cycle/audio-panel-open.png` |
| E3 | Third-party im installierten Zustand | **TEILWEISE**: Registry-Zustand dokumentiert (thpm enabled/inactive; wireguard disabled), keine Installation/Entfernung/Update. UI-Detailprüfung der beiden Einträge nicht durchgeführt | `route-plugins.png` |
| E4 | Capability-Grenzen V1/V2/Omarchy | **PASS (belegte Teilmenge)**: `addV1Slot` unter V2 → `wrong-style` (Guard greift); Omarchy Bar ohne Shibumi-Konfiguration (nur neutraler Rückkehr-Glyph) | R7-Ausgabe, `cycle/omarchy-bar.png` |
| F1 | Wiederherstellung | **PASS**: `shell.json` byte-identisch (SHA `5961657b…` bestätigt, auch nach Shell-Neustart stabil); Idle-Service wieder `enabled=true, stayAwake=false`; keine failed Services; 0 Zombie-Kinder; `switch-status` semantisch wie initial (`complete`/`shibumi`). Details Abschnitt 8 | R8-Ausgabe |

## 4. Bestätigte Bugs

### BUG-1 — Health meldet fälschlich „Quickshell process: 0 production processes“ (ERROR), obwohl die Shell läuft

1. **ID/Titel**: BUG-1 — Fehlalarm der Health-Prozesserkennung nach Crash-Relaunch.
2. **Betroffen**: Control Center → Health (Attention-Karte + „HEALTH · 1“-Chip auf allen Control-Center-Seiten); profilunabhängig (V1/V2); Host `omarchy-dev 4.0.0.r1508`, Quickshell 0.3.0 (`quickshell-git`, rev `10b439fc`).
3. **Soll-Anforderung**: `shibumi-health`, `check_processes()` (Payload-Datei `hancore.shibumi.control-center/manager/shibumi-health`, Z. 400–407): erwartet genau einen Produktionsprozess und meldet dann „PID … owns /usr/share/omarchy/shell“ mit PASS. Akzeptierte Health-Semantik (Projektstand, `docs/health-diagnostics.md`): gesundes System zeigt `PASS`; das System ist gesund (Shell antwortet).
4. **Reproduzierbare Schritte ab dokumentiertem Ausgangszustand**: (a) Ausgangszustand dieses Audits: Shell nach Crash-Relaunch aktiv (cmdline `/usr/bin/quickshell` ohne Argumente — genau der Zustand, den jeder SIGSEGV-Autorelaunch erzeugt); `omarchy-shell shell ping` → `ok`. (b) Health öffnen (`openControlCenterPage health`) oder `shibumi-health` per CLI ausführen.
5. **Exakte Beobachtung**: `{"id":"quickshell-process","status":"error","value":"0 production processes","detail":"Expected exactly one Quickshell process for the Omarchy shell.","action":"Restart the shell only after inspecting duplicate processes."}` bei nachweislich laufender, antwortender Shell.
6. **Zwei Reproduktionen**: CLI-Lauf 1 und CLI-Lauf 2 identisch (dazwischen `ping` → `ok`); unabhängig davon dieselbe Fehlkarte in der UI (`route-health.png`: „Action needed — 1 error“).
7. **Beweise**: `route-health.png` (UI-ERROR); beide CLI-JSON-Ausgaben (R-Protokoll); `/proc/1106/cmdline` = `/usr/bin/quickshell` (argumentlos); Environ von PID 1106 mit `__QUICKSHELL_CRASH_SIGNAL=11` (Crash-Relaunch als Ursache der argumentlosen cmdline); `qs ipc -p /usr/share/omarchy/shell` erreicht dieselbe Instanz (Config-Bindung an den Omarchy-Shell-Pfad belegt).
8. **Gegenprobe**: Stale Payload ausgeschlossen (Health-Skript byte-identisch zu `eb1ac69`; Payload laufzeitverifiziert). Falsches Profil ausgeschlossen (Check profilunabhängig). Erwartete Capability-Grenze: keine dokumentiert. Absichtliches Design ausgeschlossen durch **positiven Kontrollversuch**: Nach sauberem Neustart (`omarchy-restart-shell` → cmdline `quickshell -n -p /usr/share/omarchy/shell`) meldet derselbe Check `{"status":"ok","value":"1 production process"}` — der Check will diese eine Shell erkennen und scheitert nur an der Erkennungsmethode. Konfigurationsfehler: keiner (identische Konfiguration in beiden Zuständen). Fehlende Abhängigkeit: `pgrep` vorhanden. Hostfehler: Der Host startet per `autostart.lua` mit `quickshell -n -p $OMARCHY_PATH/shell`; der argumentlose Zustand entsteht durch Quickshells eigenen Crash-Relaunch — ein auf diesem Host regulär vorkommender Zustand (15 Crash-Ordner seit 19.07.), den Shibumis Check nicht abdeckt.
9. **Soll vs. Ist**: Soll `PASS · 1 production process`; Ist `ERROR · 0 production processes` plus irreführender Handlungsvorschlag, solange die Shell aus einem Crash-Relaunch läuft. **Mechanismus**: `load_processes()` (Z. 289–303) erkennt „production“ ausschließlich am Substring `/usr/share/omarchy/shell` in `/proc/<pid>/cmdline`; nach re-exec ohne Argumente versagt das dauerhaft.
10. **Schweregrad/Nutzerwirkung**: **Mittel.** Nach jedem Shell-Crash zeigt Health dauerhaft einen roten Fehler und das Control Center permanente Attention; der echte Zustand (Shell läuft) wird falsch dargestellt und die vorgeschlagene Aktion führt in die Irre. Kein Funktionsverlust der Shell selbst. Keine Designpräferenz beteiligt.

## 5. Nicht bestätigte Verdachtsfälle / fehlende Evidenz

1. **Wiederkehrende Shell-Crashes, identische Signatur**: SIGSEGV in `QQuickLoader::setSourceUrlHelper → QQuickLoader::setSource` (aufgerufen aus QML via `QObjectMethod::callPrecise`): 02.08. 10:46 (`quajv4jt`), 01.08. 13:26 (`st88ba83jt`), 01.08. 13:31 (`rgy8m693jt`); dazu SIGABRT 30.07. (`rlvzbkwzit`); insgesamt 15 Crash-Ordner seit 19.07. (`~/.cache/quickshell/crashes/`). Der heutige Crash betraf die Instanz mit Config `/usr/share/omarchy/shell/shell.qml` (Report: `crash-quajv4jt-report.txt`). **Fehlende Evidenz für einen bestätigten (Shibumi-)Bug**: reproduzierbarer Auslöser ab dokumentiertem Ausgangszustand und Attribution des `Loader.setSource`-Aufrufs (Kandidaten: Host-`panelLoaders`/Rescan in `/usr/share/omarchy/shell/shell.qml`, Shibumi-Style-Loader, `HostWidgetResolver`). Während des gesamten Audits (Rescan, Reloads, 4 Style-Wechsel, 16er-Matrix, 9 Control-Center-Routen, 4 Profilwechsel, Shell-Neustart) trat kein Crash auf. Hinweis: `Bar.qml` (`reloadPayload`) dokumentiert bereits, dass Quattros Plugin-Rescan Loader aus gecachten Komponenten neu erzeugen kann — Zusammenhang unbewiesen.
2. **IPC `shibumi-suite setWidgetAppearance` für V2 wirkungslos**: schreibt Top-Level `widgets.Gx.<key>` (via `state.setGroupSetting`), während UI und V2-Renderer `appearance.v2.*` nutzen (`setGroupAppearanceSettingForVariant`). Empirisch: Top-Level-Änderung → keinerlei Geometrie-/Pixelwirkung; `appearance.v2`-Änderung → messbare Wirkung (Roomy verschiebt G1 x 302→296). Entwickler-/CLI-Oberfläche ohne gefundenen dokumentierten Vertrag → Beobachtung; für einen Bug fehlt die Soll-Quelle.
3. **Zombie-Kindprozesse** der crash-relaunchten Shell (inotifywait, 2× wl-paste, 4× bash, busctl, lsblk, 2× quickshell; Entstehung ~10:46–11:00 Uhr, konsistent mit dem Crash): stabil, kein Wachstum während des Audits; nach dem Shell-Neustart 0. Attribution (Quickshell-Reaping vs. Host vs. Shibumi) unbewiesen.
4. **Streudatei** `ThirdPartyPanelConnector.qml` (Abschnitt 1): inert; Bereinigung oder reguläres Einchecken empfohlen; kein Runtime-Effekt nachweisbar → kein Bug.
5. **C3-Suche und alle Hover-/Drag-Pfade**: nicht geprüft (Suche: falscher Shortcut getestet; Hover/Drag: keine Pointer-Injektion auf Machine2 — kein ydotool/wlrctl installiert, wtype ist tastaturbeschränkt). Keine Aussage möglich.

## 6. Geprüfte Nicht-Fehler / absichtliche Capability-Grenzen

- **Provider-Zahlen „24 S · 33 O · 2 EXT“ vs. „18/20/1“**: kohärente, unterschiedliche Zählbasen. Chip = Registry-Inventar (`suiteManaged`=24 — ohne die Bar selbst; `firstParty`=33 — Registry hat 34, minus die nicht hostbare `omarchy.bar`; extern=2 = thpm+wireguard). Zeilen = installierbarer Widget-Katalog (`providerCatalogCount`): 18 Shibumi-Widgets (19 bar-widget-fähige minus fest verbauter G1-Launcher), 20 Omarchy-Widgets, 1 Third-party (nur enabled thpm; disabled wireguard nicht im Katalog). Registrywerte gegengerechnet (`A4-listPlugins.json`): 34/2/19/20 — konsistent. Kein Zählfehler; Dokumentation der Basen empfohlen.
- **„OMARCHY“-Wordmark als V2-Launcher**: legitime Logo-Wahl bei `identityVersion: 2`; die Normalisierung erzwingt „shibumi“ nur für Alt-Konfigurationen.
- **`auto` == `none` bei G1 Inner Space**: pixelidentisch — konsistent mit „Auto = Default“; Issue-#3-Kriterium (konturstabile Kante) unabhängig davon erfüllt.
- **Health-Warnung „Development checkout — Current · dirty“**: sachlich korrekt (Machine2-Workspace ist gegenüber seinem HEAD schmutzig; rsync-Deployment-Modell).
- **`addV1Slot` unter V2 → `wrong-style`**: beabsichtigte Profilgrenze, Guard nachgewiesen.
- **Omarchy Bar ohne Shibumi-Konfigurationsflächen**: beabsichtigt; nur der neutrale Rückkehr-Glyph ist vorhanden (B7).
- **Screensaver-Unterbrechung während des Audits**: Shell-eigener Idle-Service (Screensaver 150 s / Lock 300 s) — korrektes Produktverhalten; für die Testdauer reversibel deaktiviert und wiederhergestellt.

## 7. Runtime-, Log- und Service-Ergebnisse

- 7 erfasste Log-Deltas über alle Testblöcke: 0 echte Fehler, 0 Binding-Loops, 0 wiederholte Reloads, 0 verlorene Owner (`logs/`). Der einzige `error`-Treffer war der Name der wtype-Virtualtastatur in einem Hyprland-Layout-Event.
- Neustart-Log der neuen Instanz: sauber bis auf die benigne Portal-DBus-Meldung („Could not register app ID“, Host-/Portal-Ebene, kein Shibumi-Bezug).
- Keine failed System-/User-Services zu Beginn und am Ende. `hyprctl configerrors` leer.
- Crash-Historie des Hosts: 15 Einträge seit 19.07., Details Abschnitt 5.1; der jüngste Crash lag vor Auditbeginn (10:46 vs. 13:29). Während des Audits: 0 Crashes, Shell-PID stabil bis zum bewussten Neustarttest.

## 8. Wiederherstellung des Ausgangszustands

- `~/.config/omarchy/shell.json`: aus dem Vorab-Backup byte-identisch wiederhergestellt; SHA-256 `5961657baee5a364d2b6630fd39a9f953b640bba00dc556919f8f6334410b746` bestätigt — auch nach dem Shell-Neustart unverändert. Damit sind sämtliche Zwischenmutationen (Styles, Position, Launcher-Mode, Paddings, Radius, Splits-Residuum, G4-Testrest) beseitigt.
- Idle-Service: wieder `enabled=true, stayAwake=false` (exakt der gesicherte Initialstatus; Stay-Awake-Indikator aus der Bar verschwunden).
- Shell: läuft als frisch gestartete Instanz (`quickshell -n -p /usr/share/omarchy/shell`, 1 Prozess, V2 Notch Top). **Bewusste Abweichung vom Vorfundzustand**: Der geforderte Neustarttest ersetzt die crash-relaunchte Instanz; der neue Zustand ist der sauberere (Health-Prozesscheck grün, 0 Zombies). Der Vorfundzustand ist in Abschnitt 1/4 dokumentiert.
- Keine Paket-, Plugin-, AUR-, Git- oder GitHub-Mutationen; V1-/V2-Referenzbäume unberührt; keine Third-party-Installation/-Update; kein `omarchy update`.
- Ephemere Reste: `/tmp/fable5-audit/` auf Machine2 (Testdaten/Screenshots; /tmp-Bereich, verschwindet mit Reboot). `~/.local/state/shibumi/switch-status.json` trägt einen neueren Zeitstempel bei semantisch identischem Inhalt (`complete`/`shibumi`) — reguläre Runtime-Statusdatei.

## 9. Priorisierte Handlungsempfehlungen (nicht implementiert)

1. **BUG-1 beheben**: Prozesserkennung in `shibumi-health` von der cmdline-Substring-Heuristik lösen (z. B. Instanzabgleich über `qs ipc -p $OMARCHY_PATH/shell ping`/Instanz-ID oder Auflösung des effektiven Config-Pfads des Prozesses), damit crash-relaunchte Shells korrekt als Produktion erkannt werden.
2. **Crash-Signatur `QQuickLoader::setSource` untersuchen**: kontrollierte Reproduktion (Verdachtspfade: Plugin-Rescan/Loader-Neuaufbau) anstreben, bevor Codeänderungen erwogen werden; die drei Reports vom 01./02.08. als Startpunkt.
3. **Offene Prüfpunkte nachziehen**, sobald Pointer-Injektion auf Machine2 verfügbar ist (z. B. `ydotool`): B4-Vollmatrix (Radius-Pixelmessung, Edit-Drag, Gap/Reactor), B7-Hover, B8-Klick, C3-Suche/Hover, D2–D6-Interaktionen, E-Vollmatrix, C7-Logo-Interaktion.
4. **Zählbasen der Provider-Anzeigen dokumentieren** (Chip vs. Katalogzeilen), um Verwechslung vorzubeugen.
5. **Streudatei bereinigen**: `ThirdPartyPanelConnector.qml` auf Machine2 entfernen oder regulär committen.
6. **IPC `setWidgetAppearance`** entweder auf den varianten-scoped Setter umstellen oder als Legacy kennzeichnen.

## 10. Artefaktindex

Basisverzeichnis: `docs/audits/evidence/fable5-2026-08-02/`. Vollständige SHA-256-Liste aller 69 Artefakte: **`SHA256SUMS.txt`** (selbst SHA-256: siehe unten). Zwecke nach Gruppe; Einzel-Hashes in `SHA256SUMS.txt`.

| Pfad | Zweck | SHA-256 |
|---|---|---|
| `SHA256SUMS.txt` | Vollständiger Hash-Index aller Beweisartefakte | `2d8fcd22b0a7f006096a3d847844182bd01e505997aabfd0f968540d2e803612` |
| `01-preconditions.txt` | Vorbedingungen Machine2 (Identität, Pakete, Services, Manifeste) | `4bea2950c6d6734b…360a63cd` |
| `02-payload-local-eb1ac69.sha256` / `02-payload-machine2.sha256` / `02-payload-diff.txt` | Payload-Beweis 326/326 byte-identisch + Streudatei | `12c03518…`, `c45f71ef…`, `7c6a7f50…` |
| `03-ipc-surface.txt` | IPC-Oberfläche des laufenden Shells | `45e20e6f…` |
| `A1-contract-regression.log` | Voller Contract-Test PASS (Machine2) | `cffa9fbb…` |
| `crash-quajv4jt-report.txt` | Crash-Report 02.08. 10:46 (SIGSEGV, Stacktrace `QQuickLoader::setSource`) | `1f727e2c…` |
| `R1-baseline-v2-notch-top.png` | Ausgangszustand V2 Notch Top | `6e0b3f21…` |
| `route-quick/plugins/health.png` (Wurzel) | Kopien der BUG-1-/D1-relevanten Routen | wie `cc/`-Pendants |
| `zoom-shoulder-contrast.png` | Notch-Schulternaht, 900 %, kontrastverstärkt | `da854a53…` |
| `cc/route-*.png` (9), `cc/after-*.png`, `cc/reopen.png`, `cc/keyboard-*.png`, `cc/search-*.png` | Control-Center-Routen, Escape/Reopen/Owner-Rebuild, Tastatur/Suche | siehe `SHA256SUMS.txt` |
| `notch-matrix/{top,bottom}-{text,icon}-{auto,none,compact,roomy}.png` (16) | 16er-Notch-Matrix Rohbilder | siehe `SHA256SUMS.txt` |
| `notch-matrix/ref-top-strip.png`, `ref-bottom-strip.png` | Bar-freie Wallpaper-Referenzen (Differenzbildverfahren) | `8f46b0ef…`, `a7dcb2c4…` |
| `notch-matrix/notch_analyze2.py`, `analysis-output.txt` | Analyse-Skript + vollständige Messwerte (reproduzierbar) | `09757dd5…`, `9d97f176…` |
| `v2styles/crop-{full,fit,dock,notch}.png` | V2-Formen Bar-Ausschnitte | siehe `SHA256SUMS.txt` |
| `cycle/v1-bar.png`, `v1-splits-on.png` | V1-Islands + Splits-Zustand | `8c08b04d…`, `d74408c3…` |
| `cycle/omarchy-bar.png`, `zoom-return-icon.png` | Omarchy-Stock-Bar + neutraler Rückkehr-Glyph (B7) | `85cbcabe…`, `bff4e51c…` |
| `cycle/v2-back.png`, `back-previous.png` | Rückkehr zu V2 / „previous“-Ziel | `eaea149a…`, `7567f8f3…` |
| `cycle/state-pre.json`, `state-post.json` | Persistenz-Snapshots vor/nach Profilzyklus | `112b7c13…`, `11cee59d…` |
| `cycle/audio-panel-open.png` | Gehostetes Audio-Panel mit Bar-Anschluss (E) | `b23ee4d3…` |
| `cycle/after-restart.png` | Zustand nach Shell-Neustart (A3b) | `087eac43…` |
| `logs/R{1,3,4,5,6,7}-*-logdelta.txt` | Log-Deltas aller Testblöcke (A5) | siehe `SHA256SUMS.txt` |

Rohdaten, die bewusst nur auf Machine2 verbleiben (ephemer, `/tmp/fable5-audit/`): Voll-Screenshots aller 16 Matrix-Regionen in Originalgröße, `A4-listPlugins.json`, `shell.json.initial`-Backup, Zwischenprotokolle.

---
*Audit beendet 2026-08-02 ≈14:45 Uhr. Kein Commit, kein Push, keine Codeänderung.*
