import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The list behind the bar button. Events are ordered nearest to furthest,
// and the one marked as the default is what the bar keeps showing. Dates
// are edited here and written back through the host widget, which owns the
// shell.json entry.
Panel {
  id: root
  moduleName: "io.github.tbye.omadown"
  ipcTarget: "io.github.tbye.omadown"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property date now: new Date()
  property var ordered: []
  property string orderKey: ""
  property string selectedId: ""
  property string editingId: ""
  property bool pinNew: false
  property string formError: ""

  readonly property var events: Model.normalizeEvents(setting("events", []))
  readonly property string defaultId: String(setting("defaultId", "") || "")
  readonly property bool showHours: Model.asBool(setting("showHours", false))
  readonly property var shown: Model.pickBarEvent(events, defaultId, now)
  readonly property var shownParts: shown ? Model.parts(shown, now, showHours) : null

  readonly property color contentForeground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool formFocused: nameField.activeFocus || dateField.activeFocus || timeField.activeFocus

  function refresh() {
    now = new Date()
    refreshOrder()
  }

  // The minute clock moves the labels without rebuilding the list. A new
  // array every minute would scroll the popup back to the top.
  function refreshOrder() {
    var next = Model.sortByNearness(root.events, root.now)
    var key = Model.orderKey(next)
    if (key !== root.orderKey) {
      root.orderKey = key
      root.ordered = next
    }
    if (root.selectedId === "" || Model.indexOfId(root.ordered, root.selectedId) < 0) {
      var current = Model.pickBarEvent(root.events, root.defaultId, root.now)
      root.selectedId = current ? current.id : ""
    }
  }

  function persist(values) {
    if (root.hostWidget && typeof root.hostWidget.persist === "function")
      root.hostWidget.persist(values)
  }

  function open() {
    refresh()
    root.formError = ""
    if (root.editingId === "") root.pinNew = root.events.length === 0
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) root.setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    root.setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function draft() {
    return {
      name: nameField.text,
      date: dateField.text,
      time: timeField.text,
      pin: root.pinNew
    }
  }

  function clearForm() {
    root.editingId = ""
    root.formError = ""
    nameField.text = ""
    dateField.text = ""
    timeField.text = ""
    root.pinNew = false
  }

  function cancelEdit() {
    root.clearForm()
    root.pinNew = root.events.length === 0
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function focusAdd() {
    root.clearForm()
    root.pinNew = root.events.length === 0
    nameField.forceActiveFocus()
  }

  function beginEditSelected() {
    var event = Model.findById(root.ordered, root.selectedId)
    if (!event) return
    root.editingId = event.id
    nameField.text = event.name
    dateField.text = event.date
    timeField.text = event.time
    root.pinNew = event.id === root.defaultId
    root.formError = ""
    nameField.forceActiveFocus()
    nameField.selectAll()
  }

  function submitForm() {
    var result = root.editingId === ""
      ? Model.addCountdown(root.events, root.defaultId, root.draft(), Model.newId(Date.now(), Math.random()))
      : Model.updateCountdown(root.events, root.defaultId, root.editingId, root.draft())
    if (!result.ok) {
      root.formError = result.error
      return
    }
    var keep = root.editingId === "" ? result.events[result.events.length - 1].id : root.editingId
    root.persist({ events: result.events, defaultId: result.defaultId })
    root.selectedId = keep
    root.clearForm()
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  function pinEvent(id) {
    root.selectedId = id
    root.persist({ defaultId: id === root.defaultId ? "" : id })
  }

  function removeEvent(id) {
    var result = Model.removeCountdown(root.events, root.defaultId, id)
    if (root.editingId === id) root.clearForm()
    if (result.events.length === 0) root.pinNew = true
    root.persist({ events: result.events, defaultId: result.defaultId })
    if (root.selectedId === id) root.selectedId = ""
  }

  function moveSelection(delta) {
    if (root.ordered.length === 0) return
    var index = Model.indexOfId(root.ordered, root.selectedId)
    if (index < 0) index = delta > 0 ? -1 : 0
    var next = Math.max(0, Math.min(root.ordered.length - 1, index + delta))
    root.selectedId = root.ordered[next].id
    Qt.callLater(root.revealSelection)
  }

  function revealSelection() {
    var index = Model.indexOfId(root.ordered, root.selectedId)
    if (index < 0 || !eventRepeater) return
    var item = eventRepeater.itemAt(index)
    if (!item) return
    var pos = item.mapToItem(body, 0, 0)
    var top = pos.y
    var bottom = pos.y + item.height
    if (top < scroller.contentY) scroller.contentY = Math.max(0, top)
    else if (bottom > scroller.contentY + scroller.height)
      scroller.contentY = Math.max(0, bottom - scroller.height)
  }

  function handleFormKey(event) {
    if (event.key === Qt.Key_Escape) {
      if (root.editingId !== "") root.cancelEdit()
      else root.close()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.submitForm()
      event.accepted = true
    }
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.now = date
  }

  onEventsChanged: refreshOrder()
  onNowChanged: refreshOrder()
  onDefaultIdChanged: refreshOrder()
  Component.onCompleted: refreshOrder()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.formFocused
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveSelection(dy) }
      onActivateRequested: { if (root.selectedId !== "") root.pinEvent(root.selectedId) }
      onCloseRequested: root.close()
      onDeleteRequested: { if (root.selectedId !== "") root.removeEvent(root.selectedId) }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "a" || t === "A") root.focusAdd()
        else if (t === "e" || t === "E") root.beginEditSelected()
        else if (t === "p" || t === "P") root.persist({ showHours: !root.showHours })
      }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: body
          width: scroller.width
          spacing: Style.space(14)

          Item {
            width: parent.width
            height: Math.max(heroIcon.implicitHeight, heroText.implicitHeight)

            Text {
              id: heroIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "󰥔"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.display
            }

            Column {
              id: heroText
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(12)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.shownParts ? root.shownParts.bar : "No date yet"
                color: root.shownParts && root.shownParts.past
                  ? Qt.darker(root.contentForeground, 1.45)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.shown && root.shownParts
                  ? root.shown.name + " · " + root.shownParts.when
                  : "Add a countdown below"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }

          Item {
            width: parent.width
            height: Math.max(hoursLabel.implicitHeight, hoursSwitch.implicitHeight)

            Text {
              id: hoursLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "SHOW HOURS"
              color: Qt.darker(root.contentForeground, 1.45)
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
            }

            ToggleSwitch {
              id: hoursSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.showHours
              foreground: root.contentForeground
              accent: Commons.Color.accent
              onToggled: root.persist({ showHours: !root.showHours })
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          Text {
            visible: root.ordered.length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: "Nothing here yet."
            color: Qt.darker(root.contentForeground, 1.5)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Column {
            id: eventColumn
            width: parent.width
            spacing: Style.space(4)
            visible: root.ordered.length > 0

            Repeater {
              id: eventRepeater
              model: root.ordered

              delegate: EventRow {
                width: eventColumn.width
              }
            }
          }

          PanelSeparator { foreground: root.contentForeground }

          PanelSectionHeader {
            text: root.editingId === "" ? "ADD" : "EDIT"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          TextField {
            id: nameField
            width: parent.width
            placeholderText: "Name"
            foreground: root.contentForeground
            font.family: root.contentFontFamily
            onTextChanged: root.formError = ""
            Keys.onPressed: function(event) { root.handleFormKey(event) }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: dateField
              width: Math.max(0, parent.width - timeField.width - parent.spacing)
              placeholderText: "YYYY-MM-DD"
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              onTextChanged: root.formError = ""
              Keys.onPressed: function(event) { root.handleFormKey(event) }
            }

            TextField {
              id: timeField
              width: Style.space(96)
              placeholderText: "HH:mm"
              foreground: root.contentForeground
              font.family: root.contentFontFamily
              onTextChanged: root.formError = ""
              Keys.onPressed: function(event) { root.handleFormKey(event) }
            }
          }

          Item {
            width: parent.width
            height: Math.max(pinLabel.implicitHeight, pinSwitch.implicitHeight)

            Text {
              id: pinLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Pin to the bar"
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }

            ToggleSwitch {
              id: pinSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              checked: root.pinNew
              foreground: root.contentForeground
              accent: Commons.Color.accent
              onToggled: root.pinNew = !root.pinNew
            }
          }

          Text {
            visible: root.formError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.formError
            color: root.bar ? root.bar.urgent : Commons.Color.urgent
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            spacing: Style.space(8)

            Button {
              text: root.editingId === "" ? "Add countdown" : "Save"
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.submitForm()
            }

            Button {
              visible: root.editingId !== ""
              text: "Cancel"
              bordered: true
              foreground: root.contentForeground
              fontFamily: root.contentFontFamily
              onClicked: root.cancelEdit()
            }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: "j k move   enter pin   x remove   e edit   a add   p hours"
            color: Qt.darker(root.contentForeground, 1.7)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  component EventRow: Item {
    id: row

    required property var modelData
    required property int index

    readonly property var event: modelData
    readonly property bool pinned: !!event && event.id === root.defaultId
    readonly property bool selected: !!event && event.id === root.selectedId
    readonly property bool onBar: !!event && !!root.shown && event.id === root.shown.id
    readonly property var view: event ? Model.parts(event, root.now, root.showHours) : null
    readonly property color rowInk: view && view.past
      ? Qt.darker(root.contentForeground, 1.45)
      : root.contentForeground

    implicitHeight: Style.space(52)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: row.selected
        ? Style.selectedFillFor(root.contentForeground, Commons.Color.accent)
        : (rowHover.hovered
          ? Style.hoverFillFor(root.contentForeground, Commons.Color.accent)
          : "transparent")
    }

    HoverHandler {
      id: rowHover
      onHoveredChanged: if (hovered && row.event) root.selectedId = row.event.id
    }

    MouseArea {
      anchors.fill: parent
      anchors.rightMargin: pinButton.width + removeButton.width + Style.space(8)
      cursorShape: Qt.PointingHandCursor
      onClicked: if (row.event) root.pinEvent(row.event.id)
    }

    Item {
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(4)

      Column {
        anchors.left: parent.left
        anchors.right: remainText.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.event ? row.event.name : ""
          color: row.rowInk
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: row.pinned
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: {
            if (!row.event || !row.view) return ""
            var line = row.view.when
            if (row.onBar && !row.pinned) line += " · on the bar"
            return line
          }
          color: Qt.darker(root.contentForeground, 1.55)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: remainText
        width: Style.space(84)
        anchors.right: pinButton.left
        anchors.rightMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        textFormat: Text.PlainText
        text: row.view ? row.view.bar : ""
        color: row.rowInk
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      PanelActionButton {
        id: pinButton
        anchors.right: removeButton.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: row.pinned ? "󰓎" : "󰓒"
        tooltipText: row.pinned ? "Unpin from the bar" : "Pin to the bar"
        foreground: row.pinned ? Commons.Color.accent : root.contentForeground
        hoverColor: Commons.Color.accent
        fontFamily: root.contentFontFamily
        onClicked: if (row.event) root.pinEvent(row.event.id)
      }

      PanelActionButton {
        id: removeButton
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅖"
        tooltipText: "Remove"
        foreground: root.contentForeground
        hoverColor: root.bar ? root.bar.urgent : Commons.Color.urgent
        fontFamily: root.contentFontFamily
        onClicked: if (row.event) root.removeEvent(row.event.id)
      }
    }
  }
}
