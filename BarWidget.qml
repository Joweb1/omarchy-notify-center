import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar bell: unread badge, DND state, and the notification center popup.
BarWidget {
  id: root
  moduleName: "jovibe.notify-center"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("jovibe.notify-center") : null
  readonly property int unread: service ? Number(service.unreadCount || 0) : 0
  readonly property bool dnd: service ? service.dnd === true : false
  readonly property bool hasUnread: unread > 0

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("service" in target) target.service = root.service
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  function openSettings() {
    if (panelLoader.item && panelLoader.item.openSettings) panelLoader.item.openSettings()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item && panelLoader.item.closeForPopoutSwitch) panelLoader.item.closeForPopoutSwitch()
  }

  onBarChanged: injectPanel()
  onServiceChanged: injectPanel()

  Connections {
    target: root.service
    ignoreUnknownSignals: true

    function onPanelRequested(mode) {
      if (mode === "settings") root.openSettings()
      else if (mode === "open") root.open()
      else if (mode === "close") root.close()
      else root.togglePanel()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dnd ? "\uF1F6" : "\uF0F3"
    fontSize: Style.font.icon
    slotSize: Style.bar.statusSlot
    active: root.hasUnread || root.dnd
    activeColor: root.dnd ? root.bar.urgent : root.bar.barForeground
    useActiveColor: root.dnd
    tooltipText: root.dnd
      ? "Notifications muted"
      : (root.unread > 0 ? root.unread + " unread notification" + (root.unread === 1 ? "" : "s") : "Notifications")

    onPressed: function(buttonCode) {
      if (!root.service) return
      if (buttonCode === Qt.RightButton) root.service.toggleDnd()
      else if (buttonCode === Qt.MiddleButton) root.service.markAllRead()
      else root.togglePanel()
    }
  }

  Rectangle {
    id: badge
    visible: root.hasUnread && !root.dnd
    anchors.right: button.right
    anchors.top: button.top
    anchors.rightMargin: -Style.space(4)
    anchors.topMargin: -Style.space(4)
    z: 2
    width: Math.max(badgeLabel.implicitWidth + Style.space(8), Style.space(14))
    height: Style.space(14)
    radius: height / 2
    color: Color.urgent
    border.width: 1
    border.color: Util.alpha(Color.urgent, 0.9)

    Text {
      id: badgeLabel
      anchors.centerIn: parent
      text: root.unread > 99 ? "99+" : String(root.unread)
      color: Color.background
      font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
    onStatusChanged: if (status === Loader.Error) console.warn("notify-center: panel failed to load")
  }
}
