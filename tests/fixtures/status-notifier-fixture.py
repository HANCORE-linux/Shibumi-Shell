#!/usr/bin/env python3
"""Deterministic StatusNotifierItem and DBusMenu fixture for Wayland tests."""

import argparse
import signal
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


SNI_IFACE = "org.kde.StatusNotifierItem"
WATCHER_IFACE = "org.kde.StatusNotifierWatcher"
WATCHER_NAME = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"
MENU_IFACE = "com.canonical.dbusmenu"
PROPERTIES_IFACE = "org.freedesktop.DBus.Properties"


def variant_dictionary(values):
    return dbus.Dictionary(values, signature="sv")


class FixtureMenu(dbus.service.Object):
    """Small menu covering actions, check state, disabled rows and submenus."""

    def __init__(self, bus, event_callback):
        super().__init__(bus, "/Menu")
        self.revision = 1
        self.event_callback = event_callback
        self.nodes = {
            0: {
                "children": [1, 2, 3, 4, 5],
                "props": {"children-display": dbus.String("submenu")},
            },
            1: {
                "children": [],
                "props": {
                    "label": dbus.String("_Open Fixture"),
                    "enabled": dbus.Boolean(True),
                    "visible": dbus.Boolean(True),
                    "icon-name": dbus.String("document-open-symbolic"),
                },
            },
            2: {
                "children": [],
                "props": {
                    "label": dbus.String("_Checked option"),
                    "enabled": dbus.Boolean(True),
                    "visible": dbus.Boolean(True),
                    "toggle-type": dbus.String("checkmark"),
                    "toggle-state": dbus.Int32(1),
                },
            },
            3: {
                "children": [],
                "props": {
                    "type": dbus.String("separator"),
                    "visible": dbus.Boolean(True),
                },
            },
            4: {
                "children": [],
                "props": {
                    "label": dbus.String("_Disabled action"),
                    "enabled": dbus.Boolean(False),
                    "visible": dbus.Boolean(True),
                },
            },
            5: {
                "children": [6],
                "props": {
                    "label": dbus.String("_More"),
                    "enabled": dbus.Boolean(True),
                    "visible": dbus.Boolean(True),
                    "children-display": dbus.String("submenu"),
                },
            },
            6: {
                "children": [],
                "props": {
                    "label": dbus.String("_Nested action"),
                    "enabled": dbus.Boolean(True),
                    "visible": dbus.Boolean(True),
                },
            },
        }

    def filtered_properties(self, item_id, requested):
        source = self.nodes.get(int(item_id), {}).get("props", {})
        names = {str(value) for value in requested}
        if not names:
            return variant_dictionary(source)
        return variant_dictionary({
            key: value for key, value in source.items() if key in names
        })

    def layout_node(self, item_id, depth, requested, variant_level=0):
        node = self.nodes.get(int(item_id), {"children": [], "props": {}})
        children = []
        if depth != 0:
            next_depth = depth - 1 if depth > 0 else depth
            for child_id in node["children"]:
                children.append(self.layout_node(
                    child_id, next_depth, requested, variant_level=1
                ))
        return dbus.Struct(
            (
                dbus.Int32(item_id),
                self.filtered_properties(item_id, requested),
                dbus.Array(children, signature="v"),
            ),
            signature="ia{sv}av",
            variant_level=variant_level,
        )

    @dbus.service.method(
        MENU_IFACE, in_signature="iias", out_signature="u(ia{sv}av)"
    )
    def GetLayout(self, parent_id, recursion_depth, property_names):
        return (
            dbus.UInt32(self.revision),
            self.layout_node(parent_id, recursion_depth, property_names),
        )

    @dbus.service.method(
        MENU_IFACE, in_signature="aias", out_signature="a(ia{sv})"
    )
    def GetGroupProperties(self, item_ids, property_names):
        return dbus.Array(
            [
                dbus.Struct(
                    (
                        dbus.Int32(item_id),
                        self.filtered_properties(item_id, property_names),
                    ),
                    signature="ia{sv}",
                )
                for item_id in item_ids
                if int(item_id) in self.nodes
            ],
            signature="(ia{sv})",
        )

    @dbus.service.method(MENU_IFACE, in_signature="isvu", out_signature="")
    def Event(self, item_id, event_id, data, timestamp):
        del data, timestamp
        if str(event_id) == "clicked" and int(item_id) in (1, 2, 6):
            self.event_callback("menu", int(item_id))

    @dbus.service.method(MENU_IFACE, in_signature="i", out_signature="b")
    def AboutToShow(self, item_id):
        del item_id
        # The fixture menu is static. True would promise a subsequent
        # LayoutUpdated signal and make compliant clients wait for it.
        return dbus.Boolean(False)

    @dbus.service.method(MENU_IFACE, in_signature="ai", out_signature="aiai")
    def AboutToShowGroup(self, item_ids):
        invalid = [dbus.Int32(value) for value in item_ids if int(value) not in self.nodes]
        return dbus.Array([], signature="i"), dbus.Array(invalid, signature="i")

    @dbus.service.method(
        PROPERTIES_IFACE, in_signature="ss", out_signature="v"
    )
    def Get(self, interface_name, property_name):
        if str(interface_name) != MENU_IFACE:
            raise dbus.exceptions.DBusException(
                "org.freedesktop.DBus.Error.InvalidArgs"
            )
        values = self.menu_properties()
        if str(property_name) not in values:
            raise dbus.exceptions.DBusException(
                "org.freedesktop.DBus.Error.InvalidArgs"
            )
        return values[str(property_name)]

    @dbus.service.method(
        PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}"
    )
    def GetAll(self, interface_name):
        if str(interface_name) != MENU_IFACE:
            return variant_dictionary({})
        return variant_dictionary(self.menu_properties())

    @staticmethod
    def menu_properties():
        return {
            "Version": dbus.UInt32(4),
            "TextDirection": dbus.String("ltr"),
            "Status": dbus.String("normal"),
            "IconThemePath": dbus.Array([], signature="s"),
        }

    @dbus.service.signal(MENU_IFACE, signature="ui")
    def LayoutUpdated(self, revision, parent):
        del revision, parent

    @dbus.service.signal(MENU_IFACE, signature="ia{sv}")
    def ItemActivationRequested(self, item_id, timestamp):
        del item_id, timestamp


class FixtureItem(dbus.service.Object):
    """StatusNotifier item registered with Quickshell's authoritative watcher."""

    def __init__(self, bus, fixture_id, title, status):
        super().__init__(bus, "/StatusNotifierItem")
        self.fixture_id = fixture_id
        self.title = title
        self.status = status
        self.activation_count = 0
        self.menu_event_count = 0

    def item_properties(self):
        empty_pixmaps = dbus.Array([], signature="(iiay)")
        tooltip = dbus.Struct(
            (
                dbus.String(""),
                empty_pixmaps,
                dbus.String(self.title),
                dbus.String("Reproducible Shibumi tray and DBusMenu fixture"),
            ),
            signature="sa(iiay)ss",
        )
        return {
            "Category": dbus.String("ApplicationStatus"),
            "Id": dbus.String(self.fixture_id),
            "Title": dbus.String(self.title),
            "Status": dbus.String(self.status),
            "WindowId": dbus.UInt32(0),
            "IconName": dbus.String("dialog-information-symbolic"),
            "IconPixmap": empty_pixmaps,
            "OverlayIconName": dbus.String(""),
            "OverlayIconPixmap": empty_pixmaps,
            "AttentionIconName": dbus.String("dialog-warning-symbolic"),
            "AttentionIconPixmap": empty_pixmaps,
            "AttentionMovieName": dbus.String(""),
            "ToolTip": tooltip,
            "ItemIsMenu": dbus.Boolean(False),
            "Menu": dbus.ObjectPath("/Menu"),
            "ActivationCount": dbus.UInt32(self.activation_count),
            "MenuEventCount": dbus.UInt32(self.menu_event_count),
        }

    def record_event(self, event_type, item_id=0):
        if event_type == "activate":
            self.activation_count += 1
        elif event_type == "menu":
            self.menu_event_count += 1
        print(
            f"fixture-event type={event_type} item={item_id} "
            f"activations={self.activation_count} menus={self.menu_event_count}",
            flush=True,
        )

    @dbus.service.method(SNI_IFACE, in_signature="ii", out_signature="")
    def Activate(self, x, y):
        del x, y
        self.record_event("activate")

    @dbus.service.method(SNI_IFACE, in_signature="ii", out_signature="")
    def SecondaryActivate(self, x, y):
        del x, y
        self.record_event("secondary")

    @dbus.service.method(SNI_IFACE, in_signature="ii", out_signature="")
    def ContextMenu(self, x, y):
        del x, y
        self.record_event("context")

    @dbus.service.method(SNI_IFACE, in_signature="is", out_signature="")
    def Scroll(self, delta, orientation):
        self.record_event(f"scroll-{orientation}", int(delta))

    @dbus.service.method(
        PROPERTIES_IFACE, in_signature="ss", out_signature="v"
    )
    def Get(self, interface_name, property_name):
        if str(interface_name) != SNI_IFACE:
            raise dbus.exceptions.DBusException(
                "org.freedesktop.DBus.Error.InvalidArgs"
            )
        values = self.item_properties()
        if str(property_name) not in values:
            raise dbus.exceptions.DBusException(
                "org.freedesktop.DBus.Error.InvalidArgs"
            )
        return values[str(property_name)]

    @dbus.service.method(
        PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}"
    )
    def GetAll(self, interface_name):
        if str(interface_name) != SNI_IFACE:
            return variant_dictionary({})
        return variant_dictionary(self.item_properties())

    @dbus.service.signal(SNI_IFACE, signature="")
    def NewIcon(self):
        pass

    @dbus.service.signal(SNI_IFACE, signature="s")
    def NewStatus(self, status):
        del status

    @dbus.service.signal(SNI_IFACE, signature="")
    def NewToolTip(self):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", default="primary")
    parser.add_argument("--title", default="Shibumi Fixture")
    parser.add_argument(
        "--status", choices=("Active", "NeedsAttention"), default="Active"
    )
    args = parser.parse_args()

    safe_name = "".join(
        character if character.isalnum() else "_" for character in args.name
    )
    bus_name = f"org.shibumi.TrayFixture.{safe_name}"
    fixture_id = f"shibumi-tray-fixture-{safe_name}"

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    name = dbus.service.BusName(
        bus_name, bus=bus, allow_replacement=False, replace_existing=False,
        do_not_queue=True
    )
    item = FixtureItem(bus, fixture_id, args.title, args.status)
    menu = FixtureMenu(bus, item.record_event)
    keepalive = (name, item, menu)

    watcher = dbus.Interface(
        bus.get_object(WATCHER_NAME, WATCHER_PATH), WATCHER_IFACE
    )
    watcher.RegisterStatusNotifierItem(bus_name)

    loop = GLib.MainLoop()
    signal.signal(signal.SIGTERM, lambda *_args: loop.quit())
    signal.signal(signal.SIGINT, lambda *_args: loop.quit())
    print(
        f"fixture-ready service={bus_name} id={fixture_id} status={args.status}",
        flush=True,
    )
    loop.run()
    del keepalive
    return 0


if __name__ == "__main__":
    sys.exit(main())
