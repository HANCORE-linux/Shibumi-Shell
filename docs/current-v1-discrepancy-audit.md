# Current V1 discrepancy audit

> **Document status: Current validation evidence.** This audit reports a dated
> comparison. It does not redefine the product contract in
> [`../ARCHITECTURE.md`](../ARCHITECTURE.md), and it does not modify the V1
> reference repository.

Date: 2026-07-30

## Audit basis

- Read-only reference: `<predecessor-checkout>`
- Reference branch: `main`
- Reference commit: `0ab6477d0533e6de2981a65d518b8efa0bb6f284`
- Reference description at inspection: `v2.8.0`
- Reference state: clean and equal to `origin/main` and `origin/HEAD`;
  `origin/feat/integrated-variants` remains at `e7a5d24`
- Shibumi target: the current source tree and the contract in
  [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
- Quattro host: package `4.0.0.r1458.gfa6b5fc-1` on the validation system

The previous inspection found mutable palette and MPRIS work. That work is now
published in commit `1d764328431c6307eb24628a0d6efd5b231c45d4`; the two later
commits affect only the separately selectable V2 workspace presentation. The
current head adds documentation, V2 preview media, and its demo link only. Its `versions/V1`
tree is byte-identical to commit `348b57ca35aaf0f49d5501dc0aa4ca1be3738ec4`
(tree `cb3a17ba5ee783805920b0e7dc49c5396358ede0`), against which the isolated
the validation system capture was made. The evidence therefore remains a reproducible
current-V1 comparison baseline. No file in the reference repository was
changed by this audit.

On 2026-07-28 the unchanged V1 tree was also launched directly on the validation system
with an isolated temporary `XDG_STATE_HOME`, captured, stopped, and replaced by
the Omarchy/Shibumi shell in the same session. This adds a current physical
same-output closed-bar reference at
`docs/mockups/shibumi-v1-reference.png`; the restored Shibumi state is captured
at `docs/mockups/shibumi-v1-current-same-session.png`. The temporary reference
run did not modify the user's persisted V1 or Shibumi configuration.

On 2026-07-30 the unchanged source inventories and complete Shibumi contract
were revalidated after the validation system moved to Quattro
`4.0.0.r1458.gfa6b5fc-1`. This host-only revalidation does not replace the
dated physical V1 captures.

## Findings

| Area | Current finding | Classification | Required action |
| --- | --- | --- | --- |
| G1 identity | V1 uses predecessor branding while Shibumi is an independent product. An initial pre-release identity marker could be persisted before its inherited `omarchy` wordmark was replaced. Identity schema 2 repairs that candidate state once. | Intentional product difference; defect fixed in the current candidate | the validation system shows the native `SHIBUMI` text mark. A later explicit Omarchy selection remains valid after identity schema 2 has been recorded. |
| Network SSID | Current Quattro no longer exposes the old generic Network panel `label`. Its current Wi-Fi model exposes the connected row and `connectedWifiNetwork.name`. Shibumi previously read only the old field. | Confirmed host-adapter regression; fixed in the current candidate | The adapter now prefers the connected model row, then the current connected object, and retains bounded compatibility fallbacks. the validation system shows `WLAN-493361` in both the bar and Network panel. |
| Radius 12/6 | V1 defines outer panel/pill radius as 12 or 6 and inner panel controls as two pixels less: 10 or 4. Shibumi tokens implement the same numbers. | Numeric and propagation parity accepted for the current candidate | the validation system large/small captures cover Control and Network panels. Static coverage requires every panel family to consume the shared `controlRadius`; circular meters, slider knobs, status dots, and icon geometry remain semantic. |
| Double-looking panel edges | The current panel owner renders exactly one `Ui.BorderSurface` and at most one radius-matched `RectangularShadow`. the validation system large/small captures did not reproduce a second panel background. With both effects enabled, the one-pixel border and the independent shadow contour remain intentionally visible. | Duplicate-surface defect not present in the current candidate | Retain structural one-surface regression coverage. A future report must identify the plugin, effect combination, and capture; do not silently remove the independently selectable V1 border or shadow. |
| Bar palette | Current V1 exposes colors 01-07 plus foreground, contrast-aware swatch text, and a four-column picker. Shibumi now maps the same seven active `colors.toml` swatches, derives V1 foreground-soft from Quattro's authoritative foreground/background roles, normalizes legacy IDs, and renders the same eight-choice shape. | Ported and accepted for the current slice | the validation system passes model, atomic theme-reload, state, Control Center, full contract, and real-session visual gates. Radius 12/6 with color02/color06 was captured; every swatch followed the live control radius and the exact original configuration hash was restored. |
| G9 Now playing | Current V1 adds a `compactMpris` setting whose enabled outcome is a 24-band real Cava waveform, vinyl mark, transport state, click play/pause, and wheel previous/next. Shibumi now exposes the same selectable outcome over the official media service. | Ported and accepted for the current single-output slice | One lazy process-wide spectrum service owns capability probing, Cava, retry state, leases, and cleanup. The bar and panel are presentation clients only; no per-output or per-view `Process` exists. Two real `mpv` sources pass next/previous/switch, playback transfer, pause, paused switching, and resume through Quattro's media owner. |
| Quattro notification extraction | Quattro commit `fc4caf3c` removed the notification bar widget and retained the notification center as a service. Shibumi's V1 presentation had depended on the old widget instance. | Confirmed host-contract drift; fixed in the current candidate | G3 resolves the official service directly, preserves Shibumi's bell/history presentation, exposes standard panel diagnostics, and passes the full contract plus a real the validation system open/close lifecycle. |
| Enterprise Wi-Fi | Current Quattro exposes a protected `connectEnterprise` path that sends the secret through standard input. Shibumi previously recognized enterprise security but opened `nmtui`. | Host capability gap closed; Shibumi adapter updated, credential gate open | The V1 panel now collects identity and password and delegates both to the official owner. No local enterprise `nmcli` command exists. Fixture coverage passes; a real enterprise connection still requires supplied credentials. |
| MPRIS panel Cava launch | Current V1 replaces temporary Cava configuration files with process substitution and records Cava as optional. Shibumi streams the equivalent bounded configuration over Cava stdin and creates no temporary configuration file. | Adapted to Quattro ownership and accepted | A product-only root `Timer` placement defect was found through real `shell summon`, fixed, and regression-protected. The actual Top and Bottom MediaPanel now load and render empty and two-source default/FULL states. the validation system covers worker-free empty, available, unavailable, two-client/one-worker, three-retry crash, and real cleanup states. |
| V2 workspace frame style | Commits `9a2a144` and `348b57c` affect the separately selectable V2 presentation, not the approved default V1 bar outcome. | Outside current default-bar parity | Consider the visual language only as input for a future separately named Shibumi bar. It does not silently change `hancore.shibumi.bar`. |
| Runtime acceptance | Shibumi Top/Bottom routing passes for the bar, Control Center, Display, AI, power-profile, Bluetooth, and populated G9 FULL/muse row and panel. A real current-V1/Shibumi run at 1920x1080, scale 1.0, Top, the same wallpaper, and color01 captured the closed bar plus Control, notification/status, memory, CPU, audio, center/calendar, idle MPRIS, network, battery, and brightness families. Later real runs captured G9 default Top, FULL/muse Top/Bottom, the actual empty and two-source Top/Bottom MediaPanel, native source switching, and all six G7/G14/G15 Top/Bottom default panel states before restoring the exact Shibumi configuration. Physical mixed-scale multi-monitor, hotplug-during-drag, hardware actions, and the remaining state matrix are open. | Partial current acceptance; no additional implementation difference is accepted merely from this partial run | Complete workspace, tray, quick-picker, account-backed G7, device-backed G15, remaining media-panel degraded states, remaining hover/active/error/degraded states, complete Bottom, and applicable subpage states. Keep hardware gates open in [`release-readiness.md`](release-readiness.md); fixtures and historical QS Rise evidence do not close them. |

## Decision boundary

The palette and G9 FULL/muse work is part of the clean current V1 baseline.
Both slices are now ported and accepted for the current single-output scope.
The next parity work must:

1. finish the remaining same-state presentation matrix;
2. continue adapting platform ownership to Quattro instead of copying V1
   processes or paths; and
3. pass the affected the validation system lifecycle, resource, failure, and physical-output
   gates.

Until those slices pass or `ARCHITECTURE.md` records an explicit product
exception, Shibumi cannot claim complete current-V1 presentation parity.
