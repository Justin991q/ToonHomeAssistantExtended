import QtQuick 2.1
import qb.components 1.0

// the chosen entities in a scrollable list: per area, by name or in your own order, all or only favourites
Screen {
	id: homeassistantScreen

	screenTitle: app.appName
	screenTitleIconUrl: app.logoUrl

	property int rowHeight: isNxt ? 56 : 46
	property int fontSize: isNxt ? 20 : 16

	onShown: {
		addCustomTopRightButton("Instellingen");
		app.statesUpdated.connect(updateValues);
		app.selectionChanged.connect(rebuild);
		rebuild();
		app.pollStates();
	}
	onHidden: {
		app.statesUpdated.disconnect(updateValues);
		app.selectionChanged.disconnect(rebuild);
	}
	onCustomButtonClicked: stage.openFullscreen(app.setupScreenUrl)

	function rebuild() {
		var list = app.sortedEntities(app.favouritesOnly, app.sortMode);
		var top = listView.contentY;
		entityModel.clear();
		for (var i = 0; i < list.length; i++) {
			var e = list[i];
			entityModel.append({entityId: e.id, name: e.name, area: e.area, fav: e.fav, section: e.section,
				value: app.stateText(e.id), on: app.isOn(e.id), action: app.actionOf(e.id), adjustable: adjustable(e.id)});
		}
		listView.contentY = Math.min(top, Math.max(0, listView.contentHeight - listView.height));
	}

	// only the values: the list stays where it is
	function updateValues() {
		for (var i = 0; i < entityModel.count; i++) {
			var id = entityModel.get(i).entityId;
			entityModel.setProperty(i, "value", app.stateText(id));
			entityModel.setProperty(i, "on", app.isOn(id));
			entityModel.setProperty(i, "adjustable", adjustable(id));
		}
	}

	// a light with brightness or colour: the row opens the light screen
	function adjustable(id) {
		var l = app.lightOf(id);
		return l !== null && l !== undefined && (l.dimmable || l.color || l.colorTemp);
	}

	function page(direction) {
		var y = listView.contentY + direction * (listView.height - rowHeight);
		listView.contentY = Math.max(0, Math.min(y, listView.contentHeight - listView.height));
	}

	ListModel { id: entityModel }

	// ---- sort and filter ----
	Row {
		id: filterRow
		spacing: isNxt ? 10 : 8
		anchors {
			top: parent.top
			topMargin: isNxt ? 14 : 10
			left: parent.left
			leftMargin: isNxt ? 30 : 24
		}

		Text {
			anchors.verticalCenter: parent.verticalCenter
			font.family: qfont.semiBold.name
			font.pixelSize: fontSize
			color: colors.singleLabelLeftText
			text: "Sorteer:"
		}
		StandardButton {
			text: "Per ruimte"
			primary: app.sortMode === "area"
			onClicked: app.setSortMode("area")
		}
		StandardButton {
			text: "Op naam"
			primary: app.sortMode === "name"
			onClicked: app.setSortMode("name")
		}
		StandardButton {
			text: "Eigen volgorde"
			primary: app.sortMode === "own"
			onClicked: app.setSortMode("own")
		}
		Item { width: isNxt ? 30 : 20; height: 1 }
		StandardButton {
			text: "Alleen favorieten"
			primary: app.favouritesOnly
			onClicked: app.setFavouritesOnly(!app.favouritesOnly)
		}
	}

	Text {
		anchors {
			verticalCenter: filterRow.verticalCenter
			right: parent.right
			rightMargin: isNxt ? 30 : 24
		}
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 15 : 12
		color: app.connected ? colors.singleLabelLeftText : "#d0021b"
		text: app.connected ? "Bijgewerkt " + app.lastUpdate : (app.lastError || "Geen verbinding")
	}

	// ---- the list ----
	Rectangle {
		id: listFrame
		anchors {
			top: filterRow.bottom
			topMargin: isNxt ? 14 : 10
			left: parent.left
			leftMargin: isNxt ? 30 : 24
			right: scrollButtons.left
			rightMargin: isNxt ? 12 : 10
			bottom: parent.bottom
			bottomMargin: isNxt ? 14 : 10
		}
		color: "transparent"
		clip: true

		ListView {
			id: listView
			anchors.fill: parent
			model: entityModel
			boundsBehavior: Flickable.StopAtBounds
			clip: true

			section.property: "section"
			section.criteria: ViewSection.FullString
			section.delegate: Item {
				width: listView.width
				height: section === "" ? 0 : (isNxt ? 40 : 32)
				visible: section !== ""
				Text {
					anchors {
						left: parent.left
						leftMargin: 4
						bottom: parent.bottom
						bottomMargin: 4
					}
					font.family: qfont.bold.name
					font.pixelSize: isNxt ? 22 : 18
					color: colors.singleLabelLeftText
					text: section
				}
			}

			delegate: Rectangle {
				id: row
				width: listView.width
				height: rowHeight
				color: index % 2 === 0 ? "#ffffff" : "#f4f4f4"
				radius: 4

				MouseArea {
					anchors.fill: parent
					enabled: model.adjustable
					onClicked: app.openLight(model.entityId)
				}

				Image {
					id: star
					width: isNxt ? 30 : 24
					height: width
					sourceSize.width: width
					sourceSize.height: height
					anchors {
						left: parent.left
						leftMargin: isNxt ? 12 : 10
						verticalCenter: parent.verticalCenter
					}
					source: model.fav ? "qrc:/images/star-on.svg" : "qrc:/images/star-off.svg"
					MouseArea {
						anchors.fill: parent
						anchors.margins: -10
						onClicked: app.toggleFavourite(model.entityId)
					}
				}

				Column {
					anchors {
						left: star.right
						leftMargin: isNxt ? 14 : 10
						right: valueText.left
						rightMargin: 10
						verticalCenter: parent.verticalCenter
					}
					Text {
						width: parent.width
						elide: Text.ElideRight
						font.family: qfont.semiBold.name
						font.pixelSize: fontSize
						color: "#000000"
						text: model.name
					}
					Text {
						width: parent.width
						elide: Text.ElideRight
						visible: app.sortMode !== "area" && model.area !== ""
						font.family: qfont.regular.name
						font.pixelSize: isNxt ? 14 : 12
						color: "#808080"
						text: model.area
					}
				}

				Text {
					id: valueText
					anchors {
						right: arrow.visible ? arrow.left : (switchButton.visible ? switchButton.left : parent.right)
						rightMargin: isNxt ? 16 : 12
						verticalCenter: parent.verticalCenter
					}
					font.family: qfont.regular.name
					font.pixelSize: fontSize
					color: "#404040"
					text: model.value
				}

				Image {
					id: arrow
					visible: model.adjustable
					width: isNxt ? 22 : 18
					height: width
					sourceSize.width: width
					sourceSize.height: height
					source: "qrc:/images/arrow-right.svg"
					anchors {
						right: switchButton.left
						rightMargin: isNxt ? 14 : 10
						verticalCenter: parent.verticalCenter
					}
				}

				// on/off pill for what toggles, a Start button for scripts, scenes and buttons
				Rectangle {
					id: switchButton
					visible: model.action !== ""
					width: isNxt ? 90 : 72
					height: isNxt ? 38 : 30
					radius: height / 2
					anchors {
						right: parent.right
						rightMargin: isNxt ? 12 : 10
						verticalCenter: parent.verticalCenter
					}
					color: model.action === "toggle" ? (model.on ? "#f5a623" : "#c8c8c8") : "#4a90e2"

					Rectangle {
						visible: model.action === "toggle"
						width: parent.height - 6
						height: width
						radius: width / 2
						color: "#ffffff"
						y: 3
						x: model.on ? parent.width - width - 3 : 3
						Behavior on x { NumberAnimation { duration: 120 } }
					}
					Text {
						visible: model.action !== "toggle"
						anchors.centerIn: parent
						font.family: qfont.bold.name
						font.pixelSize: isNxt ? 16 : 13
						color: "#ffffff"
						text: model.action === "press" ? "Druk" : (model.action === "alarm" ? "Bedien" : "Start")
					}
					MouseArea {
						anchors.fill: parent
						anchors.margins: -6
						onClicked: app.activate(model.entityId)
					}
				}
			}
		}

		Text {
			anchors.centerIn: parent
			width: parent.width - 40
			horizontalAlignment: Text.AlignHCenter
			wrapMode: Text.WordWrap
			visible: entityModel.count === 0
			font.family: qfont.regular.name
			font.pixelSize: fontSize
			color: colors.singleLabelLeftText
			text: !app.isConfigured() ? "Stel eerst Home Assistant in via Instellingen."
				: (app.entities.length === 0 ? "Nog geen entiteiten gekozen. Kies ze via Instellingen of in de webeditor:\n" + app.webEditorUrl()
				: "Geen favorieten. Tik op de ster bij een entiteit, of kies Alles.")
		}
	}

	// ---- scrolling with buttons (flicking works too) ----
	Column {
		id: scrollButtons
		spacing: isNxt ? 12 : 10
		anchors {
			right: parent.right
			rightMargin: isNxt ? 30 : 24
			verticalCenter: listFrame.verticalCenter
		}
		IconButton {
			width: isNxt ? 60 : 48
			height: width
			iconSource: "qrc:/images/arrow-up.svg"
			enabled: listView.contentY > 0
			onClicked: page(-1)
		}
		Text {
			anchors.horizontalCenter: parent.horizontalCenter
			font.family: qfont.regular.name
			font.pixelSize: isNxt ? 15 : 12
			color: colors.singleLabelLeftText
			text: entityModel.count
		}
		IconButton {
			width: isNxt ? 60 : 48
			height: width
			iconSource: "qrc:/images/arrow-down.svg"
			enabled: listView.contentY < listView.contentHeight - listView.height - 1
			onClicked: page(1)
		}
	}
}
