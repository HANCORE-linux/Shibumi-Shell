# Shibumi design

Shibumi adapts the approved QS Rise V1 and V2 behavior to Omarchy's native
plugin runtime. Omarchy owns the active theme hue; Shibumi owns form,
information hierarchy, component geometry, and interaction quality.

The binding visual and interaction specification is the
[V1 presentation contract](docs/v1-presentation-contract.md). Supporting
design references are:

- [Control Center contract](docs/control-center-v4.md)
- [G1-G18 ownership map](docs/phase2-ownership-map.md)
- [V1 widget parity audit](docs/v1-widget-parity-audit.md)
- [Style extension guide](styles/README.md)
- [Screenshot plan](docs/screenshots/README.md)

## Principles

- Use semantic Omarchy theme roles instead of persisted raw colors.
- Keep related controls visually and behaviorally consistent across panels.
- Preserve the invoking widget, bar edge, and output as the panel anchor.
- Use motion to communicate state and continuity, not as decoration.
- Keep unavailable and degraded states explicit without breaking core actions.
- Preserve keyboard, pointer, focus, dismissal, and lifecycle behavior as part
  of the design contract.
- Treat stable geometry, readable hierarchy, and predictable controls as
  release requirements rather than polish.

Before changing a visible surface, validate the source contract and the real
the validation system runtime state. A functional backend alone does not establish UI or UX
parity.
