import QtQuick
import QtTest
import "../core/ShibumiConfig.js" as Config
import "../core/V2LayoutModel.js" as V2Layout

TestCase {
  name: "ShibumiConfig"

  function same(a, b) {
    return JSON.stringify(a) === JSON.stringify(b)
  }

  function test_configContract() {
    const defaults = Config.defaultConfig()
    if (defaults.version !== 1 || defaults.identityVersion !== 3)
      fail("unexpected schema or identity version")
    if (defaults.order.left.length !== 7 || defaults.order.center.length !== 1
        || defaults.order.right.length !== 7) fail("invalid default region sizes")
    if (!same(defaults.v1SlotRoles,
          Config.slotRolesForOrder(defaults.order))
        || defaults.v1SlotRoles.left.some(
          function(value) { return value !== "base" }))
      fail("invalid default V1 slot roles")
    if (defaults.v2Layout.left.length !== 10
        || defaults.v2Layout.center.length !== 1
        || defaults.v2Layout.right.length !== 13
        || defaults.v2Layout.right.indexOf("G16") < 0
        || defaults.v2Layout.right.indexOf("G17") < 0
        || defaults.v2Layout.right.indexOf("G18") < 0)
      fail("invalid V2 slot defaults")
    const movedToEmpty = V2Layout.moveGroupToSlot(
      defaults.v2Layout, "G4", "left", 3)
    if (!movedToEmpty || movedToEmpty.left[3] !== "G4"
        || movedToEmpty.left[6] !== "")
      fail("V2 empty slots are not valid drag targets")
    const extended = V2Layout.addSlot(defaults.v2Layout, "center")
    const trimmed = extended
      ? V2Layout.removeSlotAt(extended, "center", 1) : null
    if (!extended || extended.center.length !== 2
        || !trimmed || trimmed.center.length !== 1
        || V2Layout.removeSlotAt(defaults.v2Layout, "left", 3) !== null)
      fail("V2 extra slot add/remove contract")
    if (defaults.launcher.mode !== "text"
        || defaults.launcher.text !== "shibumi"
        || defaults.launcher.icon !== "omarchy")
      fail("invalid default launcher state")
    if (defaults.workspace.version !== 1 || defaults.workspace.mode !== "10"
        || defaults.workspace.style !== "default")
      fail("invalid default workspace state")
    if (defaults.picker.style !== "carousel"
        || defaults.picker.imageStyle !== "omarchy"
        || defaults.picker.mediaStyle !== "carousel")
      fail("invalid default picker state")
    if (defaults.reactor.mode !== 0)
      fail("reactor must default to zero-work mode 0")
    if (defaults.layoutProtection.v1 !== false
        || defaults.layoutProtection.v2 !== false)
      fail("layout protection must preserve live editing by default")
    if (!defaults.widgets.G7 || defaults.widgets.G7.enabled !== false
        || !defaults.widgets.G14 || defaults.widgets.G14.enabled !== false
        || !defaults.widgets.G15 || defaults.widgets.G15.enabled !== false
        || !defaults.widgets.G16 || defaults.widgets.G16.source !== "cpu"
        || defaults.widgets.G16.unit !== "metric")
      fail("widget defaults")
    if (!defaults.presentation.border || !defaults.presentation.v1Border
        || !defaults.presentation.v2Border || defaults.presentation.shadow
        || defaults.presentation.frost || defaults.presentation.radius !== "large"
        || defaults.presentation.height !== undefined
        || defaults.presentation.accent !== "color01"
        || defaults.presentation.shellStyle !== "shibumi"
        || defaults.presentation.v2ShellStyle !== "full")
      fail("invalid default presentation state")

    const absent = Config.normalize(null)
    if (!same(absent, defaults)) fail("missing state must use defaults")

    const paletteState = Config.normalize({
      version: 1,
      presentation: { accent: "color06" }
    })
    if (paletteState.presentation.accent !== "color06"
        || !Config.paletteIdValid("foreground")
        || Config.paletteIdValid("unsafe"))
      fail("canonical V1 palette state")

    const legacyPaletteState = Config.normalize({
      version: 1,
      presentation: { accent: "accent" }
    })
    const legacyGreenState = Config.normalize({
      version: 1,
      presentation: { accent: "color2" }
    })
    if (legacyPaletteState.presentation.accent !== "color01"
        || legacyGreenState.presentation.accent !== "color02")
      fail("legacy palette migration")

    const inheritedBrand = Config.normalize({
      version: 1,
      menu: {
        version: 1,
        launcher: { mode: "text", text: "omarchy", icon: "omarchy" }
      }
    })
    if (inheritedBrand.identityVersion !== 3
        || inheritedBrand.launcher.text !== "shibumi"
        || inheritedBrand.menu !== undefined)
      fail("pre-release inherited wordmark was not migrated")

    const explicitOmarchy = Config.normalize({
      version: 1,
      identityVersion: 2,
      menu: {
        version: 1,
        launcher: { mode: "text", text: "omarchy", icon: "omarchy" }
      }
    })
    if (explicitOmarchy.launcher.text !== "omarchy")
      fail("explicit post-migration wordmark choice was overwritten")

    const valid = Config.normalize({
      version: 1,
      order: {
        left: ["G7", "G2", "G3", "G4", "G5", "G6", "G1"],
        center: ["G8"],
        right: ["G9", "G10", "G11", "G14", "G12", "G13", "G15"]
      },
      splits: {
        left: [true, false, false, false, false, false],
        boundaries: [false, true],
        right: [false, false, false, false, false, true]
      },
      widgets: {
        G4: { compact: true, nested: { value: 2 } },
        G7: { "hancore.shibumi.ai": { aiTool: "opencode" } },
        G14: { enabled: true },
        BAD: { compact: true }
      },
      presentation: {
        border: false,
        shadow: true,
        frost: true,
        radius: "small",
        shellStyle: "notch",
        height: "minimal"
      },
      workspace: {
        version: 1,
        mode: "active",
        style: "magic"
      },
      launcher: { mode: "icon", text: "arch", icon: "rebel" },
      picker: {
        style: "tanzaku",
        imageStyle: "omarchy",
        mediaStyle: "hearthstone"
      },
      reactor: { mode: 7 },
      layoutProtection: { v1: true, v2: false }
    })
    if (valid.order.left[0] !== "G7" || valid.order.left[6] !== "G1")
      fail("valid order was not retained")
    if (!valid.splits.left[0] || !valid.splits.boundaries[1] || !valid.splits.right[5])
      fail("valid split state was not retained")
    if (!same(valid.v1SlotRoles, Config.slotRolesForOrder(valid.order)))
      fail("legacy fixed V1 order did not gain explicit slot roles")

    const extendedOrder = Config.defaultOrder()
    extendedOrder.left.push("")
    extendedOrder.right.push("")
    const extendedSplits = Config.defaultSplits(extendedOrder)
    extendedSplits.left[6] = true
    const extendedState = Config.normalize({
      version: 1,
      order: extendedOrder,
      v1SlotRoles: Config.slotRolesForOrder(extendedOrder),
      splits: extendedSplits
    })
    if (extendedState.order.left.length !== 8
        || extendedState.order.right.length !== 8
        || extendedState.v1SlotRoles.left[7] !== "extra"
        || extendedState.v1SlotRoles.right[7] !== "extra"
        || extendedState.splits.left.length !== 7
        || extendedState.splits.left[6] !== true)
      fail("extended V1 slot state was not retained")

    const dynamicOrder = Config.defaultOrder()
    dynamicOrder.left.push("G:custom.widget")
    const dynamicState = Config.normalize({
      version: 1,
      order: dynamicOrder,
      v1SlotRoles: Config.slotRolesForOrder(dynamicOrder),
      splits: Config.defaultSplits(dynamicOrder),
      widgets: { "G:custom.widget": { compact: true } }
    })
    if (!Config.isGroupId("G:custom.widget")
        || Config.isGroupId("G:Custom Widget")
        || dynamicState.order.left[7] !== "G:custom.widget"
        || dynamicState.widgets["G:custom.widget"].compact !== true)
      fail("dynamic V1 group state was not retained")

    const partialExtendedState = Config.normalize({
      version: 1,
      order: extendedOrder,
      v1SlotRoles: Config.slotRolesForOrder(extendedOrder),
      splits: Config.defaultSplits()
    })
    if (!same(partialExtendedState.order, defaults.order)
        || !same(partialExtendedState.v1SlotRoles, defaults.v1SlotRoles)
        || !same(partialExtendedState.splits, defaults.splits))
      fail("partial V1 slot transaction must fail closed")

    const invalidRoles = Config.slotRolesForOrder(extendedOrder)
    invalidRoles.left[7] = "base"
    const invalidRoleState = Config.normalize({
      version: 1,
      order: extendedOrder,
      v1SlotRoles: invalidRoles,
      splits: extendedSplits
    })
    if (!same(invalidRoleState.order, defaults.order)
        || !same(invalidRoleState.v1SlotRoles, defaults.v1SlotRoles))
      fail("invalid V1 slot roles must reject the complete layout")
    if (!valid.widgets.G4 || valid.widgets.G4.compact !== true || valid.widgets.BAD
        || valid.widgets.G7.enabled !== false
        || valid.widgets.G7["hancore.shibumi.ai"].aiTool !== "opencode"
        || valid.widgets.G14.enabled !== true
        || valid.widgets.G15.enabled !== false
        || valid.widgets.G16.source !== "cpu"
        || valid.widgets.G16.unit !== "metric")
      fail("widget settings were not sanitized")
    const temperatureState = Config.normalize({
      version: 1,
      widgets: { G16: { source: "gpu", unit: "imperial" } }
    })
    const unsafeTemperatureState = Config.normalize({
      version: 1,
      widgets: { G16: { source: "unsafe", unit: "kelvin" } }
    })
    if (temperatureState.widgets.G16.source !== "gpu"
        || temperatureState.widgets.G16.unit !== "imperial"
        || unsafeTemperatureState.widgets.G16.source !== "cpu"
        || unsafeTemperatureState.widgets.G16.unit !== "metric")
      fail("temperature settings were not normalized")
    if (valid.presentation.border || valid.presentation.v1Border
        || valid.presentation.v2Border || !valid.presentation.shadow
        || !valid.presentation.frost || valid.presentation.radius !== "small"
        || valid.presentation.shellStyle !== "notch"
        || valid.presentation.v2ShellStyle !== "notch"
        || valid.presentation.height !== undefined)
      fail("presentation settings were not normalized")
    const separatedBorders = Config.normalize({
      version: 1,
      presentation: { border: true, v1Border: false, v2Border: true }
    })
    if (separatedBorders.presentation.v1Border !== false
        || separatedBorders.presentation.v2Border !== true)
      fail("V1/V2 border profiles were not retained independently")
    if (valid.workspace.mode !== "active" || valid.workspace.style !== "magic")
      fail("workspace settings were not normalized")
    const v2WorkspaceStyles = ["kanji", "rings", "aurora", "pacman"]
    for (let workspaceStyle of v2WorkspaceStyles) {
      const workspaceState = Config.normalize({
        version: 1,
        workspace: { version: 1, mode: "active", style: workspaceStyle }
      })
      if (workspaceState.workspace.style !== workspaceStyle)
        fail("V2 workspace style was not retained: " + workspaceStyle)
    }
    const legacyFrame = Config.normalize({
      version: 1,
      workspace: { version: 1, mode: "active", style: "frame" }
    })
    const legacyAurora = Config.normalize({
      version: 1,
      workspace: { version: 1, mode: "active", style: "aurora-streak" }
    })
    if (legacyFrame.workspace.style !== "rings"
        || legacyAurora.workspace.style !== "aurora")
      fail("pre-alpha workspace style aliases were not migrated")
    if (valid.launcher.mode !== "icon" || valid.launcher.text !== "arch"
        || valid.launcher.icon !== "rebel")
      fail("launcher presentation was not normalized")
    const shibumiIcon = Config.normalize({
      version: 1,
      launcher: { mode: "icon", text: "shibumi", icon: "shibumi" }
    })
    if (shibumiIcon.launcher.icon !== "shibumi")
      fail("Shibumi launcher icon was not normalized")
    if (valid.picker.style !== "hearthstone"
        || valid.picker.imageStyle !== "omarchy"
        || valid.picker.mediaStyle !== "hearthstone")
      fail("picker presentation was not normalized")
    if (valid.reactor.mode !== 7)
      fail("reactor mode was not normalized")
    if (valid.layoutProtection.v1 !== true
        || valid.layoutProtection.v2 !== false)
      fail("V1/V2 layout protection was not retained independently")
    const unsafeProtection = Config.normalize({
      version: 1,
      layoutProtection: { v1: "true", v2: 1 }
    })
    if (unsafeProtection.layoutProtection.v1 !== false
        || unsafeProtection.layoutProtection.v2 !== false)
      fail("non-boolean layout protection did not fail closed")

    const carousel = Config.normalize({
      version: 1,
      picker: { style: "carousel" }
    })
    if (carousel.picker.style !== "carousel"
        || carousel.picker.imageStyle !== "omarchy"
        || carousel.picker.mediaStyle !== "carousel")
      fail("legacy carousel state was not split by media type")

    const defaultPicker = Config.normalize({
      version: 1,
      picker: { style: "default" }
    })
    if (!same(defaultPicker.picker, defaults.picker))
      fail("legacy default picker state did not select media carousel")

    const defaultMedia = Config.normalize({
      version: 1,
      picker: { imageStyle: "tanzaku", mediaStyle: "default" }
    })
    if (defaultMedia.picker.style !== "carousel"
        || defaultMedia.picker.imageStyle !== "tanzaku"
        || defaultMedia.picker.mediaStyle !== "carousel")
      fail("explicit media default did not select carousel")

    const legacyPicker = Config.normalize({
      version: 1,
      picker: { style: "hearthstone" }
    })
    if (legacyPicker.picker.style !== "hearthstone"
        || legacyPicker.picker.imageStyle !== "hearthstone"
        || legacyPicker.picker.mediaStyle !== "hearthstone")
      fail("legacy picker state was not migrated")

    const duplicate = Config.normalize({
      version: 1,
      order: {
        left: ["G1", "G1", "G3", "G4", "G5", "G6", "G7"],
        center: ["G8"],
        right: ["G9", "G10", "G11", "G14", "G12", "G13", "G15"]
      }
    })
    if (!same(duplicate.order, defaults.order)) fail("duplicate order must fail closed")

    const wrongSchema = Config.normalize({
      version: 2,
      order: valid.order,
      widgets: { G4: { compact: true } }
    })
    if (!same(wrongSchema, defaults)) fail("unknown schema must fail closed")

    const malformedLauncher = Config.normalize({
      version: 1,
      launcher: { mode: "animated", text: "unknown", icon: "unsafe" }
    })
    if (!same(malformedLauncher.launcher, defaults.launcher))
      fail("malformed launcher must fail closed")

    const malformedWorkspace = Config.normalize({
      version: 1,
      workspace: { version: 99, mode: "all", style: "unsafe" }
    })
    if (!same(malformedWorkspace.workspace, defaults.workspace))
      fail("unknown workspace schema must fail closed")

    const malformedPicker = Config.normalize({
      version: 1,
      picker: { style: "vertical" }
    })
    if (!same(malformedPicker.picker, defaults.picker))
      fail("malformed picker style must fail closed")

    const malformedReactor = Config.normalize({
      version: Config.SchemaVersion,
      reactor: { mode: 9 }
    })
    if (!same(malformedReactor.reactor, defaults.reactor))
      fail("malformed reactor mode must fail closed")

    const malformedPresentation = Config.normalize({
      version: 1,
      presentation: {
        border: "yes",
        shadow: 1,
        radius: "roundest",
        height: "tiny",
        accent: "unsafe"
      }
    })
    if (!same(malformedPresentation.presentation, defaults.presentation))
      fail("malformed presentation must fail closed")

    const oversizedCollection = []
    for (let i = 0; i <= Config.MaxWidgetCollectionItems; i++)
      oversizedCollection.push(i)
    const boundedWidgets = Config.normalize({
      version: Config.SchemaVersion,
      widgets: {
        G4: {
          compact: true,
          oversized: oversizedCollection,
          longText: "x".repeat(Config.MaxWidgetStringLength + 1),
          finite: 7,
          invalidNumber: Number.POSITIVE_INFINITY
        },
        G5: { constructor: { polluted: true } }
      }
    })
    if (!boundedWidgets.widgets.G4 || boundedWidgets.widgets.G4.compact !== true
        || boundedWidgets.widgets.G4.oversized !== undefined
        || boundedWidgets.widgets.G4.longText !== undefined
        || boundedWidgets.widgets.G4.finite !== 7
        || boundedWidgets.widgets.G4.invalidNumber !== undefined)
      fail("widget setting resource bounds")
    if (boundedWidgets.widgets.G5 !== undefined)
      fail("unsafe widget object key must fail closed")

  }
}
