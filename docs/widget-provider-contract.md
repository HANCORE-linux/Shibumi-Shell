# Widget provider contract

Shibumi treats widgets that provide the same exclusive desktop capability as
alternative providers, not as independent modules. This prevents duplicate
clocks, workspace controls, media controls, network controls, and similar
always-on bar functions.

Quattro's `barWidget.allowMultiple: false` remains authoritative for duplicate
instances of the same plugin ID. Cross-provider equivalence is declared with
one or more semantic capabilities:

```json
{
  "barWidget": {
    "allowMultiple": false,
    "semanticCapabilities": ["clock"]
  }
}
```

A Shibumi suite plugin declares the capabilities it owns and its preferred
region under `x-shibumi`:

```json
{
  "x-shibumi": {
    "suiteId": "hancore.shibumi",
    "role": "G8",
    "capabilities": ["clock", "weather"],
    "preferredRegion": "center"
  }
}
```

Third-party plugins may alternatively use `x-shibumi.capabilities`. Capability
names are lowercase, provider-neutral identifiers. A newly discovered plugin
sharing a capability with an installed Shibumi group is presented as a
replacement and is placed in that group's preferred region. Complementary
capabilities without a conflict remain independently installable.

Known Quattro plugin IDs are mapped to capabilities for backward compatibility
because their current manifests predate this extension.

Only manifests with a resolvable `entryPoints.barWidget` are accepted by the
bar host. Service-only plugins remain available to widgets through Quattro's
service registry but cannot be inserted as empty visual slots. In particular,
`omarchy.notifications` is a keep-loaded service consumed by Shibumi Status;
the installable Quattro presentation alternatives for that family are
`omarchy.indicators` and `omarchy.tray`.

Registry mutations may briefly make an otherwise valid entry point
unavailable. Every Shibumi `WidgetSlot` observes the host resolver revision and
performs a bounded retry. A later successful resolution publishes another
revision, so both current and future third-party widgets recover without
waiting for an unrelated configuration change.
