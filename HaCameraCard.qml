import QtQuick 2.1

// a camera as a double card: its still image, renewed with every poll (two images take turns, so the
// old picture stays until the new one is in). A tap opens the camera screen.
Rectangle {
	id: card

	property string entityId: ""
	property int rev: 0
	property bool unavailable: rev >= 0 && app.haStates[entityId] !== undefined && app.haStates[entityId].state === "unavailable"

	signal failed(string message)

	radius: isNxt ? 12 : 10
	color: "#2b2b2b"
	border.width: 1
	border.color: "#e2e2e2"
	clip: true

	HaCameraImage {
		id: picture
		anchors.fill: parent
		anchors.margins: 1
		entityId: card.entityId
		// only while the card can be seen: with the screen closed no picture is fetched every few seconds
		// (the last one stays, "" changes nothing)
		url: card.visible && card.rev >= 0 && !card.unavailable ? app.cameraUrl(card.entityId, picture.animated) : ""
	}

	// name (and state) over the picture
	Rectangle {
		anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
		height: label.implicitHeight + (isNxt ? 14 : 10)
		color: "#99000000"
		Text {
			id: label
			anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: isNxt ? 12 : 8; rightMargin: isNxt ? 12 : 8 }
			elide: Text.ElideRight
			font.family: qfont.semiBold.name
			font.pixelSize: isNxt ? 16 : 13
			color: "#ffffff"
			text: card.rev >= 0 ? app.displayName(card.entityId) + (card.unavailable ? " · niet beschikbaar" : "") : ""
		}
	}

	MouseArea {
		anchors.fill: parent
		onClicked: app.openDetail(card.entityId)
	}
}
