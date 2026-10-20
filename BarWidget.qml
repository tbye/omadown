import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar label for one countdown: a clock glyph, the day count, and the hours
// when that option is on. Left click opens the list. Right click toggles
// hours. Middle click walks which countdown is pinned to the bar.
//
// The popup's KeyboardPanel has to treat this item as its owner. The bar
// compares the open popout with the widget in the slot, and a nested panel
// would never match.
BarWidget {
  id: root
  moduleName: "io.github.tbye.omadown"

  // nf-md-clock, from the same Nerd Font the bar already draws with.
  readonly property string clockIcon: "󰥔"

  property date now: new Date()

  readonly property var events: Model.normalizeEvents(setting("events", []))
  readonly property string defaultId: String(setting("defaultId", "") || "")
  readonly property bool showHours: Model.asBool(setting("showHours", false))
  readonly property var barEvent: Model.pickBarEvent(events, defaultId, now)
  readonly property var barParts: barEvent ? Model.parts(barEvent, now, showHours) : null
  readonly property string barText: barParts ? barParts.bar : ""
  readonly property var verticalLines: barParts ? barParts.vertical : []
  readonly property string tip: Model.tooltip(barEvent, now, showHours)
  readonly property color ink: {
    var color = bar ? bar.barForeground : Commons.Color.foreground
    return barParts && barParts.past ? Qt.darker(color, 1.45) : color
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: hRow.implicitWidth
  readonly property real openPanelIndicatorHeight: Style.bar.iconSlot

  function refresh() {
    now = new Date()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  // shell.json is the only copy of the countdowns. The plugin directory is
  // a git checkout, and `omarchy plugin update` fast-forwards it, so dates
  // stored beside the code would be in the way of an upgrade.
  function persist(values) {
    var entry = { id: root.moduleName }
    var current = root.settings || {}
    for (var key in current) if (key !== "id") entry[key] = current[key]
    for (var name in values) entry[name] = values[name]
    root.settings = entry
    if (panelLoader.item && "settings" in panelLoader.item) panelLoader.item.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function toggleShowHours() {
    persist({ showHours: !showHours })
  }

  function cycleShown() {
    persist({ defaultId: Model.cycleDefault(events, defaultId, now) })
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.now = date
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
  }

  IpcHandler {
    target: "io.github.tbye.omadown"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.tip
    horizontalMargin: 8
    verticalPadding: 4
    fixedWidth: root.vertical ? -1 : Math.ceil(hRow.implicitWidth + Style.space(16))
    fixedHeight: root.vertical ? Math.max(Style.bar.iconSlot, Math.ceil(vCol.implicitHeight)) : -1

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleShowHours()
      else if (b === Qt.MiddleButton) root.cycleShown()
      else root.toggle()
    }

    Row {
      id: hRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: root.barText === "" ? 0 : Style.space(6)

      Text {
        textFormat: Text.PlainText
        anchors.verticalCenter: parent.verticalCenter
        text: root.clockIcon
        color: root.ink
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }

      Text {
        textFormat: Text.PlainText
        visible: root.barText !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.barText
        color: root.ink
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }
    }

    Column {
      id: vCol
      visible: root.vertical
      width: root.barSize
      anchors.horizontalCenter: parent.horizontalCenter

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: root.clockIcon
        color: root.ink
        font.family: button.fontFamily
        font.pixelSize: Style.bar.iconFont
        renderType: Text.NativeRendering
      }

      Repeater {
        model: root.verticalLines

        Text {
          required property string modelData
          width: vCol.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: modelData
          color: root.ink
          font.family: button.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          renderType: Text.NativeRendering
        }
      }
    }
  }
}
