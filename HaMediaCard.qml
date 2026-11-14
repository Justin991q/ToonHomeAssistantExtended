import QtQuick 2.1

// a speaker (media_player) as a double card: album art, what plays, and the keys right on the card
// (previous, play/pause, next, volume). Off: a power button. The rest of the card opens the speaker screen.
Rectangle {
	id: card

	property string entityId: ""
	property int rev: 0
	property bool pending: false

	property string playState: rev >= 0 && app.haStates[entityId] ? app.haStates[entityId].state : ""
	property bool off: rev >= 0 && app.mediaIsOff(entityId)
	property bool playing: playState === "playing"
	property string title: rev >= 0 ? (app.attr(entityId, "media_title") || "") : ""
	property string artist: rev >= 0 ? (app.attr(entityId, "media_artist") || app.attr(entityId, "app_name") || "") : ""
	property int margin: isNxt ? 12 : 8

	signal failed(string message)

	radius: isNxt ? 12 : 10
	color: playing ? "#fde7c2" : "#ffffff"
	border.width: playing ? 2 : 1
	border.color: playing ? "#f5a623" : "#e2e2e2"
	opacity: playState === "unavailable" ? 0.5 : 1

	Connections {
		target: app
		onActionResult: {
			if (entityId !== card.entityId) return;
			card.pending = false;
			if (!ok) card.failed(message);
		}
	}

	MouseArea {
		anchors.fill: parent
		onClicked: app.openDetail(card.entityId)
	}

	// album art, else the speaker icon
	Rectangle {
		id: artFrame
		width: height
		anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: card.margin }
		radius: 8
		color: "#f3f3f3"
		clip: true
		Image {
			id: art
			anchors.fill: parent
			fillMode: Image.PreserveAspectCrop
			asynchronous: true
			sourceSize.width: width
			source: card.rev >= 0 && !card.off ? app.pictureUrl(card.entityId) : ""
		}
		Image {
			visible: art.status !== Image.Ready
			anchors.centerIn: parent
			width: Math.round(parent.width * 0.5)
			height: width
			sourceSize.width: width
			sourceSize.height: height
			source: Qt.resolvedUrl("drawables/icons/speaker" + (card.playing ? "-on" : "") + ".svg")
		}
	}

	Column {
		id: info
		anchors { left: artFrame.right; leftMargin: card.margin; right: parent.right; rightMargin: card.margin; top: parent.top; topMargin: card.margin }
		spacing: 1
		Text {
			width: parent.width
			elide: Text.ElideRight
			font.family: qfont.semiBold.name
			font.pixelSize: isNxt ? 18 : 15
			color: "#1d1d1b"
			text: card.title !== "" && !card.off ? card.title : (card.rev >= 0 ? app.displayName(card.entityId) : "")
		}
		Text {
			width: parent.width
			elide: Text.ElideRight
			font.family: qfont.regular.name
			font.pixelSize: isNxt ? 15 : 13
			color: card.playing ? "#8a5300" : "#6b6b6b"
			text: card.off || card.title === "" ? (card.rev >= 0 ? app.stateText(card.entityId).split(":")[0] : "")
				: (card.artist !== "" ? card.artist : app.displayName(card.entityId))
		}
	}

	// the keys
	Row {
		id: keys
		visible: !card.off
		anchors { left: artFrame.right; leftMargin: card.margin; bottom: parent.bottom; bottomMargin: card.margin }
		spacing: isNxt ? 8 : 5
		property bool roomForVolume: card.width - artFrame.width - 3 * card.margin >= 5 * (isNxt ? 48 : 38) + 4 * spacing

		HaRoundButton {
			icon: "prev"
			visible: card.rev >= 0 && app.mediaSupports(card.entityId, "previous")
			onClicked: app.mediaPrevious(card.entityId)
		}
		HaRoundButton {
			icon: card.playing ? "pause" : "playbtn"
			filled: true
			onClicked: app.mediaPlayPause(card.entityId)
		}
		HaRoundButton {
			icon: "next"
			visible: card.rev >= 0 && app.mediaSupports(card.entityId, "next")
			onClicked: app.mediaNext(card.entityId)
		}
		HaRoundButton {
			icon: "minus"
			visible: keys.roomForVolume && card.rev >= 0 && (app.mediaSupports(card.entityId, "volume") || app.mediaSupports(card.entityId, "step"))
			onClicked: app.mediaVolumeStep(card.entityId, false)
		}
		HaRoundButton {
			icon: "plus"
			visible: keys.roomForVolume && card.rev >= 0 && (app.mediaSupports(card.entityId, "volume") || app.mediaSupports(card.entityId, "step"))
			onClicked: app.mediaVolumeStep(card.entityId, true)
		}
	}

	HaRoundButton {
		visible: card.off && card.rev >= 0 && app.mediaSupports(card.entityId, "on")
		icon: "power"
		anchors { left: artFrame.right; leftMargin: card.margin; bottom: parent.bottom; bottomMargin: card.margin }
		onClicked: app.mediaPower(card.entityId, true)
	}
}
