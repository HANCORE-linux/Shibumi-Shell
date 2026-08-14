pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui as Ui

Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})
  property color contentColor: "transparent"
  property bool customToneActive: false
  property color badgeContrastColor: "transparent"
  readonly property real badgeLayer: 10
  property bool updateAvailable: true
  property bool popupOpen: false
  property bool managePopupOpen: false
  property bool trayMenuOpen: false
  readonly property bool isUpdate: moduleName === "omarchy.system-update"
    || moduleName === "hancore.shibumi.update-center"
  readonly property bool isTray: moduleName === "omarchy.tray"
  readonly property bool isNotifications: moduleName === "omarchy.notifications"
  property int activationCount: 0
  property int pinToggleCount: 0
  property int menuOpenCount: 0
  property int dndToggleCount: 0
  property int markAllSeenCount: 0
  property int dismissPendingCount: 0
  property int clearPastCount: 0
  property var pinnedItems: isTray ? [{
    id: "fixture-pinned",
    icon: "",
    onlyMenu: false,
    activate: function() { root.activationCount++ },
    scroll: function(_delta, _horizontal) {}
  }] : []
  property var drawerItems: isTray ? [{
    id: "fixture-drawer",
    icon: "",
    onlyMenu: false,
    activate: function() { root.activationCount++ },
    scroll: function(_delta, _horizontal) {}
  }] : []
  property int drawerCount: drawerItems.length
  property int pendingCount: isNotifications ? 3 : 0
  property var notificationService: isNotifications ? ({
    doNotDisturb: false,
    setDoNotDisturb: function(value) {
      this.doNotDisturb = value === true
      root.dndToggleCount++
    },
    markAllSeen: function() { root.markAllSeenCount++ },
    dismissPending: function(_index) { root.dismissPendingCount++ },
    dismissPast: function(_index) {},
    clearPast: function() { root.clearPastCount++ }
  }) : null

  visible: !isUpdate || updateAvailable
  implicitWidth: isUpdate ? 21 : isTray ? 34 : 24
  implicitHeight: 35

  function open() {
    popupOpen = true
    if (bar) bar.requestPopout(root)
  }

  function close() {
    popupOpen = false
    managePopupOpen = false
    trayMenuOpen = false
    if (bar) bar.releasePopout(root)
  }

  function trayTooltip(item) {
    return item ? String(item.id || "") : ""
  }

  function togglePin(id) {
    pinToggleCount++
    if (bar && bar.shell
        && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, {
        id: moduleName,
        pinned: [String(id || "")],
        hidden: []
      })
  }

  function openTrayMenu(_item, _anchor, _mouse) {
    menuOpenCount++
    trayMenuOpen = true
    if (bar) bar.requestPopout(root)
  }

  function sanitizeBody(body, _app, _appIcon) {
    return String(body || "")
  }

  Ui.WidgetButton {
    anchors.fill: parent
    bar: root.bar
    text: root.isUpdate ? "update" : root.isTray ? "tray" : "notifications"
    onPressed: function(_button) {
      if (root.isNotifications) root.popupOpen ? root.close() : root.open()
      else if (root.isTray) root.managePopupOpen = !root.managePopupOpen
    }
  }
}
