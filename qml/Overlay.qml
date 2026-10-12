import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// The OmaCanon window: a normal app window, floated and centered by Hyprland
// because its size is fixed. Three steps: bring the photos over, pick the
// keepers, then save them (folder only, or OmaRAW too).
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool closingFromHost: false
  property string tab: "camera"

  readonly property var svc: (shell && shell.serviceFor)
    ? shell.serviceFor((manifest && manifest.id) || "io.github.dankestrick.omacanon") : null

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color accent: Color.accent
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  readonly property int pad: Style.spacing.panelPadding

  onOpenedChanged: if (svc) svc.windowOpen = opened

  // Text colour for a filled button: dark on light accents, light on dark ones.
  function textOn(fill) {
    var c = Qt.color(fill)
    if (c.a < 0.5) return root.foreground
    return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) > 0.55 ? "#111111" : "#f4f4f4"
  }

  function open(payloadJson) {
    root.closingFromHost = false
    var monitor = Hyprland.focusedMonitor
    for (var i = 0; i < Quickshell.screens.length; i++)
      if (monitor && Quickshell.screens[i].name === monitor.name && !panel.visible) panel.screen = Quickshell.screens[i]
    root.opened = true
    try {
      var payload = payloadJson ? JSON.parse(payloadJson) : null
      if (payload && ["camera", "photos", "save"].indexOf(payload.tab) >= 0) root.tab = payload.tab
      if (payload && /^\d{4}-\d{2}-\d{2}$/.test(String(payload.day || "")) && root.svc) root.svc.loadDay(payload.day)
    } catch (ignore) {}
    if (root.svc) {
      root.svc.windowOpen = true
      root.svc.refreshStatus()
      root.svc.refreshDays()
    }
    Qt.callLater(root.focusTab)
  }

  // Keys go to the photo grid on step 2, to the window on step 1.
  function focusTab() {
    if (root.tab === "photos") photosTab.focusGrid()
    else keyCatcher.forceActiveFocus()
  }

  onTabChanged: if (root.opened) Qt.callLater(root.focusTab)

  function close() {
    root.closingFromHost = true
    root.opened = false
    root.closingFromHost = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.dankestrick.omacanon")
  }

  readonly property string statusLine: {
    if (!root.svc || !root.svc.checkedOnce) return "Starting…"
    if (!root.svc.camera) return "No camera plugged in"
    if (root.svc.webcam) return "Camera is busy being a webcam"
    var j = root.svc.job
    var parts = ["Camera connected"]
    if (j.battery) parts.push("Battery " + j.battery)
    if (j.onCard) parts.push(j.onCard.toLocaleString(Qt.locale(), "f", 0) + " photos on the card")
    return parts.join("   ·   ")
  }

  readonly property var tabs: [
    { id: "camera", label: "1   Bring photos" },
    { id: "photos", label: "2   Go through photos" },
    { id: "save", label: "3   Save" }
  ]

  FloatingWindow {
    id: panel
    visible: root.opened
    title: "OmaCanon"
    color: root.background
    // A fixed size makes Hyprland float and center it with no window rule.
    property size fixed: Qt.size(Math.round(Style.space(1240)), Math.round(Style.space(800)))
    implicitWidth: fixed.width
    implicitHeight: fixed.height
    minimumSize: fixed
    maximumSize: fixed

    // Closed from Hyprland (SUPER+W): tell the shell so the next toggle opens it.
    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.dismiss()
    }

    Rectangle {
      anchors.fill: parent
      color: root.background

      // Faint OMACANON behind everything, out to the border.
      NameBackdrop {
        anchors.margins: Style.space(2)
        fontFamily: root.fontFamily
        color: root.accent
        strength: 0.16
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.dismiss()

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: root.pad
          spacing: Style.spacing.xxl

          // Title row
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.lg

            Text {
              textFormat: Text.PlainText
              text: "OmaCanon"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
              rightPadding: Style.spacing.xl
            }

            Repeater {
              model: root.tabs
              delegate: Button {
                required property var modelData
                text: modelData.label
                bordered: true
                fontSize: Style.font.title
                verticalPadding: Style.spacing.md
                horizontalPadding: Style.spacing.xxl
                background: root.tab === modelData.id ? root.accent : "transparent"
                foreground: root.textOn(background)
                onClicked: root.tab = modelData.id
              }
            }

            Text {
              textFormat: Text.PlainText
              Layout.fillWidth: true
              horizontalAlignment: Text.AlignRight
              text: root.statusLine
              color: root.svc && root.svc.camera ? root.foreground : root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Button {
              text: "Close"
              bordered: true
              onClicked: root.dismiss()
            }
          }

          StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.tab === "save" ? 2 : root.tab === "photos" ? 1 : 0

            CameraTab {
              svc: root.svc
              foreground: root.foreground
              accent: root.accent
              muted: root.muted
              fontFamily: root.fontFamily
              textOn: root.textOn
              onGoToPhotos: root.tab = "photos"
            }

            PhotosTab {
              id: photosTab
              svc: root.svc
              active: root.opened && root.tab === "photos"
              foreground: root.foreground
              background: root.background
              accent: root.accent
              muted: root.muted
              fontFamily: root.fontFamily
              textOn: root.textOn
              onEscapePressed: root.dismiss()
              onGoToSave: root.tab = "save"
            }

            SaveTab {
              svc: root.svc
              active: root.opened && root.tab === "save"
              foreground: root.foreground
              background: root.background
              accent: root.accent
              muted: root.muted
              fontFamily: root.fontFamily
              textOn: root.textOn
              onGoToPhotos: root.tab = "photos"
            }
          }

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: root.svc ? root.svc.notice : ""
            visible: text !== ""
            color: root.svc && root.svc.noticeIsError ? Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }
}
