import QtQuick 2.1
import qb.components 1.0

// every entity of Home Assistant, per area: tick to choose, pencil to rename, star for a favourite.
// Changes are saved at once.
Screen {
	id: homeassistantEntitiesScreen

	screenTitle: "Entiteiten kiezen"

	property string search: ""
	property string areaFilter: ""       // "" = all areas
	property string domainFilter: ""     // "" = all, else a group of domains below
	property bool onlySelected: false
	property int rowHeight: isNxt ? 54 : 44
	property int fontSize: isNxt ? 18 : 15

	property variant domainGroups: [
		{label: "Alle typen", domains: []},
		{label: "Lampen", domains: ["light"]},
		{label: "Schakelaars", domains: ["switch", "input_boolean", "fan", "valve", "group"]},
		{label: "Sensoren", domains: ["sensor", "binary_sensor"]},
		{label: "Klimaat", domains: ["climate", "water_heater", "humidifier"]},
		{label: "Scènes/scripts", domains: ["scene", "script", "button", "input_button", "automation"]},
		{label: "Overig", domains: ["*"]}
	]
	property int domainIndex: 0
	property variant knownDomains: ["light", "switch", "input_boolean", "fan", "valve", "group", "sensor", "binary_sensor", "climate", "water_heater", "humidifier", "scene", "script", "button", "input_button", "automation"]

	onShown: {
		app.allEntitiesLoaded.connect(rebuild);
		app.selectionChanged.connect(updateMarks);
		// the list comes from the cache; older than an hour: fetched again in the background
		if (app.allEntities.length === 0 || new Date().getTime() - app.allVersion > 3600 * 1000) app.loadAllEntities();
		rebuild();
	}
	onHidden: {
		app.allEntitiesLoaded.disconnect(rebuild);
		app.selectionChanged.disconnect(updateMarks);
	}

	function matches(entity) {
		if (onlySelected && !app.isSelected(entity.id)) return false;
		if (areaFilter !== "" && (entity.area || "Geen ruimte") !== areaFilter) return false;
		var domains = domainGroups[domainIndex].domains;
		if (domains.length === 1 && domains[0] === "*") {
			if (knownDomains.indexOf(entity.domain) >= 0) return false;
		} else if (domains.length > 0 && domains.indexOf(entity.domain) < 0) return false;
		if (search !== "") {
			var query = search.toLowerCase();
			if (entity.id.toLowerCase().indexOf(query) < 0 && entity.name.toLowerCase().indexOf(query) < 0 && app.displayName(entity.id).toLowerCase().indexOf(query) < 0) return false;
		}
		return true;
	}

	function rebuild() {
		var list = [];
		for (var entityIndex = 0; entityIndex < app.allEntities.length; entityIndex++) if (matches(app.allEntities[entityIndex])) list.push(app.allEntities[entityIndex]);
		// sort keys made once, not in every comparison
		var keyed = [];
		for (var index = 0; index < list.length; index++) keyed.push({entity: list[index], rank: app.areaRank(list[index].area), name: (list[index].name || list[index].id).toLowerCase()});
		keyed.sort(function(first, second) {
			if (first.rank !== second.rank) return first.rank - second.rank;
			return first.name < second.name ? -1 : (first.name > second.name ? 1 : 0);
		});
		var rows = [];
		for (var keyedIndex = 0; keyedIndex < keyed.length; keyedIndex++) {
			var entity = keyed[keyedIndex].entity;
			var chosenPosition = app.indexOf(entity.id);
			rows.push({entityId: entity.id, haName: entity.name || entity.id, area: entity.area || "Geen ruimte",
				selected: chosenPosition >= 0, fav: chosenPosition >= 0 && app.entities[chosenPosition].fav, ownName: chosenPosition >= 0 ? app.entities[chosenPosition].name : ""});
		}
		entityModel.clear();
		// all rows in one go: a hundred times faster than one by one (an older Qt without it: one by one)
		try { entityModel.append(rows); } catch (errorText) {}
		if (entityModel.count !== rows.length) {
			entityModel.clear();
			for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) entityModel.append(rows[rowIndex]);
		}
		listView.contentY = 0;
	}

	// after a change: only the rows that differ (a model update per row is slow on the Toon)
	function updateMarks() {
		for (var rowIndex = 0; rowIndex < entityModel.count; rowIndex++) {
			var row = entityModel.get(rowIndex);
			var chosenPosition = app.indexOf(row.entityId);
			var selected = chosenPosition >= 0, fav = chosenPosition >= 0 && app.entities[chosenPosition].fav, ownName = chosenPosition >= 0 ? app.entities[chosenPosition].name : "";
			if (row.selected !== selected) entityModel.setProperty(rowIndex, "selected", selected);
			if (row.fav !== fav) entityModel.setProperty(rowIndex, "fav", fav);
			if (row.ownName !== ownName) entityModel.setProperty(rowIndex, "ownName", ownName);
		}
	}

	function nextArea() {
		var areas = [""];
		for (var index = 0; index < app.areaNames.length; index++) areas.push(app.areaNames[index]);
		areas.push("Geen ruimte");
		var position = areas.indexOf(areaFilter);
		areaFilter = areas[(position + 1) % areas.length];
		rebuild();
	}

	function page(direction) {
		var top = listView.contentY + direction * (listView.height - rowHeight);
		listView.contentY = Math.max(0, Math.min(top, listView.contentHeight - listView.height));
	}

	ListModel { id: entityModel }

	Row {
		id: filterRow
		spacing: isNxt ? 10 : 6
		anchors {
			top: parent.top
			topMargin: isNxt ? 14 : 10
			left: parent.left
			leftMargin: isNxt ? 30 : 20
		}
		StandardButton {
			text: search === "" ? "Zoek…" : "Zoek: " + search
			primary: search !== ""
			onClicked: app.openKeyboard("Zoek op naam of entity id", search, function(text) { search = text.trim(); rebuild(); }, "Zoek")
		}
		StandardButton {
			text: areaFilter === "" ? "Alle ruimtes" : areaFilter
			primary: areaFilter !== ""
			onClicked: nextArea()
		}
		StandardButton {
			text: domainGroups[domainIndex].label
			primary: domainIndex !== 0
			onClicked: { domainIndex = (domainIndex + 1) % domainGroups.length; rebuild(); }
		}
		StandardButton {
			text: "Alleen gekozen"
			primary: onlySelected
			onClicked: { onlySelected = !onlySelected; rebuild(); }
		}
		StandardButton {
			text: "Wis filters"
			visible: search !== "" || areaFilter !== "" || domainIndex !== 0 || onlySelected
			onClicked: { search = ""; areaFilter = ""; domainIndex = 0; onlySelected = false; rebuild(); }
		}
	}

	IconButton {
		id: refreshButton
		width: isNxt ? 44 : 36
		height: width
		iconSource: "qrc:/images/refresh.svg"
		anchors {
			verticalCenter: filterRow.verticalCenter
			right: parent.right
			rightMargin: isNxt ? 30 : 20
		}
		onClicked: app.loadAllEntities()
	}

	Rectangle {
		id: listFrame
		color: "transparent"
		clip: true
		anchors {
			top: filterRow.bottom
			topMargin: isNxt ? 12 : 8
			left: parent.left
			leftMargin: isNxt ? 30 : 20
			right: scrollButtons.left
			rightMargin: isNxt ? 12 : 8
			bottom: parent.bottom
			bottomMargin: isNxt ? 12 : 8
		}

		ListView {
			id: listView
			anchors.fill: parent
			model: entityModel
			boundsBehavior: Flickable.StopAtBounds
			clip: true

			section.property: "area"
			section.delegate: Item {
				width: listView.width
				height: isNxt ? 38 : 30
				Text {
					anchors { left: parent.left; leftMargin: 4; bottom: parent.bottom; bottomMargin: 4 }
					font.family: qfont.bold.name
					font.pixelSize: isNxt ? 21 : 17
					color: colors.singleLabelLeftText
					text: section
				}
			}

			delegate: Rectangle {
				width: listView.width
				height: rowHeight
				radius: 4
				color: model.selected ? "#e8f1fb" : (index % 2 === 0 ? "#ffffff" : "#f4f4f4")

				// tick box: choose / remove
				Rectangle {
					id: box
					width: isNxt ? 30 : 24
					height: width
					radius: 4
					border.width: 2
					border.color: model.selected ? "#4a90e2" : "#a0a0a0"
					color: model.selected ? "#4a90e2" : "#ffffff"
					anchors { left: parent.left; leftMargin: isNxt ? 12 : 8; verticalCenter: parent.verticalCenter }
					Image {
						anchors.centerIn: parent
						width: parent.width - 8
						height: width
						sourceSize.width: width
						sourceSize.height: height
						source: "qrc:/images/check.svg"
						visible: model.selected
					}
				}
				MouseArea {
					// the whole left part toggles the choice
					anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: editIcon.left }
					onClicked: app.toggleSelected(model.entityId)
				}

				Column {
					anchors {
						left: box.right
						leftMargin: isNxt ? 14 : 10
						right: editIcon.left
						rightMargin: 10
						verticalCenter: parent.verticalCenter
					}
					Text {
						width: parent.width
						elide: Text.ElideRight
						font.family: qfont.semiBold.name
						font.pixelSize: fontSize
						color: "#000000"
						text: model.ownName !== "" ? model.ownName + "  (" + model.haName + ")" : model.haName
					}
					Text {
						width: parent.width
						elide: Text.ElideRight
						font.family: qfont.regular.name
						font.pixelSize: isNxt ? 13 : 11
						color: "#808080"
						text: model.entityId
					}
				}

				IconButton {
					id: editIcon
					width: isNxt ? 44 : 36
					height: width
					visible: model.selected
					iconSource: "qrc:/images/edit.svg"
					anchors { right: starIcon.left; rightMargin: isNxt ? 10 : 6; verticalCenter: parent.verticalCenter }
					onClicked: {
						var id = model.entityId; var haName = model.haName;
						qkeyboard.open("Naam voor " + id + " (leeg = naam uit Home Assistant)", model.ownName !== "" ? model.ownName : model.haName,
							function(text) { app.rename(id, text === haName ? "" : text); });
					}
				}
				Image {
					id: starIcon
					width: isNxt ? 32 : 26
					height: width
					sourceSize.width: width
					sourceSize.height: height
					opacity: model.selected ? 1 : 0
					anchors { right: parent.right; rightMargin: isNxt ? 14 : 10; verticalCenter: parent.verticalCenter }
					source: model.fav ? "qrc:/images/star-on.svg" : "qrc:/images/star-off.svg"
					MouseArea {
						anchors.fill: parent
						anchors.margins: -8
						enabled: model.selected
						onClicked: app.toggleFavourite(model.entityId)
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
			text: app.loadingAll ? "Entiteiten ophalen uit Home Assistant…"
				: (app.allEntities.length === 0 ? "Geen entiteiten ontvangen. " + app.lastError : "Niets gevonden met deze filters.")
		}
	}

	Column {
		id: scrollButtons
		spacing: isNxt ? 12 : 10
		anchors {
			right: parent.right
			rightMargin: isNxt ? 30 : 20
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
			font.pixelSize: isNxt ? 14 : 11
			color: colors.singleLabelLeftText
			text: entityModel.count + "\nvan " + app.allEntities.length
			horizontalAlignment: Text.AlignHCenter
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
