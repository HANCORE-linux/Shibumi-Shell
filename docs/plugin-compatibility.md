# Use Shibumi plugins with other bars

Status: user reference

You can use some Shibumi plugins without the default Shibumi bar. The App Menu follows Omarchy's shell-level menu contract, while visible bar widgets require the [Shibumi host facade V1](host-facade-v1.md).

## Compatibility by plugin type

The plugin kind and runtime contract determine whether a component can work with another bar:

| Plugin type | Stock Omarchy bar | Another Shibumi-compatible bar | Arbitrary third-party bar |
| --- | --- | --- | --- |
| Shibumi App Menu | Supported | Supported | Supported inside Omarchy Shell |
| Shibumi bar widgets and panels | Not supported | Supported after host-facade validation | Not supported by default |
| Shibumi service-only plugins | Internal dependencies | Internal dependencies | No supported standalone use |
| Shibumi full-bar plugin | Replaces the active bar | Alternative host | Alternative host |

An installed `bar-widget` manifest only makes the widget discoverable. It doesn't prove that the active bar implements the properties and methods used by that widget.

## Use the App Menu with another bar

`hancore.shibumi.menu` is independent from `hancore.shibumi.bar`. It uses Omarchy's menu lifecycle and falls back to standard Omarchy colors when the active bar has no Shibumi visual tokens.

The App Menu still requires `hancore.shibumi.state`. Install and maintain it through the complete Shibumi suite so dependency validation, updates, repair, and removal remain transactional.

## Use Shibumi widgets with another compatible bar

The 19 visible Shibumi feature plugins depend on host facade version 1. A compatible bar must implement the complete property and method contract for:

- visual tokens and bar geometry
- tooltip and panel routing
- output ownership
- click-target registration
- widget resolution and summon actions
- layout and Control Center mutations

A custom bar isn't supported because its QML can render one widget. It must pass the [host-facade acceptance gates](host-facade-v1.md#acceptance) and the [additional bar validation](multi-bar-extension-plan.md#required-gates-for-every-bar) on Machine2.

## Avoid unsupported combinations

Don't add Shibumi widgets directly to the stock Omarchy bar or an unvalidated third-party bar. Missing facade members can cause broken colors, panels on the wrong output, failed popouts, or QML runtime errors.

Don't disable, remove, or update individual Shibumi roots through the generic plugin menu. Use the [suite lifecycle](install.md) to keep all 25 plugin roots and their dependencies consistent.

## Build another compatible bar

A third-party bar author can support Shibumi widgets by implementing host facade version 1 without copying Shibumi's feature services. Start with the [host facade contract](host-facade-v1.md), then follow the [additional bar contract](multi-bar-extension-plan.md).

Compatibility becomes release-supported only after the complete Machine2 gates pass. Until then, treat the new bar as an external integration.
