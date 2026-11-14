import QtQuick 2.1

// a round button with an icon from drawables/icons (or a text): media keys, - and +
Rectangle {
	id: button

	property string icon: ""               // e.g. "next" -> drawables/icons/next.svg
	property string label: ""              // a text instead of an icon
	property bool filled: false            // the main button: orange with a white icon
	property bool active: false            // e.g. mute on

	signal clicked()

	width: isNxt ? 48 : 38
	height: width
	radius: width / 2
	opacity: enabled ? 1 : 0.35
	color: filled ? (mouse.pressed ? "#d48a12" : "#f5a623") : (mouse.pressed ? "#d8d8d8" : (active ? "#fde7c2" : "#f0f0f0"))
	border.color: filled ? "#f5a623" : (active ? "#f5a623" : "#d6d6d6")

	Image {
		visible: button.icon !== ""
		anchors.centerIn: parent
		width: Math.round(parent.width * 0.5)
		height: width
		sourceSize.width: width
		sourceSize.height: height
		source: button.icon !== "" ? Qt.resolvedUrl("drawables/icons/" + button.icon + (button.filled ? "-white" : "") + ".svg") : ""
	}
	Text {
		visible: button.label !== ""
		anchors.centerIn: parent
		font.family: qfont.bold.name
		font.pixelSize: Math.round(button.height * 0.5)
		color: button.filled ? "#ffffff" : "#1d1d1b"
		text: button.label
	}
	MouseArea {
		id: mouse
		anchors.fill: parent
		anchors.margins: -4
		onClicked: button.clicked()
	}
}
