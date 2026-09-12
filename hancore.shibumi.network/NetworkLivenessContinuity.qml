pragma ComponentBehavior: Bound

import Quickshell

// Must be instantiated exactly once by the process-wide Network service.
// Quickshell copies this latch across soft QML reloads; a full process restart
// creates the only fresh false value permitted for the static Network backend.
PersistentProperties {
  reloadableId: "shibumiNetworkManagerLivenessContinuity"
  property bool processRestartRequired: false
}
