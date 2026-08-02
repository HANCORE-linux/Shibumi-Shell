# Contributing to Shibumi

Shibumi is a suite of native Omarchy Quattro plugins written primarily in QML,
JavaScript, shell, and Python.

## Ground rules

- Keep one production Quickshell process. No plugin may start another shell.
- Keep every installed plugin self-contained. Do not depend on repository-root
  runtime imports or another plugin's private files.
- Reuse Quattro's authoritative services when they provide the required state
  and actions.
- Keep platform commands, validation, parsing, cancellation, and timeouts in
  services rather than views.
- Update canonical and vendored copies together; parity checks are part of the
  full contract.
- Preserve unrelated user changes in a dirty worktree.

## Development workflow

1. Branch from `main`.
2. Keep the change focused and match the surrounding two-space QML style.
3. Update the affected contract and regression test with the implementation.
4. Run the smallest affected regression locally.
5. Run the complete source contract before handoff:

   ```bash
   OMARCHY_PATH=/usr/share/omarchy ./tests/contract-regression.sh
   ```

6. For visible changes, describe the required real Wayland interaction.
   Maintainers repeat it on the isolated release-validation system and capture
   sanitized evidence.

Do not install a development suite over a primary desktop without an isolated
test profile and a recovery plan.

## QML and UI changes

Before changing a visible surface, read [DESIGN.md](DESIGN.md), the
[V1 presentation contract](docs/v1-presentation-contract.md), and the relevant
ownership contract.

Verify populated, empty, unavailable, error, disabled, hover, focus, open,
closed, Top, Bottom, and output-lifecycle states appropriate to the change.
Check keyboard behavior, outside dismissal, theme changes, shell reload, and
idle/screensaver transitions when relevant.

## Adding or changing a plugin

1. Keep the plugin under its full `hancore.shibumi.*` ID.
2. Update its `manifest.json`.
3. Update `contracts/plugin-suite-v1.json` for role, kinds, dependencies,
   services, layout, or defaults.
4. Update the [plugin catalog](docs/plugins/README.md).
5. Add focused source and runtime regressions.
6. Prove self-containment and the host-facade contract; maintainers repeat the
   live release gate on the isolated validation system.

## Documentation

Use sentence-case headings, direct language, descriptive links, and exact
commands. Put user guidance in the current reference documents and preserve
dated phase notes as historical evidence.

When adding screenshots, follow
[the screenshot plan](docs/screenshots/README.md) and remove private data.

## Commits

Use concise imperative subjects, for example:

- `Fix panel cleanup during screensaver pre-hide`
- `Document the Shibumi plugin lifecycle`
- `Add storage panel runtime regression`

The pull request or handoff should name the affected plugins, list the exact
checks, describe live UI evidence, and state any remaining physical gate.
