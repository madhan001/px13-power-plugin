import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    property var px: ({})
    property string lastOutput: ""
    property bool lastFailed: false
    property bool commandBusy: false

    readonly property string binDir: "/home/madhan/.local/bin/"
    readonly property string statusCommand: binDir + "px13-panel-status"
    readonly property string gpuUsersCommand: binDir + "px13-panel-run gpu-users"
    // Apps using the NVIDIA GPU ([{pid, name}]), fetched when GPU Eco is chosen.
    property var gpuUsers: []
    property bool gpuUsersLoaded: false

    readonly property string mode: px.mode || "unknown"
    readonly property bool drifted: px.applied === "drifted"
    readonly property bool rebootPending: px.reboot_pending === "yes"
    readonly property bool gpuOptimized: px.gpu_policy === "optimized"
    readonly property bool watcherRunning: px.watcher === "yes"
    readonly property bool onAc: px.ac_online === "1"
    readonly property bool gpuEcoOn: px.gpu_eco === "on"

    readonly property var modeInfo: ({
        "eco": { label: "Eco", letter: "E", icon: "battery-profile-powersave-symbolic", watts: "15 / 15 / 20 W" },
        "normal": { label: "Normal", letter: "N", icon: "battery-profile-balanced-symbolic", watts: "25 / 25 / 35 W" },
        "perf": { label: "Performance", letter: "P", icon: "battery-profile-performance-symbolic", watts: "up to 65 / 70 / 80 W" }
    })

    function modeLabel(m) {
        return modeInfo[m] ? modeInfo[m].label : "Unknown";
    }

    function limitValues() {
        const l = px.limits;
        if (!l || l === "unknown") {
            return ["–", "–", "–"];
        }
        return l.split(" ").map(v => Math.round(parseFloat(v)).toString());
    }

    function limitsText() {
        const v = limitValues();
        return v[0] === "–" ? "unknown" : v.join(" / ") + " W";
    }

    function batteryText() {
        if (!px.battery_percent) {
            return "No battery";
        }
        let text = px.battery_percent + "%";
        if (px.battery_status === "Discharging" && px.battery_watts) {
            text += " · " + px.battery_watts + " W draw";
        } else if (px.battery_status) {
            text += " · " + px.battery_status.toLowerCase();
        }
        if (px.charge_limit) {
            text += " · limit " + px.charge_limit + "%";
        }
        return text;
    }

    function batteryIcon() {
        const pct = parseInt(px.battery_percent || "0");
        const level = ("00" + Math.min(100, Math.round(pct / 10) * 10)).slice(-3);
        const charging = px.battery_status === "Charging" || (onAc && px.battery_status !== "Discharging");
        return "battery-" + level + (charging ? "-charging" : "") + "-symbolic";
    }

    function gpuText() {
        if (px.gpu_eco === "on") {
            return "Off (firmware GPU Eco)";
        }
        if (px.gpu_eco === "off") {
            if (px.gpu_driver && px.gpu_driver !== "none") {
                return (px.gpu_runtime === "suspended" ? "Sleeping" : "Active") + " · " + px.gpu_driver + " driver";
            }
            if (px.gpu_driver_issue === "no_module") {
                return "On · no NVIDIA module for this kernel";
            }
            if (px.gpu_driver_issue === "not_loaded") {
                return "On · driver not loaded";
            }
            return "On · no driver until reboot";
        }
        return "Unknown";
    }

    function gpuDotColor() {
        if (px.gpu_eco === "on") {
            return Kirigami.Theme.disabledTextColor;
        }
        if (px.gpu_eco === "off" && (!px.gpu_driver || px.gpu_driver === "none")) {
            return Kirigami.Theme.neutralTextColor;
        }
        return px.gpu_runtime === "suspended" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.activeTextColor;
    }

    Plasmoid.icon: modeInfo[mode] ? modeInfo[mode].icon : "preferences-system-power-management"
    Plasmoid.status: PlasmaCore.Types.ActiveStatus
    Plasmoid.busy: commandBusy

    toolTipMainText: "PX13 Power: " + modeLabel(mode) + (drifted ? " (not applied)" : "")
    toolTipSubText: "Limits: " + limitsText() + "\nBattery: " + batteryText() + "\nGPU: " + gpuText()
                    + "\nMiddle-click to cycle modes"

    switchWidth: Kirigami.Units.gridUnit * 10
    switchHeight: Kirigami.Units.gridUnit * 10

    function runCommand(command, label) {
        if (commandBusy) {
            return;
        }
        commandBusy = true;
        lastFailed = false;
        lastOutput = label + "...";
        commandRunner.disconnectSource(command);
        commandRunner.connectSource(command);
    }

    function runAction(action) {
        runCommand(binDir + "px13-panel-run " + action, "Running " + action);
    }

    function setChargeLimit(pct) {
        runCommand(binDir + "px13-panel-battery limit " + pct, "Setting charge limit");
    }

    function refreshGpuUsers() {
        gpuUsersLoaded = false;
        commandRunner.disconnectSource(gpuUsersCommand);
        commandRunner.connectSource(gpuUsersCommand);
    }

    function gpuUsersText() {
        return gpuUsers.map(u => u.name + " (" + u.pid + ")").join(", ");
    }

    // GPU Eco was chosen: list what uses the GPU before asking to confirm.
    onPendingGpuChanged: if (pendingGpu === 0) refreshGpuUsers()

    function refreshStatus() {
        commandRunner.disconnectSource(statusCommand);
        commandRunner.connectSource(statusCommand);
    }

    function parseStatus(text) {
        const parsed = {};
        const lines = text.split("\n");
        for (let i = 0; i < lines.length; i++) {
            const eq = lines[i].indexOf("=");
            if (eq > 0) {
                parsed[lines[i].substring(0, eq)] = lines[i].substring(eq + 1).trim();
            }
        }
        px = parsed;
    }

    function commandOutput(data) {
        const stdout = (data["stdout"] || "").toString().trim();
        const stderr = (data["stderr"] || "").toString().trim();
        return [stdout, stderr].filter(t => t.length > 0).join("\n") || "Done.";
    }

    onExpandedChanged: function() {
        if (expanded) {
            refreshStatus();
        } else {
            pendingGpu = -1;
        }
    }

    Component.onCompleted: refreshStatus()

    Timer {
        // Cheap: the status helper only reads a few files.
        interval: root.expanded ? 5000 : 30000
        running: true
        repeat: true
        onTriggered: root.refreshStatus()
    }

    Plasma5Support.DataSource {
        id: commandRunner
        engine: "executable"
        interval: 0

        onNewData: function(sourceName, data) {
            commandRunner.disconnectSource(sourceName);

            if (sourceName === root.statusCommand) {
                root.parseStatus((data["stdout"] || "").toString());
                return;
            }
            if (sourceName === root.gpuUsersCommand) {
                root.gpuUsers = (data["stdout"] || "").toString().split("\n")
                    .map(l => l.trim().split(/\s+/))
                    .filter(f => f.length === 2 && /^[0-9]+$/.test(f[0]))
                    .map(f => ({ pid: f[0], name: f[1] }));
                root.gpuUsersLoaded = true;
                return;
            }
            root.commandBusy = false;
            root.pendingMode = "";
            root.lastFailed = data["exit code"] !== undefined && data["exit code"] !== 0;
            root.lastOutput = root.commandOutput(data);
            root.refreshStatus();
        }
    }

    compactRepresentation: Item {
        id: compactRoot

        Layout.minimumWidth: Kirigami.Units.iconSizes.smallMedium
        Layout.minimumHeight: Kirigami.Units.iconSizes.smallMedium
        Layout.preferredWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing
        Layout.preferredHeight: Kirigami.Units.iconSizes.medium

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: function(mouse) {
                if (mouse.button === Qt.MiddleButton) {
                    root.runAction("cycle");
                } else {
                    root.expanded = !root.expanded;
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: Plasmoid.icon
                Layout.fillHeight: true
                Layout.preferredWidth: height
                opacity: root.drifted ? 0.5 : 1.0
            }

            PlasmaComponents3.Label {
                visible: compactRoot.width > Kirigami.Units.gridUnit * 2.5
                text: (root.modeInfo[root.mode] ? root.modeInfo[root.mode].letter : "?") + (root.drifted ? "!" : "")
                color: root.drifted ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.bold: true
            }
        }
    }

    readonly property var modeOrder: ["eco", "normal", "perf"]
    // While a mode switch runs, show the requested mode instead of snapping back.
    property string pendingMode: ""
    readonly property int modeIndex: Math.max(0, modeOrder.indexOf(pendingMode || mode))

    readonly property var gpuChoices: [
        { action: "deep-eco", label: "GPU Eco",
          question: "Power off the NVIDIA GPU?",
          detail: "The firmware cuts its power. No apps are using it." },
        { action: "hybrid", label: "Hybrid",
          question: "Power on the NVIDIA GPU?",
          detail: "Takes a couple of seconds. It sleeps by itself when idle." },
        { action: "optimized", label: "Optimized",
          question: "Let the GPU follow the charger?",
          detail: "GPU Eco on battery, Hybrid on AC." }
    ]
    readonly property int gpuIndex: gpuOptimized ? 2 : gpuEcoOn ? 0 : px.gpu_eco === "off" ? 1 : -1
    property int pendingGpu: -1

    function limitsDetail() {
        const v = limitValues();
        if (v[0] === "–") {
            return "Power limits unknown";
        }
        let text = v[0] + " W sustained · " + v[1] + " W slow · " + v[2] + " W fast";
        if (drifted) {
            return text + " · overridden by firmware";
        }
        return text + (px.applied === "yes" ? " · verified" : "");
    }

    readonly property int chargeLimit: parseInt(px.charge_limit || "0")
    readonly property int chargeLimitBase: parseInt(px.charge_limit_base || "0")
    // asusd raises the live limit to 100% during a one-shot full charge.
    readonly property bool oneShotActive: chargeLimitBase > 0 && chargeLimit !== chargeLimitBase
    readonly property int normalLimit: oneShotActive ? chargeLimitBase : chargeLimit
    readonly property var chargeLimitChoices: {
        let list = [60, 70, 80, 90, 100];
        if (normalLimit > 0 && list.indexOf(normalLimit) < 0) {
            list.push(normalLimit);
            list.sort((a, b) => a - b);
        }
        return list;
    }

    function batteryDetail() {
        let parts = [];
        if (px.battery_status) {
            parts.push(px.battery_status === "Not charging" ? "Not charging" : px.battery_status);
        }
        if (px.battery_status === "Discharging" && px.battery_watts) {
            parts.push(px.battery_watts + " W");
        }
        return parts.join(" · ");
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.minimumHeight: content.implicitHeight + header.implicitHeight + Kirigami.Units.largeSpacing * 2
        collapseMarginsHint: true

        header: PlasmaExtras.PlasmoidHeading {
            id: header

            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    Layout.fillWidth: true
                    Layout.leftMargin: Kirigami.Units.smallSpacing
                    text: "PX13 Power"
                    level: 1
                    elide: Text.ElideRight
                }

                PlasmaComponents3.BusyIndicator {
                    visible: root.commandBusy
                    running: root.commandBusy
                    Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refreshStatus()
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    text: "Refresh"
                    PlasmaComponents3.ToolTip { text: parent.text }
                }

                PlasmaComponents3.ToolButton {
                    icon.name: "utilities-terminal"
                    enabled: !root.commandBusy
                    display: PlasmaComponents3.AbstractButton.IconOnly
                    text: "Show full status"
                    onClicked: {
                        const command = root.binDir + "px13-open-status";
                        commandRunner.disconnectSource(command);
                        commandRunner.connectSource(command);
                    }
                    PlasmaComponents3.ToolTip { text: parent.text }
                }
            }
        }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing * 2

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.drifted
                type: Kirigami.MessageType.Warning
                text: "The firmware has overridden the " + root.modeLabel(root.mode) + " power limits."
                actions: [
                    Kirigami.Action {
                        text: "Reapply"
                        icon.name: "view-refresh"
                        enabled: !root.commandBusy
                        onTriggered: root.runAction("reapply")
                    }
                ]
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.px.mode !== undefined && !root.watcherRunning
                type: Kirigami.MessageType.Warning
                text: "The PX13 watcher is not running, so limits won't be restored after sleep."
            }

            // Power profile ----------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.gridUnit

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    source: root.modeInfo[root.modeOrder[root.modeIndex]].icon
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: "Power Profile"
                    }

                    PlasmaComponents3.Slider {
                        id: profileSlider
                        Layout.fillWidth: true
                        from: 0
                        to: 2
                        stepSize: 1
                        snapMode: PlasmaComponents3.Slider.SnapAlways
                        value: root.modeIndex
                        enabled: !root.commandBusy
                        onMoved: {
                            const target = root.modeOrder[Math.round(value)];
                            value = Qt.binding(() => root.modeIndex);
                            if (target !== root.mode) {
                                root.pendingMode = target;
                                root.runAction(target);
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Repeater {
                            model: root.modeOrder
                            PlasmaComponents3.Label {
                                required property string modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                horizontalAlignment: index === 0 ? Text.AlignLeft
                                                   : index === 2 ? Text.AlignRight : Text.AlignHCenter
                                text: root.modeLabel(modelData)
                                font: Kirigami.Theme.smallFont
                                opacity: index === root.modeIndex ? 1 : 0.6
                            }
                        }
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: root.limitsDetail()
                        font: Kirigami.Theme.smallFont
                        color: root.drifted ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        opacity: root.drifted ? 1 : 0.7
                        wrapMode: Text.Wrap
                    }
                }
            }

            // Battery ----------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.gridUnit

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    source: root.batteryIcon()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: "Battery"
                        }
                        PlasmaComponents3.Label {
                            text: root.px.battery_percent ? root.px.battery_percent + "%" : "–"
                            opacity: 0.7
                        }
                    }

                    PlasmaComponents3.ProgressBar {
                        Layout.fillWidth: true
                        from: 0
                        to: 100
                        value: parseInt(root.px.battery_percent || "0")
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: root.batteryDetail()
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        visible: root.normalLimit > 0

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: "Charge limit"
                        }
                        PlasmaComponents3.ComboBox {
                            model: root.chargeLimitChoices.map(v => v + "%")
                            currentIndex: root.chargeLimitChoices.indexOf(root.normalLimit)
                            enabled: !root.commandBusy
                            onActivated: function(index) {
                                const pct = root.chargeLimitChoices[index];
                                if (pct !== root.normalLimit) {
                                    root.setChargeLimit(pct);
                                }
                            }
                        }
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        visible: root.normalLimit > 0 && root.normalLimit < 100
                        text: root.oneShotActive
                              ? "Charging to 100% once, then back to " + root.normalLimit + "%."
                              : "Stops charging at " + root.normalLimit + "% to extend battery life."
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        wrapMode: Text.Wrap
                    }

                    PlasmaComponents3.Button {
                        visible: root.normalLimit > 0 && root.normalLimit < 100
                        enabled: !root.commandBusy
                        icon.name: root.oneShotActive ? "dialog-cancel" : "battery-100-charging-symbolic"
                        text: root.oneShotActive ? "Cancel Full Charge" : "Fully Charge Once"
                        onClicked: root.oneShotActive
                                   ? root.setChargeLimit(root.normalLimit)
                                   : root.runCommand(root.binDir + "px13-panel-battery oneshot", "Starting full charge")
                    }
                }
            }

            // GPU --------------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.gridUnit

                Kirigami.Icon {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                    source: "monitor-symbolic"
                    opacity: root.gpuEcoOn ? 0.5 : 1
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: "NVIDIA GPU"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            Layout.preferredWidth: Kirigami.Units.smallSpacing * 1.5
                            Layout.preferredHeight: Kirigami.Units.smallSpacing * 1.5
                            radius: width / 2
                            color: root.gpuDotColor()
                        }
                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: root.gpuText()
                            font: Kirigami.Theme.smallFont
                            opacity: 0.7
                            elide: Text.ElideRight
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing

                        Repeater {
                            model: root.gpuChoices

                            PlasmaComponents3.Button {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                text: modelData.label
                                // Show the choice awaiting confirmation, else the live state.
                                checked: (root.pendingGpu >= 0 ? root.pendingGpu : root.gpuIndex) === index
                                enabled: !root.commandBusy && root.px.gpu_eco !== undefined
                                onClicked: root.pendingGpu = index === root.gpuIndex ? -1 : index
                                PlasmaComponents3.ToolTip { text: modelData.detail }
                            }
                        }
                    }
                }
            }

            Kirigami.InlineMessage {
                id: gpuConfirm
                Layout.fillWidth: true
                // GPU Eco with apps on the GPU: offer to close them.
                readonly property bool appsInUse: root.pendingGpu === 0 && root.gpuUsers.length > 0
                visible: root.pendingGpu >= 0
                type: appsInUse ? Kirigami.MessageType.Warning : Kirigami.MessageType.Information
                text: root.pendingGpu < 0 ? ""
                      : appsInUse
                        ? "<b>" + root.gpuChoices[0].question + "</b><br>In use by "
                          + root.gpuUsersText() + ". They will be asked to quit (unsaved work may be lost); "
                          + "any still running after 5 s are closed."
                        : "<b>" + root.gpuChoices[root.pendingGpu].question + "</b><br>"
                          + (root.pendingGpu === 0 && !root.gpuUsersLoaded ? "Checking for apps using the GPU…"
                             : root.gpuChoices[root.pendingGpu].detail)
                actions: [
                    Kirigami.Action {
                        text: gpuConfirm.appsInUse ? "Close Apps and Switch" : "Apply"
                        icon.name: gpuConfirm.appsInUse ? "process-stop" : "dialog-ok-apply"
                        enabled: root.pendingGpu !== 0 || root.gpuUsersLoaded
                        onTriggered: {
                            let action = root.gpuChoices[root.pendingGpu].action;
                            if (gpuConfirm.appsInUse) {
                                action = "deep-eco-close";
                            }
                            root.pendingGpu = -1;
                            root.runAction(action);
                        }
                    },
                    Kirigami.Action {
                        text: "Cancel"
                        icon.name: "dialog-cancel"
                        onTriggered: root.pendingGpu = -1
                    }
                ]
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.rebootPending
                type: Kirigami.MessageType.Information
                text: "Restart to load the NVIDIA driver. The GPU sleeps until then."
            }

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: root.gpuOptimized && (root.px.gpu_busy || "").length > 0
                type: Kirigami.MessageType.Information
                text: "The GPU stays on while " + root.px.gpu_busy + " is using it."
            }

            // Keep the rows packed at the top when the popup is taller.
            Item { Layout.fillHeight: true }

            // Last action ------------------------------------------------------
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                visible: root.lastOutput.length > 0 && (root.commandBusy || root.lastFailed)
                text: root.commandBusy ? "Applying…" : root.lastOutput.split("\n")[0]
                font: Kirigami.Theme.smallFont
                color: root.lastFailed ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                opacity: root.lastFailed ? 1 : 0.7
                wrapMode: Text.Wrap
            }
        }
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: "Eco"
            icon.name: "battery-profile-powersave-symbolic"
            enabled: !root.commandBusy
            onTriggered: root.runAction("eco")
        },
        PlasmaCore.Action {
            text: "Normal"
            icon.name: "battery-profile-balanced-symbolic"
            enabled: !root.commandBusy
            onTriggered: root.runAction("normal")
        },
        PlasmaCore.Action {
            text: "Performance"
            icon.name: "battery-profile-performance-symbolic"
            enabled: !root.commandBusy
            onTriggered: root.runAction("perf")
        },
        PlasmaCore.Action {
            text: "Reapply Current Mode"
            icon.name: "view-refresh"
            enabled: !root.commandBusy
            onTriggered: root.runAction("reapply")
        }
    ]
}
