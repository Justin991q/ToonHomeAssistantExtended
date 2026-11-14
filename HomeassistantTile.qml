import QtQuick 2.1
import qb.components 1.0

// the favourites (no favourites: the first chosen entities); a row that can switch switches,
// the rest of the tile opens the full list
Tile {
	id: homeassistantTile

	property int rowHeight: isNxt ? 32 : 26
	property int maxRows: Math.max(1, Math.floor((height - listColumn.y - (isNxt ? 8 : 6)) / rowHeight))

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
	onMaxRowsChanged: update()

	function update() {
		var ids = app.favouriteList();
		rowModel.clear();
		for (var i = 0; i < ids.length && i < maxRows; i++) {
			rowModel.append({entityId: ids[i], name: app.displayName(ids[i]), value: app.stateText(ids[i]),
				on: app.isOn(ids[i]), action: app.actionOf(ids[i])});
		}
	}

	ListModel { id: rowModel }

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
		color: dimmableColors.tileTitleColor
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
		visible: rowModel.count === 0
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 18 : 15
		color: dimmableColors.tileTextColor
		text: !app.isConfigured() ? "Tik om Home Assistant in te stellen"
			: (app.entities.length === 0 ? "Kies entiteiten in de instellingen" : "")
	}

	Column {
		id: listColumn
		y: tileTitle.y + tileTitle.height + (isNxt ? 10 : 8)
		anchors {
			left: parent.left
			right: parent.right
			leftMargin: isNxt ? 14 : 10
			rightMargin: isNxt ? 14 : 10
		}

		Repeater {
			model: rowModel

			Item {
				width: listColumn.width
				height: homeassistantTile.rowHeight

				Rectangle {
					id: dot
					width: isNxt ? 10 : 8
					height: width
					radius: width / 2
					anchors.verticalCenter: parent.verticalCenter
					visible: model.action === "toggle"
					color: model.on ? "#f5a623" : (dimState ? "#666666" : "#c8c8c8")
				}
				Text {
					anchors {
						left: dot.right
						leftMargin: isNxt ? 8 : 6
						right: valueText.left
						rightMargin: 6
						verticalCenter: parent.verticalCenter
					}
					elide: Text.ElideRight
					font.family: qfont.regular.name
					font.pixelSize: isNxt ? 18 : 15
					color: dimmableColors.tileTextColor
					text: model.name
				}
				Text {
					id: valueText
					anchors {
						right: parent.right
						verticalCenter: parent.verticalCenter
					}
					font.family: qfont.bold.name
					font.pixelSize: isNxt ? 18 : 15
					color: dimmableColors.tileTextColor
					text: model.action === "run" || model.action === "press" ? "Start" : model.value
				}
				MouseArea {
					anchors.fill: parent
					enabled: model.action !== ""
					onClicked: app.activate(model.entityId)
				}
			}
		}
	}

	Text {
		anchors {
			bottom: parent.bottom
			bottomMargin: 4
			horizontalCenter: parent.horizontalCenter
		}
		visible: app.isConfigured() && !app.connected && app.lastError !== ""
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 14 : 12
		color: "#d0021b"
		text: app.lastError
	}
}
