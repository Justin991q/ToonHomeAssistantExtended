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
		{label: "Schakelaars", domains: ["switch", "input_boolean", "fan"]},
		{label: "Sensoren", domains: ["sensor", "binary_sensor"]},
		{label: "Klimaat", domains: ["climate", "water_heater", "humidifier"]},
		{label: "Scènes/scripts", domains: ["scene", "script", "button", "input_button", "automation"]},
		{label: "Overig", domains: ["*"]}
	]
	property int domainIndex: 0
	property variant knownDomains: ["light", "switch", "input_boolean", "fan", "sensor", "binary_sensor", "climate", "water_heater", "humidifier", "scene", "script", "button", "input_button", "automation"]

	onShown: {
		app.allEntitiesLoaded.connect(rebuild);
		app.selectionChanged.connect(updateMarks);
		if (app.allEntities.length === 0) app.loadAllEntities();
		rebuild();
	}
	onHidden: {
		app.allEntitiesLoaded.disconnect(rebuild);
		app.selectionChanged.disconnect(updateMarks);
	}

	function matches(e) {
		if (onlySelected && !app.isSelected(e.id)) return false;
		if (areaFilter !== "" && (e.area || "Geen ruimte") !== areaFilter) return false;
		var g = domainGroups[domainIndex].domains;
		if (g.length === 1 && g[0] === "*") {
			if (knownDomains.indexOf(e.domain) >= 0) return false;
		} else if (g.length > 0 && g.indexOf(e.domain) < 0) return false;
		if (search !== "") {
			var s = search.toLowerCase();
			if (e.id.toLowerCase().indexOf(s) < 0 && e.name.toLowerCase().indexOf(s) < 0 && app.displayName(e.id).toLowerCase().indexOf(s) < 0) return false;
		}
		return true;
	}

	function rebuild() {
		var list = [];
		for (var i = 0; i < app.allEntities.length; i++) if (matches(app.allEntities[i])) list.push(app.allEntities[i]);
		list.sort(function(a, b) {
			var ra = app.areaRank(a.area), rb = app.areaRank(b.area);
			if (ra !== rb) return ra - rb;
			var na = (a.name || a.id).toLowerCase(), nb = (b.name || b.id).toLowerCase();
			return na < nb ? -1 : (na > nb ? 1 : 0);
		});
		entityModel.clear();
		for (var j = 0; j < list.length; j++) {
			var e = list[j];
			var k = app.indexOf(e.id);
			entityModel.append({entityId: e.id, haName: e.name || e.id, area: e.area || "Geen ruimte",
				selected: k >= 0, fav: k >= 0 && app.entities[k].fav, ownName: k >= 0 ? app.entities[k].name : ""});
		}
		listView.contentY = 0;
	}

	function updateMarks() {
		for (var i = 0; i < entityModel.count; i++) {
			var id = entityModel.get(i).entityId;
			var k = app.indexOf(id);
			entityModel.setProperty(i, "selected", k >= 0);
			entityModel.setProperty(i, "fav", k >= 0 && app.entities[k].fav);
			entityModel.setProperty(i, "ownName", k >= 0 ? app.entities[k].name : "");
		}
	}

	function nextArea() {
		var areas = [""];
		for (var i = 0; i < app.areaNames.length; i++) areas.push(app.areaNames[i]);
		areas.push("Geen ruimte");
		var at = areas.indexOf(areaFilter);
		areaFilter = areas[(at + 1) % areas.length];
		rebuild();
	}

	function page(direction) {
		var y = listView.contentY + direction * (listView.height - rowHeight);
		listView.contentY = Math.max(0, Math.min(y, listView.contentHeight - listView.height));
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
			onClicked: qkeyboard.open("Zoek op naam of entity id", search, function(text) { search = text.trim(); rebuild(); })
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
