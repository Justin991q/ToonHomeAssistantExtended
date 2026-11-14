import QtQuick 2.1
import qb.components 1.0

// up to four entities as 2x2 mini cards (chosen under Instellingen > Tegel, else the favourites), in the main screen's style:
// icon, name, state, warm yellow when on. A tap on a card does what the card on the main screen does
// (switch, run, open); the rest of the tile opens the main screen.
Tile {
	id: homeassistantTile

	property int rev: 0
	property variant ids: []
	property int gap: isNxt ? 8 : 6
	property int margin: isNxt ? 10 : 8

	onClicked: app.openMain()

	Component.onCompleted: {
		app.statesUpdated.connect(update);
		app.selectionChanged.connect(update);
		update();
	}
	Component.onDestruction: {
		app.statesUpdated.disconnect(update);
		app.selectionChanged.disconnect(update);
	}

	function update() {
		ids = app.tileList();
		rev++;
	}

	Text {
		id: tileTitle
		anchors {
			baseline: parent.top
			baselineOffset: Math.round(30 * verticalScaling)
			horizontalCenter: parent.horizontalCenter
			horizontalCenterOffset: (tileLogo.width + tileLogo.anchors.rightMargin) / 2
		}
		font.family: qfont.regular.name
		font.pixelSize: qfont.tileTitle
		color: dimState ? "white" : dimmableColors.tileTitleColor
		text: "Home-Assistant"
		width: Math.min(implicitWidth, parent.width - tileLogo.width - tileLogo.anchors.rightMargin - 20)
		elide: Text.ElideRight
	}

	Image {
		id: tileLogo
		width: Math.round(tileTitle.font.pixelSize * 1.3)
		height: width
		sourceSize.width: width
		sourceSize.height: height
		source: app.logoUrl
		opacity: dimState ? 0.6 : 1
		anchors {
			right: tileTitle.left
			rightMargin: 8
			verticalCenter: tileTitle.verticalCenter
		}
	}

	Text {
		anchors.centerIn: parent
		width: parent.width - 20
		horizontalAlignment: Text.AlignHCenter
		wrapMode: Text.WordWrap
		visible: ids.length === 0
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 18 : 15
		color: dimState ? "white" : dimmableColors.tileTextColor
		text: !app.isConfigured() ? "Tik om Home Assistant in te stellen"
			: (app.entities.length === 0 ? "Kies entiteiten in de instellingen" : "")
	}

	// ---- the mini cards ----
	Grid {
		id: grid
		columns: 2
		spacing: homeassistantTile.gap
		anchors {
			top: tileTitle.bottom
			topMargin: isNxt ? 10 : 7
			left: parent.left
			right: parent.right
			bottom: errorText.visible ? errorText.top : parent.bottom
			leftMargin: homeassistantTile.margin
			rightMargin: homeassistantTile.margin
			bottomMargin: homeassistantTile.margin
		}
		property real cellWidth: (width - spacing) / 2
		property real cellHeight: (height - spacing) / 2

		Repeater {
			model: homeassistantTile.ids
			Rectangle {
				id: mini
				property string entityId: modelData
				property bool lit: homeassistantTile.rev >= 0 && app.isLit(entityId)
				property string action: homeassistantTile.rev >= 0 ? app.actionOf(entityId) : ""

				width: grid.cellWidth
				height: grid.cellHeight
				radius: isNxt ? 8 : 6
				color: dimState ? "transparent" : (lit ? "#fde7c2" : (miniMouse.pressed ? "#ececec" : "#f6f6f6"))
				border.width: lit && !dimState ? 2 : 1
				border.color: dimState ? "#4a4a4a" : (lit ? "#f5a623" : "#e2e2e2")

				// icon on the left; on the right two lines: the name and the state (a sensor, a thermostat:
				// its value big, then the name)
				Image {
					id: miniIcon
					width: isNxt ? 26 : 20
					height: width
					sourceSize.width: width
					sourceSize.height: height
					anchors { left: parent.left; leftMargin: isNxt ? 8 : 6; verticalCenter: parent.verticalCenter }
					source: homeassistantTile.rev >= 0 ? app.iconUrl(mini.entityId, dimState) : ""
				}
				Column {
					property bool valueCard: homeassistantTile.rev >= 0 && app.isValueCard(mini.entityId)
					anchors { left: miniIcon.right; leftMargin: isNxt ? 7 : 5; right: parent.right; rightMargin: isNxt ? 6 : 4; verticalCenter: parent.verticalCenter }
					Text {
						width: parent.width
						elide: Text.ElideRight
						font.family: parent.valueCard ? qfont.bold.name : qfont.semiBold.name
						font.pixelSize: parent.valueCard ? (isNxt ? 17 : 14) : (isNxt ? 15 : 12)
						color: dimState ? "white" : "#1d1d1b"
						text: homeassistantTile.rev < 0 ? "" : (parent.valueCard ? app.valueText(mini.entityId) : app.displayName(mini.entityId))
					}
					Text {
						width: parent.width
						elide: Text.ElideRight
						visible: text !== ""
						font.family: qfont.regular.name
						font.pixelSize: isNxt ? 13 : 11
						color: dimState ? "#bbbbbb" : (mini.lit ? "#8a5300" : "#6b6b6b")
						text: {
							if (homeassistantTile.rev < 0) return "";
							if (parent.valueCard) return app.displayName(mini.entityId);
							if (mini.action === "run" || mini.action === "press") return "Tik om te starten";
							return app.stateText(mini.entityId);
						}
					}
				}
				MouseArea {
					id: miniMouse
					anchors.fill: parent
					onClicked: {
						if (mini.action === "") app.openMain();      // read only: the main screen
						else app.activate(mini.entityId);
					}
				}
			}
		}
	}

	Text {
		id: errorText
		anchors {
			bottom: parent.bottom
			bottomMargin: 4
			horizontalCenter: parent.horizontalCenter
		}
		visible: app.isConfigured() && !app.connected && app.lastError !== ""
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 14 : 12
		color: "#d0021b"
		text: app.friendlyError(app.lastError)
	}
}
