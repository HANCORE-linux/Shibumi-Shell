pragma ComponentBehavior: Bound

import QtQuick

// Holder-parented registration guard. The service keeps no visual Item alive
// after its BarWidget owner is destroyed.
QtObject {
  id: record
  required property QtObject manager
  required property QtObject holder
  required property QtObject hostedBar
  property var token: null

  Component.onDestruction: {
    const service = manager
    manager = null
    if (service) service.visualBarRecordDestroyed(record)
  }
}
