import QtQuick
import Quickshell
import Quickshell.Io

// Headless half of OmaCanon. One instance for the whole shell: it notices the
// camera being plugged in, opens the window, runs the download and keeps the
// lists the window shows.
//
//   helpers/omacanonctl status | download | stop | days | day DATE
//                       trash | send (request on stdin) | albums | claude-tag
//                       webcam-off
//
// Every action is the helper with an argument list; nothing goes through a shell.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: (manifest && manifest.id) || "io.github.dankestrick.omacanon"

  function fileUrl(relative) {
    var url = Qt.resolvedUrl(relative).toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    return decodeURIComponent(url)
  }

  readonly property string cli: fileUrl("../helpers/omacanonctl")

  function ctl(seconds, args) {
    return ["timeout", "-k", "5", String(seconds), root.cli].concat(args)
  }

  property bool windowOpen: false
  property var status: ({})
  readonly property bool camera: !!(status && status.camera)
  readonly property bool webcam: !!(status && status.webcam)
  readonly property var job: status && status.job ? status.job : ({})
  readonly property bool downloading: downloadProcess.running
  property bool checkedOnce: false
  property int lastDone: 0
  property string notice: ""
  property bool noticeIsError: false

  property var days: []
  property string day: ""
  property var photos: []
  property bool loadingDay: false
  // Picked photos, path -> true. Kept across days until sent.
  property var picked: ({})
  readonly property int pickedCount: Object.keys(picked).length
  // Clean up: photos marked for the trash, path -> true.
  property var marked: ({})
  readonly property int markedCount: Object.keys(marked).length
  property bool sending: false
  property bool omarawOpen: false
  // Step 3: OmaRAW's albums, and what the last save did ({count, album, omaraw}).
  property var albums: []
  property bool loadingAlbums: false
  property var lastSaved: null
  // Claude tagging: queue and progress from the helper's status.
  readonly property bool claudeAvailable: !!(status && status.claudeAvailable)
  readonly property var claudeJob: status && status.claude ? status.claude : ({})
  readonly property bool claudeTagging: claudeProcess.running

  // ---------------------------------------------------------------------------
  // Camera plugged in / out
  // ---------------------------------------------------------------------------

  // udev tells us about USB changes, so nothing polls while the window is shut.
  Process {
    id: usbWatch
    command: ["udevadm", "monitor", "--udev", "--subsystem-match=usb"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        if (line.indexOf(" add ") >= 0 || line.indexOf(" remove ") >= 0) usbSettle.restart()
      }
    }
    onExited: usbWatchRestart.restart()
  }

  Timer {
    id: usbWatchRestart
    interval: 10000
    onTriggered: usbWatch.running = true
  }

  // A camera shows up as several USB events; act once it has settled.
  Timer {
    id: usbSettle
    interval: 1500
    onTriggered: root.refreshStatus()
  }

  Process {
    id: statusProcess
    command: root.ctl(10, ["status"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = ({})
        try {
          next = JSON.parse(String(text).trim() || "{}")
        } catch (ignore) {}
        var wasCamera = root.camera
        var oldDays = root.job && root.job.days ? root.job.days.join(",") : ""
        root.status = next
        if (root.checkedOnce && !wasCamera && root.camera) root.cameraArrived()
        // Photos still waiting for Claude (say the shell restarted): carry on.
        if (!root.checkedOnce && (root.claudeJob.queued || 0) > 0 && !root.claudeJob.running) root.startClaudeTag()
        root.checkedOnce = true
        var newDays = root.job && root.job.days ? root.job.days.join(",") : ""
        var done = root.job.done || 0
        // New day folders, or every 25 photos while a day fills up.
        if (newDays !== oldDays || Math.floor(done / 25) !== Math.floor(root.lastDone / 25)) {
          root.refreshDays()
          if (root.day !== "" && root.job.days && root.job.days.indexOf(root.day) >= 0) root.loadDay(root.day)
        }
        root.lastDone = done
      }
    }
  }

  function refreshStatus() {
    if (!statusProcess.running) statusProcess.running = true
  }

  Timer {
    // Quick while photos come over, slow while the window is just open.
    interval: root.downloading ? 1000 : 3000
    repeat: true
    running: root.downloading || root.windowOpen || root.claudeTagging
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Component.onCompleted: refreshStatus()

  // Plugged in: open the window and start bringing photos over.
  function cameraArrived() {
    if (root.shell && typeof root.shell.summon === "function")
      root.shell.summon(root.pluginId, JSON.stringify({ tab: "camera" }))
    if (!root.webcam) root.startDownload()
  }

  // ---------------------------------------------------------------------------
  // Download
  // ---------------------------------------------------------------------------

  Process {
    id: downloadProcess
    command: ["setpriv", "--pdeathsig", "TERM", root.cli, "download"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = null
        try {
          reply = JSON.parse(String(text).trim())
        } catch (ignore) {}
        // Step 1 already says how many came over; only a failure needs a line.
        if (reply && reply.ok) root.notice = ""
      }
    }
    stderr: SplitParser { onRead: function(line) {} }
    onExited: {
      root.refreshStatus()
      root.refreshDays()
      if (root.day !== "") root.loadDay(root.day)
    }
  }

  function startDownload() {
    if (downloadProcess.running) return
    root.notice = ""
    downloadProcess.running = true
    root.refreshStatus()
  }

  Process {
    id: stopProcess
    command: root.ctl(10, ["stop"])
    onExited: root.refreshStatus()
  }

  function stopDownload() {
    if (!stopProcess.running) stopProcess.running = true
  }

  Process {
    id: webcamProcess
    command: root.ctl(30, ["webcam-off"])
    onExited: {
      root.refreshStatus()
      webcamThenDownload.restart()
    }
  }

  // The webcam lets go of the camera a moment after it stops.
  Timer {
    id: webcamThenDownload
    interval: 3000
    onTriggered: root.startDownload()
  }

  function webcamOff() {
    if (!webcamProcess.running) webcamProcess.running = true
  }

  // ---------------------------------------------------------------------------
  // Days and photos on the PC
  // ---------------------------------------------------------------------------

  Process {
    id: daysProcess
    command: root.ctl(30, ["days"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.days = JSON.parse(String(text).trim()).days || []
        } catch (ignore) {}
        if (root.day === "" && root.days.length > 0) root.loadDay(root.days[0].date)
      }
    }
  }

  function refreshDays() {
    if (!daysProcess.running) daysProcess.running = true
  }

  Process {
    id: dayProcess
    property string wanted: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = null
        try {
          reply = JSON.parse(String(text).trim())
        } catch (ignore) {}
        if (reply && reply.ok && reply.date === root.day) root.photos = reply.photos || []
        root.loadingDay = false
        if (dayProcess.wanted !== "" && dayProcess.wanted !== root.day) {
          var next = dayProcess.wanted
          dayProcess.wanted = ""
          root.loadDay(next)
        }
      }
    }
  }

  function loadDay(date) {
    if (root.day !== date) root.photos = []
    root.day = date
    if (dayProcess.running) {
      dayProcess.wanted = date
      return
    }
    root.loadingDay = true
    dayProcess.wanted = ""
    dayProcess.command = root.ctl(600, ["day", date])
    dayProcess.running = true
  }

  function togglePick(path) {
    var next = ({})
    for (var k in root.picked) next[k] = true
    if (next[path]) delete next[path]
    else next[path] = true
    root.picked = next
  }

  function toggleMark(path) {
    var next = ({})
    for (var k in root.marked) next[k] = true
    if (next[path]) delete next[path]
    else next[path] = true
    root.marked = next
  }

  function markAll(on) {
    var next = ({})
    for (var k in root.marked) next[k] = true
    for (var i = 0; i < root.photos.length; i++) {
      if (on) next[root.photos[i].path] = true
      else delete next[root.photos[i].path]
    }
    root.marked = next
  }

  function trashMarked() {
    root.trash(Object.keys(root.marked))
  }

  function pickAll(on) {
    var next = ({})
    for (var k in root.picked) next[k] = true
    for (var i = 0; i < root.photos.length; i++) {
      var p = root.photos[i]
      if (p.sent) continue
      if (on) next[p.path] = true
      else delete next[p.path]
    }
    root.picked = next
  }

  // ---------------------------------------------------------------------------
  // Trash and Send: paths go on stdin, never on the command line
  // ---------------------------------------------------------------------------

  Process {
    id: trashProcess
    property string payload: ""
    stdinEnabled: true
    onStarted: {
      write(payload + "\n")
      stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = null
        try {
          reply = JSON.parse(String(text).trim())
        } catch (ignore) {}
        root.notice = reply && reply.ok
          ? (reply.trashed === 1 ? "1 photo moved to the trash." : reply.trashed + " photos moved to the trash.")
            + " Changed your mind? They're in the Trash in the file manager."
          : (reply && reply.error ? String(reply.error) : "That didn't go to the trash.")
        root.noticeIsError = !(reply && reply.ok)
      }
    }
    onExited: {
      stdinEnabled = true
      root.refreshDays()
      if (root.day !== "") root.loadDay(root.day)
    }
  }

  function trash(paths) {
    if (trashProcess.running || paths.length === 0) return
    var next = ({})
    for (var k in root.picked) if (paths.indexOf(k) < 0) next[k] = true
    root.picked = next
    var left = ({})
    for (var m in root.marked) if (paths.indexOf(m) < 0) left[m] = true
    root.marked = left
    trashProcess.payload = JSON.stringify(paths)
    trashProcess.command = root.ctl(60, ["trash"])
    trashProcess.running = true
  }

  Process {
    id: sendProcess
    property string payload: ""
    stdinEnabled: true
    onStarted: {
      write(payload + "\n")
      stdinEnabled = false
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = null
        try {
          reply = JSON.parse(String(text).trim())
        } catch (ignore) {}
        root.omarawOpen = !!(reply && reply.omarawOpen)
        if (reply && reply.ok) {
          root.lastSaved = { count: (reply.sent || 0) + (reply.already || 0), album: reply.album || "", omaraw: true,
                             claude: (reply.claude || 0) > 0 }
          if ((reply.claude || 0) > 0) root.startClaudeTag()
          root.picked = ({})
          root.notice = ""
          root.noticeIsError = false
        } else {
          root.notice = reply && reply.error ? String(reply.error) : "OmaRAW didn't take them."
          root.noticeIsError = true
        }
      }
    }
    onExited: {
      stdinEnabled = true
      root.sending = false
      root.refreshDays()
      root.refreshAlbums()
      if (root.day !== "") root.loadDay(root.day)
    }
  }

  function sendPicked(album, claude) {
    if (sendProcess.running || root.pickedCount === 0) return
    root.sending = true
    root.notice = ""
    root.lastSaved = null
    sendProcess.payload = JSON.stringify({ paths: Object.keys(root.picked), album: album || "", claude: !!claude })
    sendProcess.command = root.ctl(3600, ["send"])
    sendProcess.running = true
  }

  // Folder only: the photos are already in Pictures/Canon, so this just
  // finishes the round and clears the picks.
  function keepInFolder() {
    root.lastSaved = { count: root.pickedCount, album: "", omaraw: false }
    root.picked = ({})
    root.notice = ""
  }

  function startOver() {
    root.lastSaved = null
  }

  Process {
    id: albumsProcess
    command: root.ctl(60, ["albums"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = null
        try {
          reply = JSON.parse(String(text).trim())
        } catch (ignore) {}
        root.omarawOpen = !!(reply && reply.omarawOpen)
        if (reply && reply.ok) root.albums = reply.albums || []
      }
    }
    onExited: root.loadingAlbums = false
  }

  function refreshAlbums() {
    if (albumsProcess.running) return
    root.loadingAlbums = true
    albumsProcess.running = true
  }

  // Claude looks at the photos in the background; the window can be closed.
  Process {
    id: claudeProcess
    command: ["setpriv", "--pdeathsig", "TERM", root.cli, "claude-tag"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var reply = null
        try {
          reply = JSON.parse(String(text).trim())
        } catch (ignore) {}
        if (reply && !reply.ok && reply.error) {
          root.notice = "Claude tagging stopped: " + String(reply.error)
          root.noticeIsError = true
        }
      }
    }
    stderr: SplitParser { onRead: function(line) {} }
    onExited: root.refreshStatus()
  }

  function startClaudeTag() {
    if (claudeProcess.running) return
    claudeProcess.running = true
    root.refreshStatus()
  }

  // The window floats, so the helper opens these floating on top of it.
  function openOmaraw() {
    Quickshell.execDetached([root.cli, "open", "omaraw"])
  }

  function openFolder(path) {
    Quickshell.execDetached([root.cli, "open", path || ""])
  }
}
