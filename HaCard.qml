import QtQuick 2.1

// one entity as a card: icon, name, state. Tap switches (or runs, or opens the alarm),
// hold (or the tune button) opens a light's settings. Lit when on; pulses until Home Assistant answers.
Rectangle {
	id: card

	property string entityId: ""
	property int rev: 0                     // raised by the screen when states change: re-reads them
	property bool pending: false

	property string action: rev >= 0 ? app.actionOf(entityId) : ""
	property bool lit: rev >= 0 && action === "toggle" && app.isOn(entityId)
	property bool adjustable: rev >= 0 && isAdjustable()
	property bool valueCard: rev >= 0 && app.isValueCard(entityId)
	property bool unavailable: rev >= 0 && app.haStates[entityId] !== undefined && app.haStates[entityId].state === "unavailable"

	signal failed(string message)

	radius: isNxt ? 12 : 10
	color: lit ? "#fde7c2" : "#ffffff"
	border.width: lit ? 2 : 1
	border.color: lit ? "#f5a623" : "#e2e2e2"
	opacity: unavailable ? 0.5 : 1

	function isAdjustable() {
		var l = app.lightOf(entityId);
		return l !== null && l !== undefined && (l.dimmable || l.color || l.colorTemp);
	}

	Connections {
		target: app
		onActionResult: {
			if (entityId !== card.entityId) return;
			card.pending = false;
			if (!ok) card.failed(message);
		}
	}

	Timer {
		// no answer: stop pulsing, the next poll shows the real state
		running: card.pending
		interval: 6000
		onTriggered: card.pending = false
	}

	SequentialAnimation on opacity {
		running: card.pending
		loops: Animation.Infinite
		NumberAnimation { to: 0.55; duration: 450 }
		NumberAnimation { to: 1; duration: 450 }
		onRunningChanged: if (!running) card.opacity = Qt.binding(function() { return card.unavailable ? 0.5 : 1; })
	}

	scale: mouse.pressed ? 0.97 : 1
	Behavior on scale { NumberAnimation { duration: 80 } }

	MouseArea {
		id: mouse
		anchors.fill: parent
		property bool held: false
		onPressed: held = false
		onPressAndHold: {
			if (card.adjustable) { held = true; app.openLight(card.entityId); }
		}
		onClicked: {
			if (held) return;
			if (card.action === "") {
				if (card.adjustable) app.openLight(card.entityId);
				return;
			}
			if (card.action !== "alarm") card.pending = true;
			app.activate(card.entityId);
		}
	}

	Image {
		id: icon
		width: isNxt ? 36 : 28
		height: width
		sourceSize.width: width
		sourceSize.height: height
		anchors {
			left: parent.left
			top: parent.top
			margins: isNxt ? 12 : 8
		}
		source: rev >= 0 ? app.iconUrl(entityId, false) : ""
	}

	// a light's settings (brightness, colour): also by holding the card
	Rectangle {
		id: tuneButton
		visible: card.adjustable
		width: isNxt ? 40 : 32
		height: width
		radius: width / 2
		color: card.lit ? "#fbd89a" : "#f0f0f0"
		anchors {
			right: parent.right
			top: parent.top
			margins: isNxt ? 10 : 8
		}
		Image {
			anchors.centerIn: parent
			width: parent.width * 0.6
			height: width
			sourceSize.width: width
			sourceSize.height: height
			source: Qt.resolvedUrl("drawables/icons/tune" + (card.lit ? "-on" : "") + ".svg")
		}
		MouseArea {
			anchors.fill: parent
			anchors.margins: -6
			onClicked: app.openLight(card.entityId)
		}
	}

	Column {
		anchors {
			left: parent.left
			right: parent.right
			bottom: parent.bottom
			margins: isNxt ? 12 : 8
		}
		spacing: 2

		Text {
			visible: card.valueCard
			width: parent.width
			elide: Text.ElideRight
			font.family: qfont.bold.name
			font.pixelSize: isNxt ? 28 : 22
			color: "#1d1d1b"
			text: rev >= 0 && card.valueCard ? app.stateText(entityId) : ""
		}
		Text {
			width: parent.width
			wrapMode: Text.WordWrap
			maximumLineCount: card.valueCard ? 1 : 2
			elide: Text.ElideRight
			font.family: card.valueCard ? qfont.regular.name : qfont.semiBold.name
			font.pixelSize: card.valueCard ? (isNxt ? 15 : 13) : (isNxt ? 18 : 15)
			color: card.valueCard ? "#6b6b6b" : "#1d1d1b"
			text: rev >= 0 ? app.displayName(entityId) : ""
		}
		Text {
			visible: !card.valueCard
			width: parent.width
			elide: Text.ElideRight
			font.family: qfont.regular.name
			font.pixelSize: isNxt ? 15 : 13
			color: card.lit ? "#8a5300" : "#6b6b6b"
			text: rev >= 0 ? stateLine() : ""

			function stateLine() {
				if (card.action === "run") return "Tik om te starten";
				if (card.action === "press") return "Tik om in te drukken";
				return app.stateText(entityId);
			}
		}
	}
}
