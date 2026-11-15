import QtQuick 2.1
import qb.components 1.0

// a timer: the time left (counting down while it runs), and Start, Pauze, Afronden and Annuleren.
// Afronden ends the timer as if its time was up (Home Assistant's timer.finish: automations on "finished"
// run); Annuleren stops it without that (timer.cancel).
Screen {
	id: timerScreen

	screenTitle: "Timer"

	property string entityId: ""
	property int rev: 0
	property string timerState: ""            // idle, active or paused
	property int secondsLeft: 0
	property int fontSize: isNxt ? 20 : 16

	onShown: {
		if (args && args.entityId) entityId = args.entityId;
		screenTitle = app.displayName(entityId);
		app.statesUpdated.connect(update);
		update();
		app.pollStates();
	}
	onHidden: app.statesUpdated.disconnect(update)

	function update() {
		rev++;
		var entry = app.haStates[entityId];
		timerState = entry ? entry.state : "";
		countDown();
	}

	// "0:04:32" (Home Assistant's duration and remaining) -> seconds
	function secondsOf(durationText) {
		var parts = String(durationText || "").split(":");
		var seconds = 0;
		for (var partIndex = 0; partIndex < parts.length; partIndex++) seconds = seconds * 60 + (parseFloat(parts[partIndex]) || 0);
		return Math.round(seconds);
	}

	// the time left: running, until finishes_at; paused, what remains; idle, the timer's whole duration
	function countDown() {
		if (timerState === "active") {
			var finishes = app.parseTime(app.attr(entityId, "finishes_at"));
			secondsLeft = isNaN(finishes.getTime()) ? 0 : Math.max(0, Math.round((finishes.getTime() - Date.now()) / 1000));
		} else if (timerState === "paused") {
			secondsLeft = secondsOf(app.attr(entityId, "remaining"));
		} else {
			secondsLeft = secondsOf(app.attr(entityId, "duration"));
		}
	}

	// seconds -> "4:32" or "1:04:32"
	function clockText(seconds) {
		var hours = Math.floor(seconds / 3600), minutes = Math.floor((seconds % 3600) / 60);
		return (hours > 0 ? hours + ":" + app.pad2(minutes) : minutes) + ":" + app.pad2(seconds % 60);
	}

	Timer {
		interval: 1000
		repeat: true
		running: timerScreen.visible && timerState === "active"
		onTriggered: countDown()
	}

	Column {
		anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: isNxt ? 50 : 36 }
		spacing: isNxt ? 14 : 10

		Image {
			anchors.horizontalCenter: parent.horizontalCenter
			width: isNxt ? 56 : 44
			height: width
			sourceSize.width: width
			sourceSize.height: height
			source: Qt.resolvedUrl("drawables/icons/timer" + (timerState === "active" ? "-on" : "") + ".svg")
		}
		Text {
			anchors.horizontalCenter: parent.horizontalCenter
			font.family: qfont.bold.name
			font.pixelSize: isNxt ? 72 : 56
			color: timerState === "active" ? "#9a5a06" : "#1d1d1b"
			text: clockText(secondsLeft)
		}
		Text {
			anchors.horizontalCenter: parent.horizontalCenter
			font.family: qfont.regular.name
			font.pixelSize: timerScreen.fontSize
			color: "#6b6b6b"
			text: rev >= 0 ? app.timerText(entityId, timerState) : ""
		}
	}

	Row {
		anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: isNxt ? 50 : 36 }
		spacing: isNxt ? 16 : 10

		StandardButton {
			text: timerState === "paused" ? "Verder" : "Start"
			primary: true
			enabled: timerState !== "active"
			onClicked: app.timerCommand(entityId, "start")
		}
		StandardButton {
			text: "Pauze"
			enabled: timerState === "active"
			onClicked: app.timerCommand(entityId, "pause")
		}
		StandardButton {
			text: "Afronden"
			enabled: timerState === "active"
			onClicked: app.timerCommand(entityId, "finish")
		}
		StandardButton {
			text: "Annuleren"
			enabled: timerState === "active" || timerState === "paused"
			onClicked: app.timerCommand(entityId, "cancel")
		}
	}
}
