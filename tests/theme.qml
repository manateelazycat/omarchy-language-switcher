import QtQuick
import QtTest
import Quickshell
import qs.Commons as Commons
import "Plugin" as Plugin
import "Plugin/Languages.js" as Languages

ShellRoot {
    id: root
    Plugin.Service { id: service }
    TestCase { id: checks; when: false }
    function check(value, message) { if (!value) throw new Error(message); }
    function verifySearchLifetime() {
        var panels = service.themeTestPanels.instances;
        check(panels.length > 0, "No screens available for search lifecycle checks");
        for (var cycle = 0; cycle < 3; cycle++) {
            service.targetScreenName = panels[0].modelData.name;
            service.query = "";
            service.opened = true;
            checks.wait(30);
            for (var i = 0; i < panels.length; i++) {
                var field = checks.findChild(panels[i].contentItem, "languageSwitcherSearch");
                check(!!field === (i === 0), "Search must exist only on the target screen");
            }
            service.query = "English";
            checks.wait(30);
            check(checks.findChild(panels[0].contentItem, "languageSwitcherSearch").text === "English",
                  "Search query binding after reopening");
            service.close();
            service.noticeVisible = true;
            checks.wait(30);
            for (var j = 0; j < panels.length; j++) {
                check(!checks.findChild(panels[j].contentItem, "languageSwitcherSearch"),
                      "Closed dialog must destroy its search, including while showing a notice");
            }
        }
        service.opened = true;
        service.targetScreenName = "__missing_test_screen__";
        checks.wait(30);
        for (var k = 0; k < panels.length; k++) {
            check(!checks.findChild(panels[k].contentItem, "languageSwitcherSearch"),
                  "Non-target screens must not create a search");
        }
        service.targetScreenName = panels[0].modelData.name;
        service.query = "";
        service.noticeVisible = false;
        checks.wait(30);
    }
    function verifyTheme() {
        var card = checks.findChild(service.themeTestPanels.instances[0].contentItem, "languageSwitcherCard");
        var search = checks.findChild(service.themeTestPanels.instances[0].contentItem, "languageSwitcherSearch");
        var notice = checks.findChild(service.themeTestPanels.instances[0].contentItem, "languageSwitcherNotice");
        var row = checks.findChild(service.themeTestPanels.instances[0].contentItem, "languageSwitcherRow0");
        check(card && search && notice && row, "Dialog objects are missing");
        check(card.color === Commons.Color.menu.background, "Card background");
        check(card.border.color === Commons.Color.menu.border, "Card border");
        check(search.foreground === Commons.Color.foreground, "Search foreground");
        check(search.accent === Commons.Color.accent, "Search accent");
        check(row.color === Commons.Color.menu.selectedBackground, "Selected row background");
        check(row.border.color === Commons.Color.menu.selectedBorder, "Selected row border");
        check(notice.color === Commons.Color.menu.background, "Notice background");
        service.noticeError = true;
        checks.wait(30);
        check(notice.border.color === Commons.Color.urgent, "Error notice border");
        service.noticeError = false;
    }
    function verifySearchIntegration() {
        var field = checks.findChild(service.themeTestPanels.instances[0].contentItem, "languageSwitcherSearch");
        var editor = checks.findChild(field, "languageSwitcherSearchEditor");
        service.entries = [
            {code: "en_US.UTF-8", name: "English", active: true, installed: true},
            {code: "zh_CN.UTF-8", name: "Chinese", active: false, installed: true},
            {code: "ja_JP.UTF-8", name: "Japanese", active: false, installed: false}
        ].map(Languages.decorate);
        service.query = "";
        service.rebuild();
        editor.cursorSelection.text = "中文";
        checks.wait(30);
        check(service.query === "中文" && service.filtered.length === 1 && service.filtered[0].code === "zh_CN.UTF-8",
              "Editor changes must filter the actual language list");
        service.query = "English";
        checks.wait(30);
        check(field.text === "English" && service.filtered.length === 1 && service.filtered[0].code === "en_US.UTF-8",
              "External query updates must preserve the editor binding");
        service.query = "";
        checks.wait(30);
        field.navigationRequested({key: Qt.Key_Down, accepted: false});
        check(service.selectedIndex === 1, "Down must change the real selected language");
        field.navigationRequested({key: Qt.Key_Up, accepted: false});
        check(service.selectedIndex === 0, "Up must change the real selected language");
        field.navigationRequested({key: Qt.Key_Escape, accepted: false});
        checks.wait(30);
        check(!service.opened && !checks.findChild(service.themeTestPanels.instances[0].contentItem, "languageSwitcherSearch"),
              "Escape must dismiss and destroy the real search field");
    }
    Timer {
        interval: 250; running: true
        onTriggered: {
            try {
                verifySearchLifetime();
                service.filtered = [{code: "en_US.UTF-8", title: "English", subtitle: "English", active: true, installed: true}];
                checks.wait(30);
                verifyTheme();
                Commons.Color.shellValues = ({});
                Commons.Color.loadColors('background = "#060b1e"\nforeground = "#ffcead"\naccent = "#7d82d9"');
                checks.wait(30);
                verifyTheme();
                Commons.Color.loadColors('background = "#fafafa"\nforeground = "#202020"\naccent = "#0055aa"');
                checks.wait(30);
                verifyTheme();
                verifySearchIntegration();
                check(!service.busy, "A locale change was unexpectedly started");
                console.log("PLUGIN_THEME_PASS");
            } catch (error) { console.log("PLUGIN_THEME_FAIL", String(error)); }
            Qt.quit();
        }
    }
}
