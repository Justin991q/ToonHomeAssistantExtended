import QtQuick 2.1
import qb.components 1.0

// one alarm panel (alarm_control_panel): its state, the arm modes it supports and Uitschakelen.
// With a numeric code a keypad, with a text code the keyboard; without a code the buttons act at once.
Screen {
	id: homeassistantAlarmScreen

	screenTitle: "Alarm"

	property string entityId: ""
	property string code: ""
	property string message: ""
	property bool messageIsError: false
	property bool busy: false
	property string alarmState: ""
	property string codeFormat: ""
	property int fontSize: isNxt ? 20 : 16

	onShown: {
		// closing the keyboard shows the screen again without args: keep the panel
		if (args && args.entityId && args.entityId !== entityId) {
			entityId = args.entityId;
			code = "";
			message = "";
		}
		screenTitle = app.displayName(entityId);
		app.statesUpdated.connect(update);
		update();
		app.pollStates();
	}
	onHidden: {
		app.statesUpdated.disconnect(update);
		code = "";              // never keep a code around
	}

	function update() {
		var s = app.haStates[entityId];
		alarmState = s ? s.state : "";
		codeFormat = app.alarmCodeFormat(entityId);
		var modes = app.alarmModes(entityId);
		modeModel.clear();
		for (var i = 0; i < modes.length; i++) modeModel.append(modes[i]);
	}

	function stateColor() {
		if (alarmState === "triggered") return "#d0021b";
		if (alarmState === "disarmed") return "#417505";
		if (alarmState.indexOf("armed") === 0) return "#d0021b";
		return "#f5a623";
	}

	function run(mode, label) {
		if (busy) return;
		if (app.alarmNeedsCode(entityId, mode) && code === "") {
			message = "Voer eerst de code in";
			messageIsError = true;
			if (codeFormat === "text") askCode();
			return;
		}
		busy = true;
		message = label + "…";
		messageIsError = false;
		app.alarmCommand(entityId, mode, codeFormat ? code : "", function(ok, err) {
			busy = false;
			code = "";
			message = ok ? label + ": verstuurd" : err;
			messageIsError = !ok;
		});
	}

	function askCode() {
		qkeyboard.open("Alarmcode", "", function(text) { code = text; message = ""; });
	}

	function press(key) {
		message = "";
		if (key === "C") code = "";
		else if (key === "<") code = code.substring(0, code.length - 1);
		else if (code.length < 12) code += key;
	}

	ListModel { id: modeModel }

	// ---- left: state and modes ----
	Item {
		id: leftPane
		anchors {
			top: parent.top
			bottom: parent.bottom
			left: parent.left
			leftMargin: isNxt ? 50 : 40
			topMargin: isNxt ? 30 : 24
		}
		width: codeFormat === "number" ? parent.width * 0.5 - anchors.leftMargin : parent.width - 2 * anchors.leftMargin

		Image {
			id: logo
			width: isNxt ? 64 : 50
			height: width
			sourceSize.width: width
			sourceSize.height: height
			source: app.logoUrl
		}
		Text {
			id: stateLabel
			anchors {
				left: logo.right
				leftMargin: isNxt ? 20 : 16
				verticalCenter: logo.verticalCenter
				right: parent.right
			}
			elide: Text.ElideRight
			font.family: qfont.bold.name
			font.pixelSize: isNxt ? 34 : 28
			color: stateColor()
			text: alarmState ? app.alarmStateText(alarmState) : (app.connected ? "?" : "Geen verbinding")
		}

		Text {
			id: hint
			anchors {
				top: logo.bottom
				topMargin: isNxt ? 18 : 14
				left: parent.left
				right: parent.right
			}
			wrapMode: Text.WordWrap
			font.family: qfont.regular.name
			font.pixelSize: isNxt ? 16 : 13
			color: colors.singleLabelLeftText
			text: codeFormat === "" ? "Dit alarm heeft geen code nodig."
				: (codeFormat === "number" ? "Voer de code in op het toetsenblok en kies dan wat het alarm moet doen."
				: "Tik op Code invoeren en kies dan wat het alarm moet doen.")
		}

		Flow {
			id: modeButtons
			anchors {
				top: hint.bottom
				topMargin: isNxt ? 18 : 14
				left: parent.left
				right: parent.right
			}
			spacing: isNxt ? 12 : 10

			Repeater {
				model: modeModel
				StandardButton {
					text: model.label
					primary: model.mode === "disarm" ? homeassistantAlarmScreen.alarmState !== "disarmed" : homeassistantAlarmScreen.alarmState === "armed_" + model.mode.substring(4)
					height: isNxt ? 52 : 42
					fontPixelSize: fontSize
					onClicked: run(model.mode, model.label)
				}
			}
		}

		StandardButton {
			id: textCodeButton
			visible: codeFormat === "text"
			text: code === "" ? "Code invoeren" : "Code: " + Array(code.length + 1).join("*")
			anchors {
				top: modeButtons.bottom
				topMargin: isNxt ? 18 : 14
				left: parent.left
			}
			onClicked: askCode()
		}

		Text {
			anchors {
				top: textCodeButton.visible ? textCodeButton.bottom : modeButtons.bottom
				topMargin: isNxt ? 18 : 14
				left: parent.left
				right: parent.right
			}
			wrapMode: Text.WordWrap
			font.family: qfont.semiBold.name
			font.pixelSize: fontSize
			color: messageIsError ? "#d0021b" : colors.singleLabelLeftText
			text: message
		}
	}

	// ---- right: keypad for a numeric code ----
	Column {
		id: keypad
		visible: codeFormat === "number"
		spacing: isNxt ? 10 : 8
		anchors {
			top: parent.top
			topMargin: isNxt ? 24 : 18
			right: parent.right
			rightMargin: isNxt ? 70 : 50
		}

		property int keySize: isNxt ? 74 : 56

		Rectangle {
			width: 3 * keypad.keySize + 2 * keypad.spacing
			height: isNxt ? 52 : 42
			radius: 6
			color: "#ffffff"
			border.color: "#c8c8c8"
			Text {
				anchors.centerIn: parent
				font.family: qfont.bold.name
				font.pixelSize: isNxt ? 30 : 24
				color: code === "" ? "#a0a0a0" : "#000000"
				text: code === "" ? "code" : Array(code.length + 1).join("*")
			}
		}

		Grid {
			columns: 3
			spacing: keypad.spacing
			Repeater {
				model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "<"]
				Rectangle {
					width: keypad.keySize
					height: Math.round(keypad.keySize * 0.78)
					radius: 6
					color: keyArea.pressed ? "#d0d0d0" : (modelData === "C" || modelData === "<" ? "#e4e4e4" : "#ffffff")
					border.color: "#c8c8c8"
					Text {
						anchors.centerIn: parent
						font.family: qfont.bold.name
						font.pixelSize: isNxt ? 28 : 22
						color: "#000000"
						text: modelData === "<" ? "<-" : modelData
					}
					MouseArea {
						id: keyArea
						anchors.fill: parent
						onClicked: press(modelData)
					}
				}
			}
		}
	}
}
