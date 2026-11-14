import QtQuick 2.1
import qb.components 1.0

// a camera: its still image as large as fits, renewed every 2 seconds while the screen is open
Screen {
	id: cameraScreen

	screenTitle: "Camera"

	property string entityId: ""
	property int tick: 0

	onShown: {
		if (args && args.entityId) entityId = args.entityId;
		screenTitle = app.displayName(entityId);
		app.pollStates();          // a fresh token in entity_picture
		tick++;
	}

	Timer {
		interval: 2000
		repeat: true
		running: cameraScreen.visible
		onTriggered: cameraScreen.tick++
	}

	Rectangle {
		anchors { fill: parent; margins: isNxt ? 16 : 10 }
		color: "#1d1d1b"
		radius: 8
		clip: true
		HaCameraImage {
			anchors.fill: parent
			fillMode: Image.PreserveAspectFit
			entityId: cameraScreen.entityId
			url: {
				var u = cameraScreen.tick >= 0 ? app.cameraUrl(cameraScreen.entityId) : "";
				return u ? u + "-" + cameraScreen.tick : "";
			}
		}
	}
}
