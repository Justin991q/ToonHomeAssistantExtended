import QtQuick 2.1
import qb.components 1.0
import qb.base 1.0

// the Home Assistant logo in the systray (an option in the settings): opens the list.
// A red dot shows when an alarm panel among your entities has gone off.
SystrayIcon {
	id: homeassistantTray
	property string objectName: "homeassistantTray"

	visible: app.enableSystray
	posIndex: 8600

	property bool alarmTriggered: false

	onClicked: app.openMain()

	Component.onCompleted: app.statesUpdated.connect(update)
	Component.onDestruction: app.statesUpdated.disconnect(update)

	function update() {
		var triggered = false;
		for (var i = 0; i < app.entities.length; i++) {
			var entry = app.haStates[app.entities[i].id];
			if (entry && entry.state === "triggered") triggered = true;
		}
		alarmTriggered = triggered;
	}

	Image {
		id: logo
		anchors.centerIn: parent
		width: Math.round(30 * verticalScaling)
		height: width
		sourceSize.width: width
		sourceSize.height: height
		source: app.logoUrl
		opacity: app.connected || !app.isConfigured() ? 1 : 0.4
	}

	Rectangle {
		visible: alarmTriggered
		width: Math.round(12 * verticalScaling)
		height: width
		radius: width / 2
		color: "#d0021b"
		border.color: "#ffffff"
		border.width: 1
		anchors {
			top: logo.top
			right: logo.right
			rightMargin: -4
		}
	}
}
