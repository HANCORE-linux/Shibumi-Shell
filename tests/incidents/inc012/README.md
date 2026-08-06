# INC-012 revision-bound reproduction harness

This harness preserves the direct and asynchronous `GroupSection.qml`
lifecycle matrices used for INC-012. It is evidence tooling only: a negative
run does not close the incident, establish a root cause, or justify a null
guard.

The two immutable source contracts are:

- `beta3`: `c8d0b263c01aff3112f5204cc3bbe3097926e429`
- `current`: `47c85d155a8ffeaeedb7f675a650347e40b70659`

The runner verifies those commits and their exact `GroupSection.qml` digests,
extracts only `core/` and `styles/` with `git archive`, copies the selected
Omarchy `shell/Commons` tree into a private fixture, and starts the real
Quickshell binary with private `HOME` and `XDG_*` paths. It unsets the inherited
Wayland and Hyprland identifiers and uses Qt's offscreen platform. It does not
touch the installed Shibumi payload or any production registry entry.

From the repository root, regenerate the committed bounded report with:

```sh
python3 tests/incidents/inc012/reproduce.py \
  --revision beta3 \
  --revision current \
  --omarchy-path /usr/share/omarchy \
  --quickshell /usr/bin/quickshell \
  --report docs/audits/evidence/issues/inc012/reproduction-2026-08-06.json
```

Run one axis without writing a report with, for example:

```sh
python3 tests/incidents/inc012/reproduce.py --revision beta3
```

Each Quickshell process has a 40-second outer deadline and a 30-second QML
watchdog. The JSON retains at most 120 relevant lines per run, 600 characters
per line, and 20 historical-signature lines. Full transient logs are not
retained. Exit status is `0` when every matrix completes without the historical
signature, `1` for a harness failure, and `2` if the historical null-access
signature is observed.

The direct matrix covers target-session replacement/removal, model removal,
and 20 unload/load cycles in each of V1, V1 editing, V2, and V2 editing. The
asynchronous matrix repeats 20 owner-context destruction cycles for the same
four modes. A real full Omarchy host, physical outputs, and timing outside the
offscreen executor remain outside this harness and must not be inferred from a
negative result.
