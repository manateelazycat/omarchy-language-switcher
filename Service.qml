import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Languages.js" as Languages

Item {
  id: root

  property bool opened: false
  property bool busy: false
  property bool noticeVisible: false
  property bool noticeError: false
  property string noticeMessage: ""
  property string loadError: ""
  property string query: ""
  property string targetScreenName: ""
  property int selectedIndex: 0
  property var entries: []
  property var filtered: []
  readonly property string helperPath: "/usr/local/libexec/omarchy-language-switcher-helper"

  function rebuild() {
    filtered = Languages.filter(entries, query)
    var activeIndex = filtered.findIndex(function(entry) { return entry.active })
    selectedIndex = activeIndex >= 0 ? activeIndex : 0
  }

  function open() {
    if (busy) return
    targetScreenName = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? ""
    noticeTimer.stop()
    noticeVisible = false
    loadError = ""
    query = ""
    rebuild()
    opened = true
    if (!listProcess.running) listProcess.running = true
  }

  function close() { opened = false }
  function toggle() { if (opened) close(); else open() }

  function moveSelection(delta) {
    if (filtered.length === 0) return
    selectedIndex = Math.max(0, Math.min(filtered.length - 1, selectedIndex + delta))
  }

  function showNotice(message, isError, transient) {
    noticeTimer.stop()
    noticeMessage = message
    noticeError = isError
    noticeVisible = true
    if (transient) noticeTimer.start()
  }

  function select(index) {
    if (busy || index < 0 || index >= filtered.length) return
    var entry = filtered[index]
    opened = false
    busy = true
    showNotice("正在切换到 " + entry.title + "…", false, false)
    applyProcess.command = ["/usr/bin/pkexec", helperPath, "apply", entry.code]
    applyProcess.running = true
  }

  onQueryChanged: rebuild()

  Process {
    id: listProcess
    command: [root.helperPath, "list"]
    stdout: StdioCollector { id: listOutput; waitForEnd: true }
    stderr: StdioCollector { id: listError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.entries = []
        root.rebuild()
        root.loadError = String(listError.text || "无法读取语言列表").trim()
        return
      }
      try {
        var result = JSON.parse(String(listOutput.text || "{}"))
        root.entries = (result.locales || []).map(Languages.decorate)
        root.loadError = ""
        root.rebuild()
      } catch (error) {
        root.entries = []
        root.rebuild()
        root.loadError = "语言列表格式错误：" + error
      }
    }
  }

  Process {
    id: applyProcess
    stdout: StdioCollector { id: applyOutput; waitForEnd: true }
    stderr: StdioCollector { id: applyError; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) {
        root.showNotice("系统语言已切换。请注销并重新登录后生效。", false, true)
      } else {
        var message = String(applyError.text || "").trim()
        root.showNotice(message || (exitCode === 126 ? "已取消管理员授权" : "切换系统语言失败"), true, true)
      }
    }
  }

  Timer {
    id: noticeTimer
    interval: 6500
    onTriggered: root.noticeVisible = false
  }

  IpcHandler {
    target: "andy.language-switcher"
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property ShellScreen modelData
      screen: modelData
      visible: (root.opened || root.noticeVisible) && modelData.name === root.targetScreenName
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      mask: Region { item: root.opened ? scrim : notice }
      WlrLayershell.namespace: "andy-language-switcher"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: panel.visible && root.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
      anchors { top: true; bottom: true; left: true; right: true }
      onVisibleChanged: if (visible && root.opened) Qt.callLater(function() {
        resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
        searchField.forceActiveFocus()
      })

      Rectangle {
        id: scrim
        anchors.fill: parent
        visible: root.opened
        color: Color.menu.scrim
        MouseArea { anchors.fill: parent; onClicked: root.close() }
      }

      Rectangle {
        id: card
        width: Math.min(Style.space(520), panel.width - Style.gapsOut * 2)
        height: Math.min(Style.space(512), panel.height - Style.gapsOut * 2)
        anchors.centerIn: parent
        visible: root.opened
        radius: Style.cornerRadius
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: 1

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.md

          Text {
            text: "切换系统语言"
            textFormat: Text.PlainText
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          TextField {
            id: searchField
            width: parent.width
            text: root.query
            placeholderText: "搜索语言名称或 locale 代码…"
            onTextEdited: root.query = text
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
              else if (event.key === Qt.Key_Down) { root.moveSelection(1); event.accepted = true }
              else if (event.key === Qt.Key_Up) { root.moveSelection(-1); event.accepted = true }
              else if (event.key === Qt.Key_PageDown) { root.moveSelection(6); event.accepted = true }
              else if (event.key === Qt.Key_PageUp) { root.moveSelection(-6); event.accepted = true }
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.select(root.selectedIndex)
                event.accepted = true
              }
            }
          }

          Text {
            text: root.filtered.length + " 种语言/地区  ·  ↑↓ 选择  ·  Enter 切换  ·  Esc 关闭"
            textFormat: Text.PlainText
            color: Color.menu.text
            opacity: 0.62
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }

          ListView {
            id: resultList
            width: parent.width
            height: Math.max(0, parent.height - y)
            model: root.filtered
            clip: true
            spacing: Style.spacing.xs
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.selectedIndex
            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
            onCountChanged: if (root.opened && count > 0) positionViewAtIndex(root.selectedIndex, ListView.Contain)

            delegate: Rectangle {
              id: row
              required property int index
              required property var modelData
              width: ListView.view.width
              height: Style.space(53)
              radius: Style.cornerRadius
              color: index === root.selectedIndex ? Color.menu.selectedBackground : "transparent"
              border.color: index === root.selectedIndex ? Color.menu.selectedBorder : "transparent"
              border.width: index === root.selectedIndex ? 1 : 0

              Column {
                anchors.left: parent.left
                anchors.right: statusLabel.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.md
                spacing: 2

                Text {
                  text: row.modelData.title
                  textFormat: Text.PlainText
                  color: row.index === root.selectedIndex ? Color.menu.selectedText : Color.menu.text
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.body
                  font.bold: row.index === root.selectedIndex
                  elide: Text.ElideRight
                  width: parent.width
                }
                Text {
                  text: row.modelData.subtitle + "  ·  " + row.modelData.code
                  textFormat: Text.PlainText
                  color: row.index === root.selectedIndex ? Color.menu.selectedText : Color.menu.text
                  opacity: 0.64
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                }
              }

              Text {
                id: statusLabel
                anchors.right: parent.right
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.active ? "当前" : (row.modelData.installed ? "已安装" : "")
                textFormat: Text.PlainText
                color: row.index === root.selectedIndex ? Color.menu.selectedText : Color.menu.text
                opacity: 0.66
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: root.selectedIndex = row.index
                onClicked: root.select(row.index)
              }
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.filtered.length === 0
          text: listProcess.running ? "正在读取语言…" : (root.loadError || "没有匹配的语言")
          textFormat: Text.PlainText
          color: root.loadError ? Color.urgent : Color.menu.text
          opacity: 0.65
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }
      }

      Rectangle {
        id: notice
        anchors.centerIn: parent
        visible: root.noticeVisible && !root.opened
        width: Math.min(Style.space(470), panel.width - Style.gapsOut * 2)
        height: Style.space(100)
        radius: Style.cornerRadius
        color: Color.menu.background
        border.color: root.noticeError ? Color.urgent : Color.menu.border
        border.width: 1

        Column {
          anchors.centerIn: parent
          width: parent.width - Style.spacing.panelPadding * 2
          spacing: Style.spacing.sm
          Text {
            width: parent.width
            text: root.noticeError ? "切换失败" : (root.busy ? "正在处理" : "切换完成")
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            color: root.noticeError ? Color.urgent : Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            width: parent.width
            text: root.noticeMessage
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
