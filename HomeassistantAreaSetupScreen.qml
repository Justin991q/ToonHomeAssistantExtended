import QtQuick 2.1
import qb.components 1.0

// per area a temperature and a humidity sensor: shown under the area's name on its tab. Left the areas,
// right the sensors that fit (the area's own first). Tap to choose, tap again to clear. Saved at once.
Screen {
	id: areaSetupScreen

	screenTitle: "Ruimtes: temperatuur en vocht"

	property variant areas: []
	property int areaIndex: 0
	property string kind: "temperature"        // or "humidity"
	property int rev: 0
	property variant candidates: []

	onShown: {
		app.allEntitiesLoaded.connect(refresh);
		app.selectionChanged.connect(refresh);
		app.statesUpdated.connect(onStates);
		if (app.allEntities.length === 0 || new Date().getTime() - app.allVersion > 3600 * 1000) app.loadAllEntities();
		refresh();
	}
	onHidden: {
		app.allEntitiesLoaded.disconnect(refresh);
		app.selectionChanged.disconnect(refresh);
		app.statesUpdated.disconnect(onStates);
	}

	function onStates() { rev++; }

	function currentArea() { return areas.length > 0 ? areas[Math.min(areaIndex, areas.length - 1)].key : ""; }

	function refresh() {
		rev++;
		areas = app.sensorAreaList();
		var area = currentArea();
		var chosenId = app.areaSensor(area, kind);
		var out = [];
		for (var index = 0; index < app.allEntities.length; index++) {
			var entity = app.allEntities[index];
			if (!app.fitsAreaSensor(entity, kind) && entity.id !== chosenId) continue;
			out.push({id: entity.id, name: entity.name || entity.id, state: entity.state, unit: entity.unit,
				here: (entity.area || "") === area, chosen: entity.id === chosenId});
		}
		// grouped by area, each group under a header: this area's own first, then the others in your order, no area last
		var groups = {}, groupOrder = [];
		for (var candidateIndex = 0; candidateIndex < out.length; candidateIndex++) {
			var candidateArea = app.allIndex[out[candidateIndex].id] ? (app.allIndex[out[candidateIndex].id].area || "") : "";
			if (!groups[candidateArea]) { groups[candidateArea] = []; groupOrder.push(candidateArea); }
			groups[candidateArea].push(out[candidateIndex]);
		}
		groupOrder.sort(function(first, second) {
			if ((first === area) !== (second === area)) return first === area ? -1 : 1;
			return app.areaRank(first) - app.areaRank(second) || (first < second ? -1 : (first > second ? 1 : 0));
		});
		var list = [];
		// the area's own header always: also when it has no fitting sensor
		if (!groups[area]) list.push({header: true, label: "In " + (area || "Overig") + " (deze ruimte): geen"});
		for (var groupIndex = 0; groupIndex < groupOrder.length; groupIndex++) {
			var groupArea = groupOrder[groupIndex];
			list.push({header: true, label: groupArea === area ? "In " + (area || "Overig") + " (deze ruimte)" : (groupArea || "Geen ruimte")});
			var members = groups[groupArea];
			members.sort(function(first, second) { return first.name.toLowerCase() < second.name.toLowerCase() ? -1 : (first.name.toLowerCase() > second.name.toLowerCase() ? 1 : 0); });
			for (var memberIndex = 0; memberIndex < members.length; memberIndex++) list.push(members[memberIndex]);
		}
		candidates = list;
	}

	function summary(area) {
		if (rev < 0) return "";
		var climate = app.areaClimateText(area);
		if (climate) return climate;
		var temperatureId = app.areaSensor(area, "temperature"), humidityId = app.areaSensor(area, "humidity");
		if (!temperatureId && !humidityId) return "niet ingesteld";
		return "nog geen waarde";
	}

	function choose(id) {
		var area = currentArea();
		app.setAreaSensor(area, kind, app.areaSensor(area, kind) === id ? "" : id);
	}

	// ---- the areas ----
	ListView {
		id: areaList
		width: isNxt ? 300 : 230
		anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: isNxt ? 20 : 14; topMargin: isNxt ? 16 : 10; bottomMargin: isNxt ? 16 : 10 }
		spacing: 4
		clip: true
		boundsBehavior: Flickable.StopAtBounds
		model: areas
		delegate: Rectangle {
			property bool selected: index === areaSetupScreen.areaIndex
			width: areaList.width
			height: isNxt ? 60 : 48
			radius: 8
			color: selected ? "#fde7c2" : (areaMouse.pressed ? "#ececec" : "transparent")
			Column {
				anchors { left: parent.left; right: parent.right; leftMargin: 12; rightMargin: 8; verticalCenter: parent.verticalCenter }
				Text {
					width: parent.width
					elide: Text.ElideRight
					font.family: selected ? qfont.bold.name : qfont.regular.name
					font.pixelSize: isNxt ? 17 : 14
					color: selected ? "#7a4500" : "#1d1d1b"
					text: modelData.label
				}
				Text {
					width: parent.width
					elide: Text.ElideRight
					font.family: qfont.regular.name
					font.pixelSize: isNxt ? 14 : 12
					color: "#8a8a8a"
					text: summary(modelData.key)
				}
			}
			MouseArea {
				id: areaMouse
				anchors.fill: parent
				onClicked: { areaSetupScreen.areaIndex = index; refresh(); }
			}
		}
	}

	Text {
		visible: areas.length === 0
		anchors { left: areaList.left; right: areaList.right; top: areaList.top; topMargin: 20 }
		wrapMode: Text.WordWrap
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 15 : 12
		color: "#8a8a8a"
		text: app.loadingAll ? "Ruimtes ophalen…" : "Geen ruimtes in Home Assistant"
	}

	Rectangle {
		id: divider
		width: 1
		color: "#d6d6d6"
		anchors { top: areaList.top; bottom: areaList.bottom; left: areaList.right; leftMargin: isNxt ? 14 : 10 }
	}

	// ---- temperature or humidity ----
	Row {
		id: kindRow
		spacing: isNxt ? 10 : 8
		anchors { left: divider.right; leftMargin: isNxt ? 20 : 14; top: areaList.top }
		Repeater {
			model: [{key: "temperature", label: "Temperatuur"}, {key: "humidity", label: "Luchtvochtigheid"}]
			Rectangle {
				property bool selected: areaSetupScreen.kind === modelData.key
				width: kindLabel.implicitWidth + (isNxt ? 32 : 24)
				height: isNxt ? 40 : 32
				radius: height / 2
				color: selected ? "#f5a623" : (kindMouse.pressed ? "#e4e4e4" : "#ffffff")
				border.color: selected ? "#f5a623" : "#d0d0d0"
				Text {
					id: kindLabel
					anchors.centerIn: parent
					font.family: qfont.semiBold.name
					font.pixelSize: isNxt ? 16 : 13
					color: selected ? "#ffffff" : "#3c3c3a"
					text: modelData.label + (rev >= 0 && app.areaSensor(currentArea(), modelData.key) ? " ✓" : "")
				}
				MouseArea {
					id: kindMouse
					anchors.fill: parent
					onClicked: { areaSetupScreen.kind = modelData.key; refresh(); }
				}
			}
		}
	}

	Text {
		id: hint
		anchors { left: kindRow.left; right: parent.right; rightMargin: isNxt ? 20 : 14; top: kindRow.bottom; topMargin: isNxt ? 10 : 8 }
		wrapMode: Text.WordWrap
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 15 : 12
		color: "#6b6b6b"
		text: (kind === "temperature" ? "De temperatuur" : "De luchtvochtigheid") + " van " + (areas.length > 0 ? areas[Math.min(areaIndex, areas.length - 1)].label : "de ruimte")
			+ ": komt onder de naam op het tabblad. Nog eens tikken haalt hem weg."
	}

	ListView {
		id: candidateList
		anchors { left: hint.left; right: hint.right; top: hint.bottom; topMargin: 8; bottom: areaList.bottom }
		clip: true
		spacing: 2
		boundsBehavior: Flickable.StopAtBounds
		model: candidates
		delegate: Rectangle {
			property bool header: modelData.header === true
			width: candidateList.width
			height: header ? (isNxt ? 34 : 28) : (isNxt ? 54 : 44)
			radius: 6
			color: header ? "transparent" : (candidateMouse.pressed ? "#ececec" : (modelData.chosen ? "#fff6e6" : "#ffffff"))
			border.color: header ? "transparent" : (modelData.chosen ? "#f5a623" : "#e8e8e8")
			// an area's header
			Text {
				visible: header
				anchors { left: parent.left; leftMargin: 4; right: parent.right; bottom: parent.bottom; bottomMargin: 4 }
				elide: Text.ElideRight
				font.family: qfont.bold.name
				font.pixelSize: isNxt ? 15 : 12
				color: "#7a4500"
				text: header ? modelData.label : ""
			}
			Rectangle {
				id: radio
				visible: !header
				width: isNxt ? 24 : 20
				height: width
				radius: width / 2
				anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
				color: "#ffffff"
				border.width: 2
				border.color: modelData.chosen ? "#f5a623" : "#b0b0b0"
				Rectangle {
					visible: modelData.chosen === true
					anchors.centerIn: parent
					width: parent.width * 0.5
					height: width
					radius: width / 2
					color: "#f5a623"
				}
			}
			Column {
				visible: !header
				anchors { left: radio.right; leftMargin: 10; right: valueText.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
				Text {
					width: parent.width
					elide: Text.ElideRight
					font.family: qfont.semiBold.name
					font.pixelSize: isNxt ? 16 : 13
					color: "#1d1d1b"
					text: header ? "" : modelData.name
				}
				Text {
					width: parent.width
					elide: Text.ElideRight
					font.family: qfont.regular.name
					font.pixelSize: isNxt ? 13 : 11
					color: "#8a8a8a"
					text: header ? "" : modelData.id
				}
			}
			Text {
				id: valueText
				visible: !header
				anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
				font.family: qfont.regular.name
				font.pixelSize: isNxt ? 15 : 12
				color: "#6b6b6b"
				text: header ? "" : modelData.state + (modelData.unit ? " " + modelData.unit : "")
			}
			MouseArea {
				id: candidateMouse
				enabled: !header
				anchors.fill: parent
				onClicked: choose(modelData.id)
			}
		}
	}

	Text {
		visible: candidates.length === 0
		anchors { left: hint.left; right: hint.right; top: hint.bottom; topMargin: 30 }
		horizontalAlignment: Text.AlignHCenter
		wrapMode: Text.WordWrap
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 17 : 14
		color: "#8a8a8a"
		text: app.loadingAll ? "Entiteiten ophalen…" : (kind === "temperature" ? "Geen temperatuursensoren in Home Assistant" : "Geen luchtvochtigheidssensoren in Home Assistant")
	}
}
