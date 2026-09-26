import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "andy.language-switcher"

  readonly property var languageService: bar?.shell?.serviceFor(root.moduleName)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰗊"
    active: root.languageService ? root.languageService.opened : false
    tooltipText: "切换系统语言"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton && root.languageService)
        root.languageService.toggle()
    }
  }
}
