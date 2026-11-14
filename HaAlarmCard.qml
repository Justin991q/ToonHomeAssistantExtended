import QtQuick 2.1

// an alarm panel as a double card: a shield in the state's colour, the state, and buttons on the card.
// Off: the arm modes the panel has (as many as fit); on: Uitschakelen. A panel that needs a code opens
// the alarm screen for it, with the mode already chosen; the rest of the card opens that screen too.
Rectangle {
	id: card

	property string entityId: ""
	property int rev: 0
	property bool pending: false

	property string alarmState: rev >= 0 && app.haStates[entityId] ? app.haStates[entityId].state : ""
	property bool armed: alarmState.indexOf("armed_") === 0
	property bool triggered: alarmState === "triggered"
	property bool busy: alarmState === "arming" || alarmState === "pending" || alarmState === "disarming"
	property bool disarmed: alarmState === "disarmed"

	signal failed(string message)

	radius: isNxt ? 12 : 10
	color: triggered ? "#fde2e2" : "#ffffff"
	border.width: triggered || armed ? 2 : 1
	border.color: triggered || armed ? "#d0021b" : (disarmed ? "#b9d8a4" : "#e2e2e2")

	function stateColor() {
		if (armed || triggered) return "#c62828";
		if (disarmed) return "#3b7d16";
		return "#9a5a06";
	}

	// the buttons the card shows: [{mode, label}]
	function buttons() {
		if (armed || triggered || busy) return [{mode: "disarm", label: "Uitschakelen"}];
		var modes = app.alarmModes(entityId);
		var out = [];
		for (var i = 0; i < modes.length && out.length < maxButtons; i++) if (modes[i].mode !== "disarm") out.push(modes[i]);
		return out;
	}
	// as many buttons as fit above each other (at most 3)
	property int buttonMinHeight: isNxt ? 34 : 28
	property int buttonSpacing: isNxt ? 8 : 6
	property int maxButtons: Math.max(1, Math.min(3, Math.floor((height - 2 * (isNxt ? 12 : 8) + buttonSpacing) / (buttonMinHeight + buttonSpacing))))

	// the buttons are rebuilt only when they change: a poll must not move them under a finger
	property variant buttonList: []
	property string buttonKey: ""
	function updateButtons() {
		var b = buttons();
		var k = JSON.stringify(b);
		if (k === buttonKey) return;
		buttonKey = k;
		buttonList = b;
	}
	onRevChanged: updateButtons()
	onEntityIdChanged: updateButtons()
	onMaxButtonsChanged: updateButtons()
	onAlarmStateChanged: updateButtons()

	function press(mode, label) {
		if (app.alarmNeedsCode(entityId, mode)) {
			app.openAlarm(entityId, mode);
			return;
		}
		pending = true;
		app.alarmCommand(entityId, mode, "", null);
	}

	Connections {
		target: app
		onActionResult: {
			if (entityId !== card.entityId) return;
			card.pending = false;
			if (!ok) card.failed(message);
		}
	}
	Timer { running: card.pending; interval: 6000; onTriggered: card.pending = false }
	SequentialAnimation on opacity {
		running: card.pending || card.triggered
		loops: Animation.Infinite
		NumberAnimation { to: 0.6; duration: 450 }
		NumberAnimation { to: 1; duration: 450 }
		onRunningChanged: if (!running) card.opacity = 1
	}

	MouseArea {
		anchors.fill: parent
		onClicked: app.openAlarm(card.entityId)
	}

	Image {
		id: shield
		width: isNxt ? 44 : 34
		height: width
		sourceSize.width: width
		sourceSize.height: height
		anchors { left: parent.left; top: parent.top; margins: isNxt ? 12 : 8 }
		source: Qt.resolvedUrl("drawables/icons/shield" + (armed || triggered ? "-alert" : (disarmed ? "-ok" : "-on")) + ".svg")
	}

	Column {
		anchors {
			left: parent.left
			right: buttonColumn.left
			bottom: parent.bottom
			margins: isNxt ? 12 : 8
		}
		spacing: 2
		Text {
			width: parent.width
			elide: Text.ElideRight
			font.family: qfont.bold.name
			font.pixelSize: isNxt ? 24 : 19
			color: stateColor()
			text: rev >= 0 ? app.alarmStateText(alarmState) : ""
		}
		Text {
			width: parent.width
			elide: Text.ElideRight
			font.family: qfont.regular.name
			font.pixelSize: isNxt ? 15 : 13
			color: "#6b6b6b"
			text: rev >= 0 ? app.displayName(entityId) : ""
		}
	}

	// the buttons, stacked on the right
	Column {
		id: buttonColumn
		spacing: card.buttonSpacing
		anchors {
			right: parent.right
			rightMargin: isNxt ? 12 : 8
			verticalCenter: parent.verticalCenter
		}
		Repeater {
			model: card.buttonList
			Rectangle {
				property bool isDisarm: modelData.mode === "disarm"
				width: isNxt ? 150 : 116
				height: Math.min(isNxt ? 40 : 32, (card.height - 2 * (isNxt ? 12 : 8) - 2 * buttonColumn.spacing) / Math.max(1, card.buttonList.length))
				radius: height / 2
				color: buttonMouse.pressed ? (isDisarm ? "#2f6a10" : "#d0d0d0") : (isDisarm ? "#3b7d16" : "#f0f0f0")
				border.color: isDisarm ? "#3b7d16" : "#d0d0d0"
				Text {
					anchors.centerIn: parent
					font.family: qfont.semiBold.name
					font.pixelSize: isNxt ? 16 : 13
					color: isDisarm ? "#ffffff" : "#1d1d1b"
					text: modelData.label
				}
				MouseArea {
					id: buttonMouse
					anchors.fill: parent
					onClicked: card.press(modelData.mode, modelData.label)
				}
			}
		}
	}
}
