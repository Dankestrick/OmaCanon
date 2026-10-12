import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// Step 3: what to do with the picked photos. They are already saved in
// Pictures/Canon, so the choice is "that's enough" or "add them to OmaRAW too",
// where they get tagged and, if she likes, put in an album.
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

  signal goToPhotos()

  readonly property int count: svc ? svc.pickedCount : 0
  property bool claudeTags: false
  readonly property var tagJob: svc ? svc.claudeJob : ({})
  readonly property string claudeLine: {
    var t = root.tagJob
    if (!t || !t.state) return ""
    if (t.state === "tagging" || (t.state === "waiting" && t.running))
      return "Claude is tagging them: " + (t.done || 0) + " of " + (t.total || 0) + " done. You can close this window."
    if (t.state === "waiting-omaraw") return "Claude is ready to write the tags. Close the OmaRAW window so it can finish."
    if (t.state === "error") return "Claude tagging stopped: " + (t.error || "something went wrong") + ""
    if (t.state === "done" && root.saved && root.saved.claude) return "Claude tagged them ✓ Each one has keywords, a title and a caption in OmaRAW."
    return ""
  }
  readonly property var saved: svc ? svc.lastSaved : null

  readonly property string state: {
    if (!svc) return "nothing"
    if (svc.sending) return "sending"
    if (saved && count === 0) return "saved"
    if (count === 0) return "nothing"
    return "choose"
  }

  function photosWord(n) {
    return n === 1 ? "1 photo" : n + " photos"
  }

  onActiveChanged: if (active && svc) svc.refreshAlbums()

  readonly property string headline: {
    switch (root.state) {
    case "sending": return "Adding to OmaRAW…"
    case "saved": return "Saved ✓"
    case "nothing": return "Pick photos first"
    default: return "Save your " + photosWord(root.count)
    }
  }

  readonly property string detail: {
    switch (root.state) {
    case "sending": return "OmaRAW is looking at each photo to tag what's in it. This takes a few seconds per photo."
    case "saved":
      if (!saved.omaraw) return photosWord(saved.count) + (saved.count === 1 ? " is" : " are") + " saved in Pictures › Canon."
      return photosWord(saved.count) + (saved.count === 1 ? " is" : " are") + " in OmaRAW"
        + (saved.album ? ", in the album “" + saved.album + "”" : "")
        + ". " + (saved.count === 1 ? "It's" : "They're") + " still in Pictures › Canon too."
        + (root.claudeLine ? "\n\n" + root.claudeLine : "")
    case "nothing": return "Go to step 2 and click the photos you want to keep."
    default: return (root.count === 1 ? "It's" : "They're") + " already saved in Pictures › Canon. Choose one:"
    }
  }

  ColumnLayout {
    anchors.centerIn: parent
    width: Math.min(parent.width - Style.space(40), Style.space(1100))
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
      text: root.detail
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
      wrapMode: Text.Wrap
    }

    // The two choices, side by side.
    RowLayout {
      Layout.fillWidth: true
      visible: root.state === "choose"
      spacing: Style.spacing.huge * 2

      // A: the folder is enough.
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        color: Qt.alpha(root.foreground, 0.04)
        border.color: Qt.alpha(root.foreground, 0.3)
        border.width: Style.space(2)
        implicitHeight: folderCard.implicitHeight + Style.spacing.huge * 2

        ColumnLayout {
          id: folderCard
          anchors.fill: parent
          anchors.margins: Style.spacing.huge
          spacing: Style.spacing.xxl

          Text {
            textFormat: Text.PlainText
            text: "Keep them in the folder"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: "Nothing else happens. They stay in Pictures › Canon, sorted by the day they were taken."
            color: Qt.alpha(root.foreground, 0.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            wrapMode: Text.Wrap
          }

          Item { Layout.fillHeight: true }

          Button {
            Layout.alignment: Qt.AlignHCenter
            text: "Keep in the folder"
            bordered: true
            fontSize: Style.font.display
            verticalPadding: Style.spacing.xl
            horizontalPadding: Style.spacing.huge * 2
            onClicked: root.svc.keepInFolder()
          }
        }
      }

      // B: add to OmaRAW, with tags and an optional album.
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        color: Qt.alpha(root.accent, 0.08)
        border.color: root.accent
        border.width: Style.space(3)
        implicitHeight: omarawCard.implicitHeight + Style.spacing.huge * 2

        ColumnLayout {
          id: omarawCard
          anchors.fill: parent
          anchors.margins: Style.spacing.huge
          spacing: Style.spacing.xxl

          Text {
            textFormat: Text.PlainText
            text: "Add them to OmaRAW too"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: "OmaRAW tags what's in each photo (people, pets, food…) so they're easy to find, sort and edit later."
            color: Qt.alpha(root.foreground, 0.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            wrapMode: Text.Wrap
          }

          Text {
            textFormat: Text.PlainText
            text: "Put them in an album (you can leave this empty)"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          TextField {
            id: albumField
            Layout.fillWidth: true
            font.pixelSize: Style.font.title
            verticalPadding: Style.spacing.lg
            placeholderText: "Album name, like Beach trip"
            maximumLength: 80
            onAccepted: addButton.clicked()
          }

          // Albums she already has: one click fills the box.
          Flow {
            Layout.fillWidth: true
            spacing: Style.spacing.md
            visible: root.svc && root.svc.albums.length > 0

            Repeater {
              model: root.svc ? root.svc.albums.slice(0, 8) : []
              delegate: Button {
                required property string modelData
                text: modelData
                bordered: true
                background: albumField.text.toLowerCase() === modelData.toLowerCase() ? root.accent : "transparent"
                foreground: root.textOn(background)
                onClicked: albumField.text = modelData
              }
            }
          }

          // Claude tagging, one click.
          Button {
            visible: root.svc && root.svc.claudeAvailable
            text: root.claudeTags ? "✓   Claude will tag them" : "Let Claude tag them too"
            bordered: true
            fontSize: Style.font.title
            verticalPadding: Style.spacing.md
            background: root.claudeTags ? root.accent : "transparent"
            foreground: root.textOn(background)
            onClicked: root.claudeTags = !root.claudeTags
          }

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            visible: root.svc && root.svc.claudeAvailable
            text: "Claude looks at each photo and writes keywords, a title and a caption. It keeps going after this window closes."
            color: Qt.alpha(root.foreground, 0.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }

          Item { Layout.fillHeight: true }

          Button {
            id: addButton
            Layout.alignment: Qt.AlignHCenter
            text: "Add to OmaRAW"
            bordered: true
            fontSize: Style.font.display
            verticalPadding: Style.spacing.xl
            horizontalPadding: Style.spacing.huge * 2
            background: root.accent
            foreground: root.textOn(background)
            onClicked: root.svc.sendPicked(albumField.text.trim(), root.claudeTags)
          }
        }
      }
    }

    // After saving, or with nothing picked.
    RowLayout {
      Layout.alignment: Qt.AlignHCenter
      visible: root.state === "saved" || root.state === "nothing"
      spacing: Style.spacing.xxl

      Button {
        visible: root.state === "saved" && !!(root.saved && root.saved.omaraw)
        text: "Open OmaRAW"
        bordered: true
        fontSize: Style.font.display
        verticalPadding: Style.spacing.xl
        horizontalPadding: Style.spacing.huge * 2
        onClicked: root.svc.openOmaraw()
      }

      Button {
        visible: root.state === "saved"
        text: "Open the photo folder"
        bordered: true
        fontSize: Style.font.display
        verticalPadding: Style.spacing.xl
        horizontalPadding: Style.spacing.huge * 2
        onClicked: root.svc.openFolder("")
      }

      Button {
        text: root.state === "saved" ? "Pick more photos" : "Go to step 2"
        bordered: true
        fontSize: Style.font.display
        verticalPadding: Style.spacing.xl
        horizontalPadding: Style.spacing.huge * 2
        background: root.accent
        foreground: root.textOn(background)
        onClicked: {
          albumField.text = ""
          root.svc.startOver()
          root.goToPhotos()
        }
      }
    }
  }

  // Way back, while choosing.
  RowLayout {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    visible: root.state === "choose"
    spacing: Style.spacing.lg

    Button {
      text: "‹  Back to picking"
      bordered: true
      onClicked: root.goToPhotos()
    }

    Text {
      textFormat: Text.PlainText
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignRight
      text: "Photos are never erased from the camera."
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
