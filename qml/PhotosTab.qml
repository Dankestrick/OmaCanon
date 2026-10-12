import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Step 2: days on the left, that day's photos on the right. Two ways to work:
// "Pick keepers" (click = ✓, Next takes them to step 3) and "Clean up"
// (click = mark for the trash, one button moves them all). Double-click a
// photo to see it big.
Item {
  id: root

  property var svc: null
  property bool active: false
  property color foreground: Color.foreground
  property color background: Color.background
  property color accent: Color.accent
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  property var textOn: function(c) { return root.foreground }

  signal escapePressed()
  signal goToSave()

  readonly property var photos: svc ? svc.photos : []
  readonly property var picked: svc ? svc.picked : ({})
  readonly property var marked: svc ? svc.marked : ({})
  property string mode: "keep"      // "keep" or "clean"
  readonly property string dayPath: {
    var days = svc ? svc.days : []
    for (var i = 0; i < days.length; i++) if (days[i].date === svc.day) return days[i].path
    return ""
  }
  readonly property color danger: "#c62828"
  readonly property bool cleaning: mode === "clean"

  // Space / click: pick in keep mode, mark for the trash in clean mode.
  function toggle(p) {
    if (!p || p.sent) return
    if (root.cleaning) root.svc.toggleMark(p.path)
    else root.svc.togglePick(p.path)
  }
  property int viewing: -1          // index of the photo shown big, -1 = grid
  property string confirmPath: ""

  function focusGrid() {
    if (root.viewing >= 0) viewer.forceActiveFocus()
    else grid.forceActiveFocus()
    if (grid.currentIndex < 0 && grid.count > 0) grid.currentIndex = 0
  }

  function fileUrl(path) {
    return path ? "file://" + encodeURI(path) : ""
  }

  // Viewer: keep (pick it in keep mode) and go on to the next photo.
  function keepAndNext() {
    var p = root.photos[root.viewing]
    if (p && !p.sent && !root.cleaning && !root.picked[p.path]) root.svc.togglePick(p.path)
    if (root.viewing < root.photos.length - 1) root.viewing += 1
  }

  function trashOne(index) {
    var p = root.photos[index]
    if (!p) return
    root.svc.trash([p.path])
    if (root.photos.length <= 1) root.viewing = -1
    else if (index >= root.photos.length - 1) root.viewing = index - 1
  }

  RowLayout {
    anchors.fill: parent
    spacing: Style.spacing.huge
    visible: root.viewing < 0

    // Days
    ColumnLayout {
      Layout.preferredWidth: Style.space(290)
      Layout.minimumWidth: Style.space(290)
      Layout.maximumWidth: Style.space(290)
      Layout.fillHeight: true
      spacing: Style.spacing.md

      Text {
        textFormat: Text.PlainText
        text: "Days"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        font.bold: true
      }

      ListView {
        id: dayList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: Style.spacing.sm
        model: root.svc ? root.svc.days : []
        delegate: Rectangle {
          id: dayRow
          required property var modelData
          readonly property bool current: root.svc && root.svc.day === modelData.date
          width: dayList.width
          height: dayText.implicitHeight + Style.spacing.xl * 2
          color: current ? root.accent : (dayMouse.containsMouse ? Qt.alpha(root.foreground, 0.08) : "transparent")
          border.color: Qt.alpha(root.foreground, 0.25)
          border.width: current ? 0 : 1

          Column {
            id: dayText
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.xl
            spacing: Style.spacing.xxs

            Text {
              textFormat: Text.PlainText
              text: dayRow.modelData.label
              color: dayRow.current ? root.textOn(root.accent) : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: dayRow.modelData.count + (dayRow.modelData.count === 1 ? " photo" : " photos")
                + (dayRow.modelData.sent > 0 ? "   ·   " + dayRow.modelData.sent + " in OmaRAW" : "")
              color: dayRow.current ? root.textOn(root.accent) : root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          MouseArea {
            id: dayMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.svc.loadDay(dayRow.modelData.date)
          }
        }

        Text {
          anchors.centerIn: parent
          width: parent.width
          visible: dayList.count === 0
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: "No photos on the PC yet. Plug in the camera to bring them over."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }
      }
    }

    // Photos of the chosen day
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.spacing.lg

      // Which job: pick keepers, or clean up.
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.md

        Repeater {
          model: [
            { id: "keep", label: "✓   Pick keepers" },
            { id: "clean", label: "✕   Clean up (delete)" }
          ]
          delegate: Button {
            required property var modelData
            text: modelData.label
            bordered: true
            fontSize: Style.font.title
            verticalPadding: Style.spacing.md
            horizontalPadding: Style.spacing.xxl
            background: root.mode === modelData.id ? (modelData.id === "clean" ? root.danger : root.accent) : "transparent"
            foreground: root.textOn(background)
            onClicked: {
              root.mode = modelData.id
              grid.forceActiveFocus()
            }
          }
        }

        Item { Layout.fillWidth: true }

        Button {
          text: "📁   Open this day's folder"
          bordered: true
          fontSize: Style.font.title
          verticalPadding: Style.spacing.md
          enabled: root.dayPath !== ""
          onClicked: root.svc.openFolder(root.dayPath)
        }

        Button {
          text: "See them one by one"
          bordered: true
          fontSize: Style.font.title
          verticalPadding: Style.spacing.md
          enabled: root.photos.length > 0
          onClicked: root.viewing = Math.max(0, grid.currentIndex)
        }
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: root.cleaning
          ? "Click the photos you don't want (they get a red ✕), then press Move to the trash. Photos already in OmaRAW stay put."
          : "Click the photos you want to keep (they get a ✓), then press Next. Double-click a photo to see it big."
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        wrapMode: Text.Wrap
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.lg

        Button {
          text: root.cleaning ? "Mark all of this day" : "Pick all"
          bordered: true
          enabled: root.photos.length > 0
          onClicked: root.cleaning ? root.svc.markAll(true) : root.svc.pickAll(true)
        }

        Button {
          text: root.cleaning ? "Unmark all" : "Pick none"
          bordered: true
          enabled: root.photos.length > 0
          onClicked: root.cleaning ? root.svc.markAll(false) : root.svc.pickAll(false)
        }

        Item { Layout.fillWidth: true }

        Text {
          textFormat: Text.PlainText
          visible: root.svc && root.svc.loadingDay && root.photos.length === 0
          text: "Loading the photos…"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      GridView {
        id: grid
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        focus: true
        readonly property int columns: Math.max(2, Math.floor(width / Style.space(230)))
        cellWidth: Math.floor(width / columns)
        cellHeight: Math.round(cellWidth * 0.72)
        model: root.photos
        keyNavigationEnabled: true
        highlightFollowsCurrentItem: false
        Keys.onEscapePressed: root.escapePressed()
        Keys.onReturnPressed: if (currentIndex >= 0) root.viewing = currentIndex
        Keys.onSpacePressed: root.toggle(root.photos[currentIndex])
        Keys.onDeletePressed: {
          var p = root.photos[currentIndex]
          if (!p || p.sent) return
          root.mode = "clean"
          root.svc.toggleMark(p.path)
        }

        delegate: Item {
          id: cell
          required property var modelData
          required property int index
          readonly property bool isPicked: !root.cleaning && !!root.picked[modelData.path]
          readonly property bool isMarked: !!root.marked[modelData.path]
          readonly property bool isSent: !!modelData.sent
          width: grid.cellWidth
          height: grid.cellHeight

          Rectangle {
            anchors.fill: parent
            anchors.margins: Style.spacing.sm
            color: Qt.alpha(root.foreground, 0.05)
            border.color: cell.isMarked ? root.danger : cell.isPicked ? root.accent
              : (grid.currentIndex === cell.index && grid.activeFocus ? root.foreground : "transparent")
            border.width: Style.space(cell.isPicked || cell.isMarked ? 4 : 2)

            Image {
              anchors.fill: parent
              anchors.margins: Style.space(cell.isPicked ? 6 : 4)
              source: root.fileUrl(cell.modelData.thumb)
              sourceSize.width: 480
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              cache: false
              opacity: cell.isSent || cell.isMarked ? 0.4 : 1
            }

            // Marked for the trash
            Rectangle {
              anchors.centerIn: parent
              visible: cell.isMarked
              width: Style.space(64)
              height: width
              radius: width / 2
              color: root.danger
              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "✕"
                color: root.textOn(root.danger)
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                font.bold: true
              }
            }

            // Pick mark
            Rectangle {
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.spacing.md
              width: Style.space(34)
              height: width
              radius: width / 2
              visible: !cell.isSent && !root.cleaning
              color: cell.isPicked ? root.accent : Qt.alpha(root.background, 0.7)
              border.color: cell.isPicked ? root.accent : root.foreground
              border.width: Style.space(2)
              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: cell.isPicked ? "✓" : ""
                color: root.textOn(root.accent)
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                font.bold: true
              }
            }

            // Already in OmaRAW
            Rectangle {
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.margins: Style.spacing.md
              visible: cell.isSent
              color: Qt.alpha(root.background, 0.85)
              width: sentText.implicitWidth + Style.spacing.lg * 2
              height: sentText.implicitHeight + Style.spacing.sm * 2
              Text {
                id: sentText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "✓ In OmaRAW"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                grid.currentIndex = cell.index
                grid.forceActiveFocus()
                root.toggle(cell.modelData)
              }
              onDoubleClicked: {
                // The first click of a double-click already flipped the mark.
                root.toggle(cell.modelData)
                root.viewing = cell.index
              }
            }
          }
        }
      }

      // Send bar
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xxl

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: root.cleaning
            ? (root.svc && root.svc.markedCount > 0
              ? (root.svc.markedCount === 1 ? "1 photo marked" : root.svc.markedCount + " photos marked")
              : "Nothing marked")
            : root.svc && root.svc.pickedCount > 0
            ? (root.svc.pickedCount === 1 ? "1 photo picked" : root.svc.pickedCount + " photos picked")
            : "Nothing picked yet"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
        }

        Button {
          visible: root.cleaning
          text: "Move " + (root.svc ? root.svc.markedCount : 0) + " to the trash"
          bordered: true
          enabled: root.svc && root.svc.markedCount > 0
          fontSize: Style.font.display
          verticalPadding: Style.spacing.xl
          horizontalPadding: Style.spacing.huge * 2
          background: enabled ? root.danger : "transparent"
          foreground: root.textOn(background)
          onClicked: root.svc.trashMarked()
        }

        Button {
          visible: !root.cleaning
          text: "Next: save them  ›"
          bordered: true
          enabled: root.svc && root.svc.pickedCount > 0
          fontSize: Style.font.display
          verticalPadding: Style.spacing.xl
          horizontalPadding: Style.spacing.huge * 2
          background: enabled ? root.accent : "transparent"
          foreground: root.textOn(background)
          onClicked: root.goToSave()
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // One photo, big
  // ---------------------------------------------------------------------------

  Item {
    id: viewer
    anchors.fill: parent
    visible: root.viewing >= 0
    focus: visible
    onVisibleChanged: if (visible) forceActiveFocus(); else grid.forceActiveFocus()

    readonly property var photo: root.viewing >= 0 ? root.photos[root.viewing] : null
    readonly property bool isPicked: !!(photo && root.picked[photo.path])

    Keys.onEscapePressed: root.viewing = -1
    Keys.onLeftPressed: if (root.viewing > 0) root.viewing -= 1
    Keys.onRightPressed: if (root.viewing < root.photos.length - 1) root.viewing += 1
    Keys.onSpacePressed: root.keepAndNext()
    Keys.onDeletePressed: if (photo && !photo.sent) root.trashOne(root.viewing)

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.spacing.lg

      Image {
        Layout.fillWidth: true
        Layout.fillHeight: true
        source: viewer.photo ? root.fileUrl(viewer.photo.preview) : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xxl

        Button {
          text: "‹  Back to all photos"
          bordered: true
          fontSize: Style.font.title
          verticalPadding: Style.spacing.lg
          onClicked: root.viewing = -1
        }

        Button {
          text: "←"
          bordered: true
          fontSize: Style.font.display
          enabled: root.viewing > 0
          onClicked: root.viewing -= 1
        }

        Button {
          text: "→"
          bordered: true
          fontSize: Style.font.display
          enabled: root.viewing < root.photos.length - 1
          onClicked: root.viewing += 1
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          text: viewer.photo ? (root.viewing + 1) + " of " + root.photos.length + "   ·   " + viewer.photo.name : ""
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          elide: Text.ElideMiddle
        }

        Button {
          visible: !!(viewer.photo && !viewer.photo.sent)
          text: "✕   Delete"
          bordered: true
          fontSize: Style.font.display
          verticalPadding: Style.spacing.lg
          horizontalPadding: Style.spacing.huge
          background: root.danger
          foreground: root.textOn(background)
          onClicked: root.trashOne(root.viewing)
        }

        Button {
          visible: !!(viewer.photo && viewer.photo.sent)
          text: "✓ In OmaRAW"
          bordered: true
          enabled: false
          fontSize: Style.font.display
          verticalPadding: Style.spacing.lg
        }

        Button {
          visible: !!(viewer.photo && !viewer.photo.sent)
          text: root.cleaning ? "Keep  ›" : viewer.isPicked ? "✓ Keeping  ›" : "✓ Keep  ›"
          bordered: true
          fontSize: Style.font.display
          verticalPadding: Style.spacing.lg
          horizontalPadding: Style.spacing.huge
          background: root.accent
          foreground: root.textOn(background)
          onClicked: root.keepAndNext()
        }
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: "Space: keep and go to the next   ·   Delete: to the trash   ·   Arrow keys: next / previous   ·   Esc: back"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
