import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import qs.Commons
import "Toml.js" as Toml

// Notification server, popup deck and persistent history for the Omarchy shell.
//
// The service is the single owner of org.freedesktop.Notifications while the
// built-in omarchy.notifications plugin is disabled. The bar widget reads this
// object directly through bar.shell.serviceFor(pluginId), so popups, badge,
// panel and CLI all share one state.
Item {
  id: service

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginId: String(manifest && manifest.id ? manifest.id : "jovibe.notify-center")
  readonly property string configDir: home + "/.config/omarchy-notify-center"
  readonly property string configPath: configDir + "/config.toml"
  readonly property string stateDir: home + "/.local/state/omarchy-notify-center"
  readonly property string historyPath: stateDir + "/history.json"
  readonly property string pluginDir: home + "/.config/omarchy/plugins/" + pluginId
  readonly property string focusHelper: pluginDir + "/bin/notify-center-focus"

  // ---------------------------------------------------------------- config

  property var config: ({})
  property bool configLoaded: false
  property string position: "right"
  property int timeout: 5
  property int criticalTimeout: 5
  property bool stickyCritical: false
  property int maxVisible: 3
  property int maxStack: 50
  property int historyLimit: 200
  property bool animation: true
  property int cardWidth: 380
  property bool dnd: false
  property var muted: ({})
  property var mutedList: []
  property var devices: []
  property bool deviceScanPending: false
  property bool devicesInitialized: false
  property var deviceNotifyQueue: []
  property bool deviceNotifyRunning: false

  readonly property string defaultConfigText:
    "# omarchy-notify-center configuration.\n" +
    "# Changes reload live; no shell restart needed.\n\n" +
    "[general]\n" +
    "# Popup anchor: \"left\", \"center\", or \"right\".\n" +
    "position = \"right\"\n" +
    "# Seconds a normal popup stays on screen (0 = never expire).\n" +
    "timeout = 5\n" +
    "# Seconds a critical popup stays on screen.\n" +
    "critical_timeout = 5\n" +
    "# Keep critical popups until dismissed.\n" +
    "sticky_critical = false\n" +
    "# Cards visible at once (1 = one pill, 3 = stacked deck).\n" +
    "max_visible = 3\n" +
    "# Cards kept in the live queue before the oldest is dropped.\n" +
    "max_stack = 50\n" +
    "# Notifications kept in persistent history.\n" +
    "history_limit = 200\n" +
    "# Fade/slide animation.\n" +
    "animation = true\n" +
    "# Popup width in pixels.\n" +
    "width = 380\n" +
    "# Do Not Disturb. Also toggle with the bar bell's right click.\n" +
    "dnd = false\n\n" +
    "[mute]\n" +
    "# Apps whose notifications are suppressed.\n" +
    "apps = []\n"

  function asInt(value, fallback) {
    var n = Number(value)
    return isFinite(n) ? Math.round(n) : fallback
  }

  function asBool(value, fallback) {
    if (value === true || value === false) return value
    var s = String(value || "").toLowerCase()
    if (s === "true" || s === "1" || s === "yes" || s === "on") return true
    if (s === "false" || s === "0" || s === "no" || s === "off") return false
    return fallback
  }

  function normalizePosition(value) {
    var s = String(value || "").toLowerCase()
    return (s === "left" || s === "right" || s === "center") ? s : "center"
  }

  function normalizeAppKey(value) {
    return String(value || "").trim().toLowerCase()
  }

  function listMuted(map) {
    var out = []
    for (var key in map) if (map[key]) out.push(key)
    out.sort()
    return out
  }

  function applyConfig(raw) {
    var parsed = Toml.parse(raw && String(raw).trim().length > 0 ? raw : defaultConfigText)
    config = parsed
    position = normalizePosition(parsed["general.position"])
    timeout = Math.max(0, asInt(parsed["general.timeout"], 5))
    criticalTimeout = Math.max(0, asInt(parsed["general.critical_timeout"], 5))
    stickyCritical = asBool(parsed["general.sticky_critical"], false)
    maxVisible = Math.max(1, Math.min(3, asInt(parsed["general.max_visible"], 3)))
    maxStack = Math.max(1, asInt(parsed["general.max_stack"], 50))
    historyLimit = Math.max(1, Math.min(2000, asInt(parsed["general.history_limit"], 200)))
    animation = asBool(parsed["general.animation"], true)
    cardWidth = Math.max(240, Math.min(900, asInt(parsed["general.width"], 380)))
    dnd = asBool(parsed["general.dnd"], false)

    var list = parsed["mute.apps"]
    var map = ({})
    if (Array.isArray(list)) {
      for (var i = 0; i < list.length; i++) {
        var key = normalizeAppKey(list[i])
        if (key.length > 0) map[key] = true
      }
    }
    muted = map
    mutedList = listMuted(map)
    configLoaded = true

    while (popupModel.count > maxStack) popupModel.remove(popupModel.count - 1)
    trimHistory()
    updateDepths()
  }

  function writeConfigValue(section, key, literal) {
    if (!configLoaded) return
    var raw = configFile.text() || defaultConfigText
    var header = "[" + section + "]"
    var start = raw.indexOf(header)
    if (start < 0) {
      raw = raw.replace(/\s*$/, "\n") + "\n" + header + "\n" + key + " = " + literal + "\n"
    } else {
      var bodyStart = raw.indexOf("\n", start)
      if (bodyStart < 0) bodyStart = raw.length
      else bodyStart += 1
      var next = raw.indexOf("\n[", bodyStart)
      var sectionText = next < 0 ? raw.slice(bodyStart) : raw.slice(bodyStart, next)
      var re = new RegExp("^(\\s*" + key + "\\s*=\\s*).*$", "m")
      if (re.test(sectionText)) {
        sectionText = sectionText.replace(re, "$1" + literal)
      } else {
        sectionText = key + " = " + literal + "\n" + sectionText
      }
      raw = raw.slice(0, bodyStart) + sectionText + (next < 0 ? "" : raw.slice(next))
    }
    configWriter.setText(raw)
  }

  function persistString(section, key, value) {
    writeConfigValue(section, key, JSON.stringify(String(value)))
  }

  function persistBool(section, key, value) {
    writeConfigValue(section, key, value ? "true" : "false")
  }

  function persistNumber(section, key, value) {
    writeConfigValue(section, key, String(Math.round(Number(value) || 0)))
  }

  function persistMuted() {
    var list = []
    for (var i = 0; i < mutedList.length; i++) list.push(mutedList[i])
    writeConfigValue("mute", "apps", JSON.stringify(list))
  }

  function setPosition(value, persist) {
    position = normalizePosition(value)
    if (persist === true) persistString("general", "position", position)
    return position
  }

  function setDnd(value) {
    dnd = asBool(value, false)
    persistBool("general", "dnd", dnd)
    if (dnd) dismissAll()
    return dnd ? "on" : "off"
  }

  function toggleDnd() {
    return setDnd(!dnd)
  }

  function setTimeout(value) {
    timeout = Math.max(0, asInt(value, timeout))
    persistNumber("general", "timeout", timeout)
    return timeout
  }

  function setCriticalTimeout(value) {
    criticalTimeout = Math.max(0, asInt(value, criticalTimeout))
    persistNumber("general", "critical_timeout", criticalTimeout)
    return criticalTimeout
  }

  function setMaxVisible(value) {
    maxVisible = Math.max(1, Math.min(3, asInt(value, maxVisible)))
    persistNumber("general", "max_visible", maxVisible)
    updateDepths()
    return maxVisible
  }

  function setAnimation(value) {
    animation = asBool(value, animation)
    persistBool("general", "animation", animation)
    return animation
  }

  function setStickyCritical(value) {
    stickyCritical = asBool(value, stickyCritical)
    persistBool("general", "sticky_critical", stickyCritical)
    return stickyCritical
  }

  function isMuted(appName) {
    return !!muted[normalizeAppKey(appName)]
  }

  function muteApp(appName) {
    var key = normalizeAppKey(appName)
    if (!key) return "none"
    var next = ({})
    for (var k in muted) next[k] = muted[k]
    next[key] = true
    muted = next
    mutedList = listMuted(next)
    persistMuted()
    for (var i = popupModel.count - 1; i >= 0; i--) {
      if (normalizeAppKey(popupModel.get(i).app) === key) dismissByNotifId(Number(popupModel.get(i).notifId))
    }
    return "ok"
  }

  function unmuteApp(appName) {
    var key = normalizeAppKey(appName)
    if (!muted[key]) return "none"
    var next = ({})
    for (var k in muted) if (k !== key) next[k] = muted[k]
    muted = next
    mutedList = listMuted(next)
    persistMuted()
    return "ok"
  }

  // --------------------------------------------------------------- popups

  property real frontCardHeight: 0
  readonly property real deckPeek: Style.space(9)
  property var liveRefs: ({})
  property var liveKeyByNotifId: ({})
  property int popupSeq: 0

  ListModel { id: popupModel }

  readonly property int popupCount: popupModel.count

  readonly property string barPosition: {
    if (shell && shell.barConfig) return String(shell.barConfig.position || "top")
    return "top"
  }
  readonly property real topMargin: Style.gapsOut + (barPosition === "top" ? Style.bar.sizeHorizontal + Style.gapsOut : 0)
  readonly property real sideMargin: Style.gapsOut * 2

  readonly property var focusedScreen: {
    var monitor = Hyprland.focusedMonitor
    if (monitor) {
      for (var i = 0; i < Quickshell.screens.length; i++) {
        if (Quickshell.screens[i].name === monitor.name) return Quickshell.screens[i]
      }
    }
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  function durationFor(urgency, expireTimeout) {
    var requested = Number(expireTimeout || 0)
    if (isFinite(requested) && requested > 0) return Math.round(requested)
    if (Number(urgency) === 2) return stickyCritical ? 0 : criticalTimeout * 1000
    return timeout * 1000
  }

  function truncate(value, limit) {
    var text = String(value || "")
    if (text.length <= limit) return text
    return text.slice(0, Math.max(0, limit - 1)) + "\u2026"
  }

  function decodeEntities(text) {
    return String(text || "")
      .replace(/&nbsp;/gi, " ")
      .replace(/&lt;/gi, "<")
      .replace(/&gt;/gi, ">")
      .replace(/&quot;/gi, '"')
      .replace(/&#39;/g, "'")
      .replace(/&#x27;/gi, "'")
      .replace(/&amp;/gi, "&")
  }

  function stripMarkup(value, limit) {
    var text = String(value || "")
    text = text.replace(/<img\b[^>]*>/gi, "")
    text = text.replace(/<\s*br\s*\/?>/gi, "\n")
    text = text.replace(/<\/\s*(p|div|li|tr)\s*>/gi, "\n")
    text = text.replace(/<[^>]*>/g, "")
    text = decodeEntities(text)
    return truncate(text.replace(/\r\n|\r/g, "\n").replace(/\n{3,}/g, "\n\n").trim(), limit || 4000)
  }

  function hintString(notification, names) {
    try {
      var hints = notification.hints
      if (!hints) return ""
      for (var i = 0; i < names.length; i++) {
        var value = hints[names[i]]
        if (value !== undefined && value !== null && String(value).length > 0) return String(value)
      }
    } catch (e) {}
    return ""
  }

  function newKey(timestamp) {
    popupSeq += 1
    return String(timestamp) + "-" + String(popupSeq) + "-" + Math.floor(Math.random() * 100000)
  }

  function actionsOf(notification) {
    var actions = []
    try {
      if (notification.actions) {
        for (var i = 0; i < notification.actions.length; i++) {
          var a = notification.actions[i]
          actions.push({
            identifier: String(a.identifier || ""),
            text: String(a.text || "")
          })
        }
      }
    } catch (e) {}
    return actions
  }

  function snapshotOf(notification, existingKey, existingTimestamp) {
    var timestamp = existingTimestamp ? Number(existingTimestamp) : Date.now()
    var key = existingKey && String(existingKey).length > 0 ? String(existingKey) : newKey(timestamp)
    var image = ""
    try { image = String(notification.image || "") } catch (e) {}
    var desktopEntry = ""
    try { desktopEntry = String(notification.desktopEntry || "") } catch (e) {}
    var actions = actionsOf(notification)
    var url = hintString(notification, ["x-url", "url", "x-omarchy-url"])
    return {
      uid: key,
      key: key,
      notifId: Number(notification.id || 0),
      app: truncate(String(notification.appName || "Notification"), 120),
      appIcon: String(notification.appIcon || ""),
      summary: stripMarkup(notification.summary, 400),
      body: stripMarkup(notification.body, 4000),
      image: image,
      urgency: Number(notification.urgency || 0),
      expireTimeout: Number(notification.expireTimeout || 0),
      timestamp: timestamp,
      desktopEntry: desktopEntry,
      actionsJson: JSON.stringify(actions),
      transient: notification.transient === true,
      url: url,
      depth: 0,
      dismissing: false
    }
  }

  function indexOfNotif(id) {
    for (var i = 0; i < popupModel.count; i++) {
      if (Number(popupModel.get(i).notifId) === Number(id)) return i
    }
    return -1
  }

  function rowIndexForUid(uid) {
    for (var i = 0; i < popupModel.count; i++) {
      if (String(popupModel.get(i).uid) === String(uid)) return i
    }
    return -1
  }

  function handleNotification(notification) {
    notification.tracked = true
    var appName = String(notification.appName || "Notification")
    if (isMuted(appName)) {
      try { notification.dismiss() } catch (e) {}
      notification.tracked = false
      return
    }

    var id = Number(notification.id || 0)
    var index = indexOfNotif(id)
    var existingKey = index >= 0 ? String(popupModel.get(index).uid) : String(liveKeyByNotifId[id] || "")
    var existingTimestamp = index >= 0 ? Number(popupModel.get(index).timestamp) : 0
    var snapshot = snapshotOf(notification, existingKey, existingTimestamp)

    var isNewRef = liveRefs[id] !== notification
    liveRefs[id] = notification
    liveKeyByNotifId[id] = snapshot.uid
    if (isNewRef) {
      // A replaces_id update reuses the object; a sender close on an old
      // generation must not remove a newer notification that took the id.
      notification.closed.connect(function() {
        if (service.liveRefs[id] === notification) service.onNotificationClosed(id)
      })
      var refresh = function() {
        if (service.liveRefs[id] === notification) service.refreshNotification(id)
      }
      notification.summaryChanged.connect(refresh)
      notification.bodyChanged.connect(refresh)
      notification.appNameChanged.connect(refresh)
      notification.appIconChanged.connect(refresh)
      notification.urgencyChanged.connect(refresh)
      notification.imageChanged.connect(refresh)
      notification.desktopEntryChanged.connect(refresh)
      notification.actionsChanged.connect(refresh)
      notification.hintsChanged.connect(refresh)
    }

    if (dnd) {
      // DND still records what was missed; the reader sees it in the center.
      if (existingKey) updateHistoryEntry(existingKey, snapshot, { read: false, silenced: true })
      else addHistory(snapshot, false, true)
      if (index >= 0) removeRow(id)
      try { notification.dismiss() } catch (e) {}
      try { notification.tracked = false } catch (e) {}
      return
    }

    if (index >= 0) {
      popupModel.set(index, snapshot)
      updateHistoryEntry(snapshot.uid, snapshot, null)
      return
    }

    addHistory(snapshot, false, false)
    popupModel.insert(0, snapshot)
    while (popupModel.count > maxStack) {
      var last = popupModel.count - 1
      var oldId = Number(popupModel.get(last).notifId)
      popupModel.remove(last)
      releaseLive(oldId)
    }
    updateDepths()
  }

  function refreshNotification(id) {
    var index = indexOfNotif(id)
    var ref = liveRefs[id]
    if (index < 0 || !ref) return
    var row = popupModel.get(index)
    var snapshot = snapshotOf(ref, row.uid, row.timestamp)
    snapshot.depth = Number(row.depth || 0)
    snapshot.dismissing = row.dismissing === true
    if (JSON.stringify(snapshot) === JSON.stringify(row)) return
    popupModel.set(index, snapshot)
    updateHistoryEntry(snapshot.uid, snapshot, null)
  }

  function updateDepths() {
    for (var i = 0; i < popupModel.count; i++) popupModel.setProperty(i, "depth", Math.min(i, 99))
  }

  function onNotificationClosed(id) {
    var index = indexOfNotif(id)
    if (index >= 0) {
      popupModel.setProperty(index, "dismissing", true)
      if (!animation) removeRow(id)
    }
    releaseLive(id)
  }

  function releaseLive(id) {
    var ref = liveRefs[id]
    delete liveRefs[id]
    delete liveKeyByNotifId[id]
    if (!ref) return
    try { ref.tracked = false } catch (e) {}
  }

  function removeRow(id) {
    var index = indexOfNotif(id)
    if (index >= 0) popupModel.remove(index)
    releaseLive(id)
    updateDepths()
    frontCardHeight = 0
  }

  function dismissByNotifId(id) {
    var ref = liveRefs[id]
    if (!ref) { removeRow(id); return "ok" }
    try { ref.dismiss() } catch (e) { removeRow(id) }
    return "ok"
  }

  function expireByNotifId(id) {
    var ref = liveRefs[id]
    if (!ref) { removeRow(id); return "ok" }
    try { ref.expire() } catch (e) { removeRow(id) }
    return "ok"
  }

  function invokeActionByNotifId(id, identifier) {
    var ref = liveRefs[id]
    if (ref && ref.actions) {
      for (var i = 0; i < ref.actions.length; i++) {
        var action = ref.actions[i]
        if (action && String(action.identifier) === String(identifier)) {
          try { action.invoke() } catch (e) { console.warn("notify-center: action failed:", e) }
          dismissByNotifId(id)
          return "ok"
        }
      }
    }
    dismissByNotifId(id)
    return "none"
  }

  function invokeByNotifId(id) {
    var index = indexOfNotif(id)
    if (index < 0) return "none"
    var entry = popupModel.get(index)
    var ref = liveRefs[id]
    var invoked = false
    if (ref && ref.actions) {
      for (var i = 0; i < ref.actions.length; i++) {
        var action = ref.actions[i]
        if (action && String(action.identifier) === "default") {
          try {
            action.invoke()
            invoked = true
          } catch (e) {
            console.warn("notify-center: default action failed:", e)
          }
          break
        }
      }
    }
    if (!invoked) focusSource(entry)
    dismissByNotifId(id)
    return invoked ? "action" : "focus"
  }

  function focusSource(entry) {
    if (!entry) return
    focusProc.command = ["bash", focusHelper, String(entry.app || ""), String(entry.desktopEntry || ""), String(entry.url || "")]
    focusProc.running = true
  }

  Process { id: focusProc; running: false }

  // -------------------------------------------------------------- peripherals

  function refreshDevices() {
    if (deviceScan.running) {
      deviceScanPending = true
      return
    }
    deviceScan.running = true
  }

  function deviceGlyph(kind) {
    switch (String(kind || "")) {
      case "mouse": return "\uF245"
      case "keyboard": return "\uF11C"
      case "audio": return "\uF025"
      case "drive": return "\uF0A0"
      case "printer": return "\uF02F"
      case "phone": return "\uF10B"
      case "monitor": return "\uF108"
      case "device": return "\uF287"
      default: return "\uF128"
    }
  }

  function deviceKindLabel(kind) {
    switch (String(kind || "")) {
      case "mouse": return "Mouse"
      case "keyboard": return "Keyboard"
      case "audio": return "Audio device"
      case "drive": return "Drive"
      case "printer": return "Printer"
      case "phone": return "Phone"
      case "monitor": return "External monitor"
      case "device": return "USB device"
      default: return "Unknown USB device"
    }
  }

  function deviceNotificationTitle(device) {
    switch (String(device && device.kind || "")) {
      case "mouse": return "USB mouse connected"
      case "keyboard": return "USB keyboard connected"
      case "audio": return "USB audio device connected"
      case "drive": return "USB drive connected"
      case "printer": return "Printer connected"
      case "phone": return "Phone connected"
      case "monitor": return "External monitor connected"
      case "device": return "USB device connected"
      default: return "USB device connected"
    }
  }

  function deviceNotificationBody(device) {
    var name = String(device && device.name || "").trim()
    if (name.length === 0) name = deviceKindLabel(device ? device.kind : "")
    var detail = String(device && device.detail || "").trim()
    if (detail.length > 0 && detail.toLowerCase() !== name.toLowerCase()) name += "\n" + detail
    var action = String(device && device.action || "")
    if (action === "files") name += "\nClick to open Files"
    else if (action === "printers") name += "\nClick to open Print Settings"
    else if (action === "display") name += "\nClick to open Monitor Settings"
    return name
  }

  function deviceNotificationCommand(device) {
    var command = [
      "omarchy-notification-send",
      "--app-name", "Devices",
      "-g", deviceGlyph(device.kind),
      "-u", "low",
      deviceNotificationTitle(device),
      deviceNotificationBody(device)
    ]
    var action = String(device.action || "")
    if (action === "files") command = command.concat(["--exec", "omarchy-launch-nautilus"])
    else if (action === "printers") command = command.concat(["--exec", "system-config-printer"])
    else if (action === "display") command = command.concat(["--exec", "omarchy-menu", "summon", "setup.monitors"])
    return command
  }

  function drainDeviceNotifications() {
    if (deviceNotifyRunning || deviceNotifyQueue.length === 0) return
    var device = deviceNotifyQueue[0]
    deviceNotifyQueue = deviceNotifyQueue.slice(1)
    deviceNotify.command = deviceNotificationCommand(device)
    deviceNotifyRunning = true
    deviceNotify.running = true
  }

  function queueDeviceNotification(device) {
    if (!device) return
    deviceNotifyQueue = deviceNotifyQueue.concat([device])
    drainDeviceNotifications()
  }

  function applyDeviceScan(scanned) {
    if (devicesInitialized) {
      var known = ({})
      for (var i = 0; i < devices.length; i++) known[String(devices[i].id || "")] = true
      for (var j = 0; j < scanned.length; j++) {
        var device = scanned[j]
        if (!known[String(device.id || "")]) queueDeviceNotification(device)
      }
    }
    devices = scanned
    devicesInitialized = true
  }

  function openDevice(device) {
    if (!device) return
    var action = String(device.action || "")
    if (action === "files") {
      Util.execDetached(
        'if command -v omarchy-launch-nautilus >/dev/null 2>&1; then exec omarchy-launch-nautilus; ' +
        'elif command -v nautilus >/dev/null 2>&1; then exec nautilus --new-window; ' +
        'elif command -v xdg-open >/dev/null 2>&1; then exec xdg-open "$HOME"; fi'
      )
    } else if (action === "printers") {
      Util.execDetached(
        'if command -v system-config-printer >/dev/null 2>&1; then exec system-config-printer; ' +
        'elif command -v gnome-control-center >/dev/null 2>&1; then exec gnome-control-center printers; ' +
        'elif command -v systemsettings >/dev/null 2>&1; then exec systemsettings kcm_printer_manager; ' +
        'elif command -v xdg-open >/dev/null 2>&1; then exec xdg-open http://localhost:631/; fi'
      )
    } else if (action === "display") {
      Util.execDetached(
        'if command -v omarchy-menu >/dev/null 2>&1; then exec omarchy-menu summon setup.monitors; ' +
        'elif command -v omarchy-launch-config-editor >/dev/null 2>&1; then exec omarchy-launch-config-editor "$HOME/.config/hypr/monitors.lua"; fi'
      )
    }
  }

  function dismissAll() {
    var ids = []
    for (var i = 0; i < popupModel.count; i++) ids.push(Number(popupModel.get(i).notifId))
    for (var j = 0; j < ids.length; j++) dismissByNotifId(ids[j])
    return "ok"
  }

  // -------------------------------------------------------------- history

  property var history: []
  property int unreadCount: 0
  property bool historyLoaded: false

  function historyLimitTrim() {
    return historyLimit
  }

  function cloneEntry(entry) {
    var out = {}
    for (var k in entry) out[k] = entry[k]
    return out
  }

  function displayFields(snapshot) {
    return {
      key: snapshot.key,
      uid: snapshot.uid,
      notifId: snapshot.notifId,
      app: snapshot.app,
      appIcon: snapshot.appIcon,
      summary: snapshot.summary,
      body: snapshot.body,
      image: snapshot.image,
      urgency: snapshot.urgency,
      timestamp: snapshot.timestamp,
      desktopEntry: snapshot.desktopEntry,
      actionsJson: snapshot.actionsJson,
      transient: snapshot.transient,
      url: snapshot.url
    }
  }

  function addHistory(snapshot, read, silenced) {
    if (snapshot.transient) return
    var entry = displayFields(snapshot)
    entry.read = !!read
    entry.silenced = !!silenced
    var next = [entry]
    for (var i = 0; i < history.length; i++) {
      if (String(history[i].key) !== String(entry.key)) next.push(history[i])
    }
    history = next.slice(0, historyLimit)
    recalcUnread()
    persistHistory()
  }

  function updateHistoryEntry(key, snapshot, overrides) {
    if (!key || snapshot.transient) return
    var fields = displayFields(snapshot)
    var next = []
    var found = false
    for (var i = 0; i < history.length; i++) {
      var entry = history[i]
      if (String(entry.key) === String(key)) {
        var merged = cloneEntry(entry)
        for (var k in fields) merged[k] = fields[k]
        if (overrides) for (var o in overrides) merged[o] = overrides[o]
        next.push(merged)
        found = true
      } else {
        next.push(entry)
      }
    }
    if (!found) {
      var fresh = fields
      fresh.key = key
      fresh.uid = key
      fresh.read = overrides && overrides.read === true
      fresh.silenced = overrides && overrides.silenced === true
      next.unshift(fresh)
    }
    history = next.slice(0, historyLimit)
    recalcUnread()
    persistHistory()
  }

  function recalcUnread() {
    var n = 0
    for (var i = 0; i < history.length; i++) if (!history[i].read) n += 1
    unreadCount = n
  }

  function trimHistory() {
    if (history.length > historyLimit) {
      history = history.slice(0, historyLimit)
      recalcUnread()
      persistHistory()
    }
  }

  function loadHistory(raw) {
    if (historyLoaded) return
    var parsed = []
    try {
      var value = JSON.parse(String(raw || "").trim())
      if (Array.isArray(value)) parsed = value
      else if (value && Array.isArray(value.entries)) parsed = value.entries
    } catch (e) {
      console.warn("notify-center: history parse failed:", e)
    }

    var merged = []
    var seen = ({})
    function push(entry) {
      if (!entry || typeof entry !== "object") return
      var key = String(entry.key || entry.uid || "")
      if (!key) {
        key = newKey(Number(entry.timestamp) || Date.now())
        entry.key = key
      }
      if (seen[key]) return
      seen[key] = true
      var out = cloneEntry(entry)
      out.key = key
      out.uid = key
      out.app = String(out.app || "Notification")
      out.summary = String(out.summary || "")
      out.body = String(out.body || "")
      out.timestamp = Number(out.timestamp || 0)
      out.read = out.read === true
      out.silenced = out.silenced === true
      merged.push(out)
    }

    // Anything already received while the file was loading is newer.
    for (var i = 0; i < history.length; i++) push(history[i])
    for (var j = 0; j < parsed.length; j++) push(parsed[j])
    merged.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
    history = merged.slice(0, historyLimit)
    historyLoaded = true
    recalcUnread()
    persistHistory()
  }

  // Set once the state directory is confirmed private (0700).
  property bool stateSecured: false

  function persistHistory() {
    if (!historyLoaded || !stateSecured) return
    historyFile.setText(JSON.stringify({ version: 1, entries: history }) + "\n")
  }

  function findHistory(key) {
    for (var i = 0; i < history.length; i++) {
      if (String(history[i].key) === String(key)) return history[i]
    }
    return null
  }

  function markAllRead() {
    if (history.length === 0) return "ok"
    var next = []
    for (var i = 0; i < history.length; i++) {
      var entry = cloneEntry(history[i])
      entry.read = true
      next.push(entry)
    }
    history = next
    unreadCount = 0
    persistHistory()
    return "ok"
  }

  function markRead(key) {
    var next = []
    var changed = false
    for (var i = 0; i < history.length; i++) {
      var entry = history[i]
      if (String(entry.key) === String(key) && !entry.read) {
        var copy = cloneEntry(entry)
        copy.read = true
        next.push(copy)
        changed = true
      } else {
        next.push(entry)
      }
    }
    if (changed) {
      history = next
      recalcUnread()
      persistHistory()
    }
    return "ok"
  }

  function removeHistory(key) {
    var index = rowIndexForUid(key)
    if (index >= 0) dismissByNotifId(Number(popupModel.get(index).notifId))
    var next = []
    for (var i = 0; i < history.length; i++) {
      if (String(history[i].key) !== String(key)) next.push(history[i])
    }
    history = next
    recalcUnread()
    persistHistory()
    return "ok"
  }

  function clearHistory() {
    history = []
    unreadCount = 0
    persistHistory()
    return "ok"
  }

  function invokeHistory(key) {
    var entry = findHistory(key)
    if (!entry) return "none"
    var index = rowIndexForUid(key)
    if (index >= 0) invokeByNotifId(Number(popupModel.get(index).notifId))
    else focusSource(entry)
    markRead(key)
    return "ok"
  }

  function invokeHistoryAction(key, identifier) {
    var index = rowIndexForUid(key)
    if (index >= 0) return invokeActionByNotifId(Number(popupModel.get(index).notifId), identifier)
    var entry = findHistory(key)
    if (entry && identifier === "default") focusSource(entry)
    markRead(key)
    return "ok"
  }

  // ---------------------------------------------------------- panel requests

  signal panelRequested(string mode)

  property var panelRequest: ({ counter: 0, mode: "toggle" })

  function requestPanel(mode) {
    var requested = String(mode || "toggle")
    panelRequest = {
      counter: Number(panelRequest.counter || 0) + 1,
      mode: requested
    }
    panelRequested(requested)
    return "ok"
  }

  // ------------------------------------------------------------ lifecycle

  Component.onCompleted: {
    ensureDirs.running = true
    Qt.callLater(function() {
      configFile.reload()
      service.refreshDevices()
    })
  }

  Process {
    id: ensureDirs
    // History holds private notification content: keep the state directory
    // and file owner-only, and tighten anything left over from older installs.
    command: ["sh", "-c",
      "umask 077; mkdir -p \"$1\" \"$2\" && chmod 700 \"$2\" && " +
      "{ [ ! -e \"$3\" ] || chmod 600 \"$3\"; }",
      "notify-center", service.configDir, service.stateDir, service.historyPath]
    running: false
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        console.warn("notify-center: could not secure state directory; history disabled")
        return
      }
      service.stateSecured = true
      historyFile.reload()
    }
  }

  Process {
    id: deviceScan
    command: ["bash", service.pluginDir + "/bin/notify-center-devices"]
    running: false
    stdout: StdioCollector {
      id: deviceOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        try {
          var parsed = JSON.parse(String(deviceOutput.text || "[]"))
          if (Array.isArray(parsed)) service.applyDeviceScan(parsed)
        } catch (e) {
          console.warn("notify-center: could not parse devices:", e)
        }
      }
      if (service.deviceScanPending) {
        service.deviceScanPending = false
        service.refreshDevices()
      }
    }
  }

  Process {
    id: deviceNotify
    running: false
    onExited: function(exitCode) {
      service.deviceNotifyRunning = false
      service.drainDeviceNotifications()
    }
  }

  Timer {
    interval: 5000
    repeat: true
    running: true
    onTriggered: service.refreshDevices()
  }

  FileView {
    id: configFile
    path: service.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: service.applyConfig(text())
    onFileChanged: reload()
    onLoadFailed: {
      service.configLoaded = false
      configWriter.setText(service.defaultConfigText)
      service.applyConfig(service.defaultConfigText)
    }
  }

  FileView {
    id: configWriter
    path: service.configPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: historyFile
    path: service.historyPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadHistory(text())
    onLoadFailed: service.loadHistory("")
    onSaved: secureHistory.running = true
  }

  Process {
    id: secureHistory
    command: ["chmod", "600", service.historyPath]
    running: false
  }

  NotificationServer {
    id: server
    keepOnReload: false
    imageSupported: true
    actionsSupported: true
    bodyMarkupSupported: true
    bodyHyperlinksSupported: true
    bodyImagesSupported: false
    persistenceSupported: true

    onNotification: function(notification) {
      service.handleNotification(notification)
    }
  }

  // -------------------------------------------------------------- popup UI

  PanelWindow {
    id: popupWindow
    screen: service.focusedScreen
    visible: popupModel.count > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "omarchy-notify-center"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    mask: Region { item: popupColumn }

    Column {
      id: popupColumn
      spacing: Style.space(8)
      anchors.top: parent.top
      anchors.topMargin: service.topMargin
      anchors.horizontalCenter: service.position === "center" ? parent.horizontalCenter : undefined
      anchors.left: service.position === "left" ? parent.left : undefined
      anchors.leftMargin: service.position === "left" ? service.sideMargin : 0
      anchors.right: service.position === "right" ? parent.right : undefined
      anchors.rightMargin: service.position === "right" ? service.sideMargin : 0

      Item {
        id: deck
        width: Math.min(service.cardWidth, popupWindow.width - service.sideMargin * 2)
        height: service.frontCardHeight + service.deckPeek * Math.max(0, Math.min(popupModel.count, service.maxVisible) - 1)

        Repeater {
          model: popupModel

          delegate: Item {
            id: slot
            required property int index
            required property string uid
            required property int notifId
            required property string app
            required property string appIcon
            required property string summary
            required property string body
            required property string image
            required property int urgency
            required property double expireTimeout
            required property double timestamp
            required property string desktopEntry
            required property string actionsJson
            required property string url
            required property int depth
            required property bool dismissing

            width: deck.width
            height: cardHeight
            visible: depth < service.maxVisible
            y: depth * service.deckPeek
            z: 100 - depth
            scale: 1 - depth * 0.035
            opacity: depth === 0 ? 1.0 : (depth === 1 ? 0.55 : 0.30)
            transformOrigin: Item.Top

            property real cardHeight: card.implicitHeight
            property real remaining: 1.0
            property bool expired: false
            readonly property real lifetime: service.durationFor(slot.urgency, slot.expireTimeout)
            readonly property bool ticking: slot.lifetime > 0 && slot.depth === 0 && !card.hovered && !slot.dismissing && !slot.expired

            onSummaryChanged: slot.remaining = 1.0
            onBodyChanged: slot.remaining = 1.0
            onImageChanged: slot.remaining = 1.0
            onCardHeightChanged: if (slot.depth === 0) service.frontCardHeight = slot.cardHeight
            onDepthChanged: if (slot.depth === 0) service.frontCardHeight = slot.cardHeight
            Component.onCompleted: if (slot.depth === 0) service.frontCardHeight = slot.cardHeight

            Behavior on y {
              enabled: service.animation
              NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on scale {
              enabled: service.animation
              NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
              enabled: service.animation
              NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }

            Timer {
              interval: 50
              repeat: true
              running: slot.ticking
              onTriggered: {
                if (slot.lifetime <= 0 || slot.expired) return
                slot.remaining -= 50.0 / slot.lifetime
                if (slot.remaining <= 0) {
                  slot.remaining = 0
                  slot.expired = true
                  service.expireByNotifId(slot.notifId)
                }
              }
            }

            Timer {
              interval: 180
              running: slot.dismissing
              onTriggered: service.removeRow(slot.notifId)
            }

            NotificationCard {
              id: card
              width: slot.width
              app: slot.app
              appIcon: slot.appIcon
              summary: slot.summary
              body: slot.body
              image: slot.image
              urgency: slot.urgency
              timestamp: slot.timestamp
              actionsJson: slot.actionsJson
              dismissing: slot.dismissing
              animationEnabled: service.animation
              stackedView: true
              stackFront: slot.depth === 0
              fontFamily: Style.fontFamily

              onCloseRequested: service.dismissByNotifId(slot.notifId)
              onDismissRequested: service.dismissByNotifId(slot.notifId)
              onCardClicked: service.invokeByNotifId(slot.notifId)
              onActionInvoked: function(identifier) { service.invokeActionByNotifId(slot.notifId, identifier) }
              onMuteRequested: service.muteApp(slot.app)
              onSettingsRequested: service.requestPanel("settings")
            }
          }
        }
      }

      Rectangle {
        id: moreBadge
        visible: popupModel.count > service.maxVisible
        anchors.horizontalCenter: parent.horizontalCenter
        width: moreText.implicitWidth + Style.space(20)
        height: Style.space(26)
        radius: height / 2
        color: Color.notifications.background
        border.width: Math.max(1, Math.round(Style.space(1)))
        border.color: Util.alpha(Color.notifications.border, 0.55)

        Text {
          id: moreText
          anchors.centerIn: parent
          text: "+" + (popupModel.count - service.maxVisible) + " more"
          textFormat: Text.PlainText
          color: Color.notifications.countdown
          font.family: Style.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }
    }
  }

  // ------------------------------------------------------------------ IPC

  IpcHandler {
    target: "notify-center"

    function ping(): string { return "ok" }

    function status(): string {
      return JSON.stringify({
        version: "1.1.0",
        count: popupModel.count,
        history: history.length,
        unread: service.unreadCount,
        position: service.position,
        dnd: service.dnd,
        muted: service.mutedList,
        timeout: service.timeout,
        criticalTimeout: service.criticalTimeout,
        stickyCritical: service.stickyCritical,
        maxVisible: service.maxVisible,
        maxStack: service.maxStack,
        animation: service.animation,
        width: service.cardWidth,
        historyLimit: service.historyLimit,
        devices: service.devices.length,
        config: service.configPath,
        state: service.historyPath
      })
    }

    function toggle(): string { return service.requestPanel("toggle") }
    function open(): string { return service.requestPanel("open") }
    function close(): string { return service.requestPanel("close") }
    function settings(): string { return service.requestPanel("settings") }

    function dnd(value: string): string {
      var v = String(value || "").toLowerCase()
      if (v === "toggle" || v === "") return service.toggleDnd()
      return service.setDnd(v === "true" || v === "1" || v === "on" || v === "yes")
    }

    function clear(): string {
      service.clearHistory()
      return "ok"
    }

    function position(value: string): string {
      return service.setPosition(value, true)
    }

    function reload(): string {
      configFile.reload()
      return "ok"
    }

    function mute(app: string): string { return service.muteApp(app) }
    function unmute(app: string): string { return service.unmuteApp(app) }

    function readAll(): string { return service.markAllRead() }
    function remove(key: string): string { return service.removeHistory(key) }
    function invoke(key: string): string { return service.invokeHistory(key) }

    function historyJson(): string { return JSON.stringify(service.history) }
  }
}
