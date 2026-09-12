pragma ComponentBehavior: Bound
import QtQuick

// Read interest, not native authority. Interest survives transient admission
// loss; NativeCatalog separately revokes publication/work for that loss.
Item {
  id: root
  property var _records: []
  property var _retiringHolders: []
  property bool _destroying: false
  property int _count: 0
  readonly property alias count: root._count

  function has(token) {
    if (_destroying || !token) return false
    return _records.some(function(record) {
      return Qt.isQtObject(record) && record.token === token && Qt.isQtObject(record.holder)
    })
  }

  function tokenFor(holder) {
    if (_destroying || !Qt.isQtObject(holder)) return null
    for (var i = 0; i < _records.length; i++) {
      var existing = _records[i]
      if (Qt.isQtObject(existing) && existing.holder === holder) return existing.token
    }
    return null
  }

  function acquire(holder) {
    if (_destroying || !Qt.isQtObject(holder)) return null
    _retiringHolders = _retiringHolders.filter(function(value) { return Qt.isQtObject(value) })
    if (_retiringHolders.indexOf(holder) >= 0) return null
    var existing = tokenFor(holder)
    if (existing) return existing
    if (_records.length >= 64) return null
    var token = Object.freeze({})
    // Parent the guard to the consumer. Holder destruction then destroys the
    // guard directly, without a weak-property callback after its QML context.
    var record = recordFactory.createObject(holder, {holder: holder, manager: root})
    if (!record || !Qt.isQtObject(record.holder)) {
      if (record) record.destroy()
      return null
    }
    // Set in JS, not createObject's QVariantMap: retain exact token identity.
    record.token = token
    _records = _records.concat([record])
    _count = _records.length
    // Count/Loader notifications can synchronously release/reacquire this owner.
    // Return its current token, never leave a hidden replacement behind null.
    if (_destroying || _records.indexOf(record) < 0 || !Qt.isQtObject(record.holder)) {
      release(token)
      return tokenFor(holder)
    }
    return token
  }

  function release(token) {
    if (_destroying || !token) return false
    var index = _records.findIndex(function(record) {
      return Qt.isQtObject(record) && record.token === token
    })
    if (index < 0) return false
    var previous = _records[index]
    _records = _records.filter(function(record) { return record !== previous })
    _count = _records.length
    // Publish loss first; a reentrant new lease is not part of this disposal.
    if (Qt.isQtObject(previous)) {
      previous.manager = null
      previous.destroy()
    }
    return true
  }

  // Called as the final statement of CatalogDemandRecord destruction. Block
  // reentrant acquisition of the holder that is itself being torn down, remove
  // its record, then publish count as this function's final operation.
  function recordDestroyed(record, holder) {
    if (_destroying || !Qt.isQtObject(record)) return
    var index = _records.indexOf(record)
    if (index < 0) return
    _retiringHolders = _retiringHolders.filter(function(value) { return Qt.isQtObject(value) })
    if (Qt.isQtObject(holder)) _retiringHolders = _retiringHolders.concat([holder])
    _records = _records.filter(function(value) { return value !== record })
    _count = _records.length
  }

  Component { id: recordFactory; CatalogDemandRecord {} }
  Component.onDestruction: {
    _destroying = true
    var retained = _records
    _records = []
    for (var i = 0; i < retained.length; i++) {
      if (!Qt.isQtObject(retained[i])) continue
      retained[i].manager = null
      retained[i].destroy()
    }
  }
}
