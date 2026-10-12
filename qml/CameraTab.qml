import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Step 1: the camera. One big message for where things stand, and at most
// one big button for what to do next.
Item {
  id: root

  property var svc: null
  property color foreground: Color.foreground
  property color accent: Color.accent
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  property var textOn: function(c) { return root.foreground }

  signal goToPhotos()

  readonly property var job: svc ? svc.job : ({})
  readonly property string state: {
    if (!svc || !svc.checkedOnce) return "starting"
    if (!svc.camera) return "unplugged"
    if (svc.webcam) return "webcam"
    if (svc.downloading && job.state === "scanning") return "scanning"
    if (svc.downloading) return "downloading"
    if (job.state === "error") return "error"
    if (job.state === "stopped") return "stopped"
    if (job.state === "done") return "done"
    return "ready"
  }

  function count(n) {
    return Number(n || 0).toLocaleString(Qt.locale(), "f", 0)
  }

  function timeLeft(seconds) {
    var s = Number(seconds || 0)
    if (s <= 0) return ""
    if (s < 60) return "less than a minute left"
    var m = Math.round(s / 60)
    if (m < 60) return "about " + m + (m === 1 ? " minute left" : " minutes left")
    var h = Math.floor(m / 60)
    return "about " + h + " h " + (m % 60) + " min left"
  }

  readonly property string headline: {
    switch (root.state) {
    case "starting": return "One moment…"
    case "unplugged": return "Plug in the camera"
    case "webcam": return "The camera is your webcam"
    case "scanning": return "Looking at the camera's card…"
    case "downloading": return "Bringing photos to the PC"
    case "error": return "Something got in the way"
    case "stopped": return "Stopped"
    case "done": return (job.total || 0) > 0 ? "All caught up ✓" : "No new photos ✓"
    default: return "Camera connected"
    }
  }

  readonly property string detail: {
    switch (root.state) {
    case "unplugged": return ""
    case "webcam": return "It's streaming to OBS. For a sharp picture, set the lens switch to MF and turn the focus ring while you watch OBS. To bring photos over instead, turn the webcam off."
    case "scanning": return "Checking which photos are new."
    case "downloading": {
      var line = count(job.done) + " of " + count(job.total)
      var left = timeLeft(job.eta)
      return left ? line + "   ·   " + left : line
    }
    case "error": return job.error || "The camera stopped answering."
    case "stopped": return count(job.done) + " of " + count(job.total) + " came over. The rest are still on the camera."
    case "done": return (job.total || 0) > 0
      ? (job.done === 1 ? "1 new photo came over." : count(job.done) + " new photos came over.") + " Now pick the ones you want to keep."
      : "Everything on the card is already on the PC."
    default: return "Press the button to bring new photos over."
    }
  }

  ColumnLayout {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(80), Style.space(820))
    spacing: Style.spacing.huge * 2

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      text: root.headline
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.displayLarge * 1.4
      font.bold: true
      wrapMode: Text.Wrap
    }

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      visible: text !== ""
      text: root.detail
      color: root.state === "error" ? Color.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
      wrapMode: Text.Wrap
    }

    // How to plug in, as three numbered steps.
    ColumnLayout {
      Layout.fillWidth: true
      visible: root.state === "unplugged"
      spacing: Style.spacing.huge

      Repeater {
        model: [
          "Turn the camera's Wi-Fi off (only needed once):\nMENU › wrench tab › Wi-Fi/NFC › Disable",
          "Plug the camera's USB cable into the PC",
          "Turn the camera on"
        ]
        delegate: RowLayout {
          required property int index
          required property string modelData
          Layout.fillWidth: true
          spacing: Style.spacing.xxl

          Rectangle {
            Layout.preferredWidth: Style.space(44)
            Layout.preferredHeight: Style.space(44)
            radius: width / 2
            color: root.accent
            Text {
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: String(index + 1)
              color: root.textOn(root.accent)
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }
          }

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: modelData
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            wrapMode: Text.Wrap
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        Layout.topMargin: Style.spacing.xxl
        text: "This window opens by itself when the camera is plugged in."
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }
    }

    // Progress while photos come over.
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Style.space(28)
      visible: root.state === "downloading" || root.state === "stopped"
      color: "transparent"
      border.color: root.accent
      border.width: Math.max(1, Style.space(2))

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Style.space(4)
        width: Math.max(0, (parent.width - Style.space(8)) * Math.min(1, (job.doneKB || 0) / Math.max(1, job.totalKB || 1)))
        color: root.accent
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
      }
    }

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      visible: root.state === "downloading" && (job.done || 0) > 0
      text: "You can already start picking keepers in step 2 while this runs."
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }

    // The one big button.
    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      spacing: Style.spacing.xxl

      Button {
        visible: root.state === "webcam"
        text: "Turn the webcam off"
        bordered: true
        fontSize: Style.font.display
        verticalPadding: Style.spacing.xl
        horizontalPadding: Style.spacing.huge * 2
        onClicked: root.svc.webcamOff()
      }

      Button {
        visible: ["ready", "stopped", "error"].indexOf(root.state) >= 0
        text: root.state === "stopped" ? "Bring the rest" : root.state === "error" ? "Try again" : "Bring new photos to the PC"
        bordered: true
        fontSize: Style.font.display
        verticalPadding: Style.spacing.xl
        horizontalPadding: Style.spacing.huge * 2
        background: root.accent
        foreground: root.textOn(background)
        onClicked: root.svc.startDownload()
      }

      Button {
        visible: root.state === "done" || (root.state === "downloading" && (job.done || 0) > 0)
        text: "Go to step 2: pick keepers"
        bordered: true
        fontSize: Style.font.display
        verticalPadding: Style.spacing.xl
        horizontalPadding: Style.spacing.huge * 2
        background: root.state === "done" ? root.accent : "transparent"
        foreground: root.textOn(background)
        onClicked: root.goToPhotos()
      }

      Button {
        visible: root.state === "downloading"
        text: "Stop"
        bordered: true
        fontSize: Style.font.display
        verticalPadding: Style.spacing.xl
        horizontalPadding: Style.spacing.huge * 2
        onClicked: root.svc.stopDownload()
      }
    }

    // Its own row, so the buttons above never get too wide for the window.
    Button {
      Layout.alignment: Qt.AlignHCenter
      visible: root.state !== "starting"
      text: "📁   Open the photo folder"
      bordered: true
      fontSize: Style.font.display
      verticalPadding: Style.spacing.xl
      horizontalPadding: Style.spacing.huge * 2
      onClicked: root.svc.openFolder("")
    }
  }

  // Where the photos live.
  RowLayout {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    spacing: Style.spacing.lg

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
      text: "Photos go to Pictures › Canon, sorted by the day they were taken. Nothing is ever erased from the camera."
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }
}
