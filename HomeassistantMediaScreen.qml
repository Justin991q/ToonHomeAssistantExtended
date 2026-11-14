import QtQuick 2.1
import qb.components 1.0

// a speaker (media_player): album art, what plays, the keys, volume (slider, mute), power and the source
Screen {
	id: mediaScreen

	screenTitle: "Speaker"

	property string entityId: ""
	property int rev: 0
	property string playState: ""
	property bool off: true
	property bool playing: playState === "playing"
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
		var s = app.haStates[entityId];
		playState = s ? s.state : "";
		off = app.mediaIsOff(entityId);
		sourceBar.refresh();
		var v = app.attr(entityId, "volume_level");
		if (!volumeSlider.dragging && typeof v === "number") volumeSlider.value = v;
	}

	// ---- album art ----
	Rectangle {
		id: artFrame
		width: isNxt ? 260 : 200
		height: width
		radius: 12
		color: "#f3f3f3"
		clip: true
		anchors { left: parent.left; leftMargin: isNxt ? 50 : 36; top: parent.top; topMargin: isNxt ? 36 : 24 }
		Image {
			id: art
			anchors.fill: parent
			fillMode: Image.PreserveAspectCrop
			asynchronous: true
			sourceSize.width: width
			source: rev >= 0 && !off ? app.pictureUrl(entityId) : ""
		}
		Image {
			visible: art.status !== Image.Ready
			anchors.centerIn: parent
			width: parent.width * 0.4
			height: width
			sourceSize.width: width
			sourceSize.height: height
			source: Qt.resolvedUrl("drawables/icons/speaker" + (playing ? "-on" : "") + ".svg")
		}
	}

	// ---- what plays, keys, volume ----
	Column {
		id: right
		anchors { left: artFrame.right; leftMargin: isNxt ? 40 : 28; right: power.left; rightMargin: isNxt ? 20 : 14; top: artFrame.top }
		spacing: isNxt ? 8 : 5

		Text {
			width: parent.width
			elide: Text.ElideRight
			font.family: qfont.bold.name
			font.pixelSize: isNxt ? 30 : 24
			color: "#1d1d1b"
			text: rev >= 0 && !off && app.attr(entityId, "media_title") ? app.attr(entityId, "media_title") : (rev >= 0 ? app.stateText(entityId) : "")
		}
		Text {
			width: parent.width
			elide: Text.ElideRight
			font.family: qfont.regular.name
			font.pixelSize: mediaScreen.fontSize
			color: "#6b6b6b"
			text: {
				if (rev < 0 || off) return "";
				var parts = [];
				var a = app.attr(entityId, "media_artist"), al = app.attr(entityId, "media_album_name"), ap = app.attr(entityId, "app_name");
				if (a) parts.push(a);
				if (al) parts.push(al);
				if (parts.length === 0 && ap) parts.push(ap);
				return parts.join(" · ");
			}
		}
		Item { width: 1; height: isNxt ? 14 : 8 }

		Row {
			spacing: isNxt ? 20 : 14
			visible: !off
			HaRoundButton {
				width: isNxt ? 60 : 48
				anchors.verticalCenter: parent.verticalCenter
				icon: "prev"
				enabled: rev >= 0 && app.mediaSupports(entityId, "previous")
				onClicked: app.mediaPrevious(entityId)
			}
			HaRoundButton {
				width: isNxt ? 76 : 60
				anchors.verticalCenter: parent.verticalCenter
				icon: playing ? "pause" : "playbtn"
				filled: true
				onClicked: app.mediaPlayPause(entityId)
			}
			HaRoundButton {
				width: isNxt ? 60 : 48
				anchors.verticalCenter: parent.verticalCenter
				icon: "next"
				enabled: rev >= 0 && app.mediaSupports(entityId, "next")
				onClicked: app.mediaNext(entityId)
			}
		}
		Item { width: 1; height: isNxt ? 10 : 6 }

		Row {
			visible: !off && rev >= 0 && (app.mediaSupports(entityId, "volume") || app.mediaSupports(entityId, "step") || app.mediaSupports(entityId, "mute"))
			spacing: isNxt ? 14 : 10
			HaRoundButton {
				anchors.verticalCenter: parent.verticalCenter
				icon: rev >= 0 && app.attr(entityId, "is_volume_muted") === true ? "mute" : "volume"
				active: rev >= 0 && app.attr(entityId, "is_volume_muted") === true
				enabled: rev >= 0 && app.mediaSupports(entityId, "mute")
				onClicked: app.mediaMute(entityId)
			}
			HaSlider {
				id: volumeSlider
				visible: rev >= 0 && app.mediaSupports(entityId, "volume")
				width: right.width - (isNxt ? 48 : 38) * 3 - 3 * parent.spacing
				anchors.verticalCenter: parent.verticalCenter
				fillToKnob: true
				onReleased: app.mediaSetVolume(entityId, value)
			}
			HaRoundButton {
				anchors.verticalCenter: parent.verticalCenter
				icon: "minus"
				visible: rev >= 0 && (app.mediaSupports(entityId, "volume") || app.mediaSupports(entityId, "step"))
				onClicked: app.mediaVolumeStep(entityId, false)
			}
			HaRoundButton {
				anchors.verticalCenter: parent.verticalCenter
				icon: "plus"
				visible: rev >= 0 && (app.mediaSupports(entityId, "volume") || app.mediaSupports(entityId, "step"))
				onClicked: app.mediaVolumeStep(entityId, true)
			}
		}
	}

	// ---- power, top right ----
	Rectangle {
		id: power
		opacity: rev >= 0 && (app.mediaSupports(entityId, off ? "on" : "off")) ? 1 : 0
		width: isNxt ? 110 : 88
		height: isNxt ? 50 : 40
		radius: height / 2
		color: off ? "#c8c8c8" : "#f5a623"
		anchors { right: parent.right; rightMargin: isNxt ? 50 : 36; top: artFrame.top }
		Rectangle {
			width: parent.height - 8
			height: width
			radius: width / 2
			color: "#ffffff"
			anchors.verticalCenter: parent.verticalCenter
			x: off ? 4 : parent.width - width - 4
			Behavior on x { NumberAnimation { duration: 120 } }
		}
		MouseArea { anchors.fill: parent; enabled: power.opacity > 0; onClicked: app.mediaPower(entityId, off) }
	}

	// ---- source: a row of buttons that scrolls sideways ----
	Item {
		id: sourceBar
		property variant sources: []
		property string sourcesKey: ""
		// rebuilt only when the list changes: a redraw would drop a tap that is going on
		function refresh() {
			var list = app.mediaSupports(entityId, "source") ? (app.attr(entityId, "source_list") || []) : [];
			var key = JSON.stringify(list);
			if (key === sourcesKey) return;
			sourcesKey = key;
			sources = list;
		}
		visible: sources.length > 0 && !off
		height: isNxt ? 48 : 40
		anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: isNxt ? 50 : 36; rightMargin: isNxt ? 50 : 36; bottomMargin: isNxt ? 30 : 20 }
		Text {
			id: sourceLabel
			anchors.verticalCenter: parent.verticalCenter
			font.family: qfont.regular.name
			font.pixelSize: mediaScreen.fontSize - 2
			color: "#6b6b6b"
			text: "Bron"
		}
		Flickable {
			anchors { left: sourceLabel.right; leftMargin: isNxt ? 20 : 14; right: parent.right; top: parent.top; bottom: parent.bottom }
			contentWidth: sourceRow.width
			flickableDirection: Flickable.HorizontalFlick
			boundsBehavior: Flickable.StopAtBounds
			clip: true
			Row {
				id: sourceRow
				spacing: isNxt ? 10 : 7
				Repeater {
					model: sourceBar.sources
					Rectangle {
						property bool picked: rev >= 0 && app.attr(entityId, "source") === modelData
						width: sourceText.implicitWidth + (isNxt ? 30 : 22)
						height: sourceBar.height
						radius: height / 2
						color: picked ? "#f5a623" : (sourceMouse.pressed ? "#d8d8d8" : "#f0f0f0")
						border.color: picked ? "#f5a623" : "#d6d6d6"
						Text {
							id: sourceText
							anchors.centerIn: parent
							font.family: qfont.semiBold.name
							font.pixelSize: isNxt ? 16 : 13
							color: parent.picked ? "#ffffff" : "#1d1d1b"
							text: modelData
						}
						MouseArea { id: sourceMouse; anchors.fill: parent; onClicked: app.mediaSource(entityId, modelData) }
					}
				}
			}
		}
	}
}
