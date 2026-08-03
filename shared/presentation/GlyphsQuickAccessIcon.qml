pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
  id: root

  property string name: "images"
  property color color: "white"
  property real sourceStrokeWidth: 3

  implicitWidth: 20
  implicitHeight: 20

  // Glyphs Core 0.8.12, path variant. The website defaults this variant to
  // stroke width 3. Source geometry is kept in its native 80 x 80 viewBox.
  // https://glyphs.fyi/dir/images?s=core&v=path
  // https://glyphs.fyi/dir/palette?s=core&v=path
  Shape {
    anchors.centerIn: parent
    width: 80
    height: 80
    scale: Math.min(root.width, root.height) / 80
    visible: root.name === "images"
    antialiasing: true

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.sourceStrokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: "M21 21C21 17.6863 23.6863 15 27 15H59C62.3137 15 65 17.6863 65 21V53C65 56.3137 62.3137 59 59 59H27C23.6863 59 21 56.3137 21 53V21Z"
      }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.sourceStrokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: "M21 21C17.6863 21 15 23.6863 15 27V59C15 62.3137 17.6863 65 21 65H53C56.3137 65 59 62.3137 59 59"
      }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.sourceStrokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: "M27 59H59C61.8222 59 64.1893 57.0515 64.8294 54.4264C64.905 54.1164 64.7952 53.7952 64.5696 53.5695L58.7071 47.7071C58.3166 47.3165 57.6834 47.3165 57.2929 47.7071L53.5212 51.4788C53.1186 51.8814 52.4616 51.8671 52.0769 51.4475L37.7372 35.8041C37.3408 35.3718 36.6592 35.3718 36.2629 35.8041L21.2628 52.1678C21.0938 52.3522 21 52.5933 21 52.8435V53C21 56.3137 23.6863 59 27 59Z"
      }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.sourceStrokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: "M48.4018 22.5C50.0095 21.5718 51.9902 21.5718 53.5979 22.5C55.2056 23.4282 56.196 25.1436 56.196 27C56.196 28.8564 55.2056 30.5718 53.5979 31.5C51.9902 32.4282 50.0095 32.4282 48.4018 31.5C46.7941 30.5718 45.8037 28.8564 45.8037 27C45.8037 25.1436 46.7941 23.4282 48.4018 22.5Z"
      }
    }
  }

  Shape {
    anchors.centerIn: parent
    width: 80
    height: 80
    scale: Math.min(root.width, root.height) / 80
    visible: root.name === "palette"
    antialiasing: true

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.sourceStrokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: "M53.5692 15.7128C44.9948 10.7624 34.4308 10.7624 25.8564 15.7128C17.282 20.6632 12 29.812 12 39.7128C12 49.6136 17.282 58.7624 25.8564 63.7128C32.7649 67.7014 40.965 68.4764 48.3753 66.0377L43.6524 56.5918C43.0346 55.3561 42.7129 53.9935 42.7129 52.612C42.7129 47.6971 46.6972 43.7128 51.6121 43.7128H67.136C67.3274 42.3993 67.4256 41.063 67.4256 39.7128C67.4256 29.812 62.1436 20.6632 53.5692 15.7128Z"
      }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.sourceStrokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: "M23.4139 45.4628C24.2178 44.9987 25.2081 44.9987 26.012 45.4628C26.8158 45.9269 27.311 46.7846 27.311 47.7128C27.311 48.641 26.8158 49.4987 26.012 49.9628C25.2081 50.4269 24.2178 50.4269 23.4139 49.9628C22.6101 49.4987 22.1149 48.641 22.1149 47.7128C22.1149 46.7846 22.6101 45.9269 23.4139 45.4628Z"
      }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.sourceStrokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: "M24.4139 28.4628C25.2178 27.9987 26.2081 27.9987 27.012 28.4628C27.8158 28.9269 28.311 29.7846 28.311 30.7128C28.311 31.641 27.8158 32.4987 27.012 32.9628C26.2081 33.4269 25.2178 33.4269 24.4139 32.9628C23.6101 32.4987 23.1149 31.641 23.1149 30.7128C23.1149 29.7846 23.6101 28.9269 24.4139 28.4628Z"
      }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.sourceStrokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: "M38.701 20.7501C39.5049 20.286 40.4952 20.286 41.2991 20.7501C42.1029 21.2142 42.5981 22.0719 42.5981 23.0001C42.5981 23.9283 42.1029 24.786 41.2991 25.2501C40.4952 25.7142 39.5049 25.7142 38.701 25.2501C37.8972 24.786 37.402 23.9283 37.402 23.0001C37.402 22.0719 37.8972 21.2142 38.701 20.7501Z"
      }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.sourceStrokeWidth
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg {
        path: "M52.701 28.7501C53.5049 28.286 54.4952 28.286 55.2991 28.7501C56.1029 29.2142 56.5981 30.0719 56.5981 31.0001C56.5981 31.9283 56.1029 32.786 55.2991 33.2501C54.4952 33.7142 53.5049 33.7142 52.701 33.2501C51.8972 32.786 51.402 31.9283 51.402 31.0001C51.402 30.0719 51.8972 29.2142 52.701 28.7501Z"
      }
    }
  }
}
