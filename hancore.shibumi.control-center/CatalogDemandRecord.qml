pragma ComponentBehavior: Bound
import QtQuick

// Private consumer-owned lifetime guard.
QtObject {
  id: record
  required property QtObject holder
  required property QtObject manager
  property var token: null
  Component.onDestruction: {
    var owner = manager
    var retiringHolder = holder
    manager = null
    if (owner) owner.recordDestroyed(record, retiringHolder)
  }
}
