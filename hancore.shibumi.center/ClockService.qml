import QtQuick
import Quickshell

Scope {
  readonly property date date: systemClock.date

  SystemClock {
    id: systemClock
    precision: SystemClock.Minutes
  }
}
