import QtQuick 2.1
import qb.components 1.0

// the Energie tab's entities, apart from the cards: left the parts (power now, meter readings), right the
// entities of Home Assistant with a fitting unit. Tap to add or remove; more than one is summed (e.g. the
// two tariffs of a smart meter). Saved at once.
Screen {
	id: energySetupScreen

	screenTitle: "Energie instellen"

	property variant fields: app.energyFields()
	property int fieldIndex: 0
	property int rev: 0
	property variant candidates: []

	onShown: {
		app.allEntitiesLoaded.connect(refresh);
		app.selectionChanged.connect(refresh);
		if (app.allEntities.length === 0) app.loadAllEntities();
		refresh();
	}
	onHidden: {
		app.allEntitiesLoaded.disconnect(refresh);
		app.selectionChanged.disconnect(refresh);
	}

	function refresh() {
		rev++;
		var f = fields[fieldIndex];
		var chosen = app.energy[f.key] || [];
		var out = [];
		for (var i = 0; i < app.allEntities.length; i++) {
			var e = app.allEntities[i];
			if (f.units.indexOf(e.unit) < 0 && chosen.indexOf(e.id) < 0) continue;
			out.push({id: e.id, name: e.name || e.id, state: e.state, unit: e.unit, chosen: chosen.indexOf(e.id) >= 0});
		}
		// the chosen ones first, then by name
		out.sort(function(a, b) {
			if (a.chosen !== b.chosen) return a.chosen ? -1 : 1;
			return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : (a.name.toLowerCase() > b.name.toLowerCase() ? 1 : 0);
		});
		candidates = out;
	}

	function summary(key) {
		var list = rev >= 0 ? (app.energy[key] || []) : [];
		if (list.length === 0) return "niet ingesteld";
		if (list.length === 1) return app.displayName(list[0]);
		return list.length + " entiteiten (opgeteld)";
	}

	function toggle(id) {
		var key = fields[fieldIndex].key;
		var list = (app.energy[key] || []).slice(0);
		var i = list.indexOf(id);
		if (i >= 0) list.splice(i, 1); else list.push(id);
		app.setEnergyField(key, list);
	}

	// ---- the parts ----
	ListView {
		id: fieldList
		width: isNxt ? 360 : 280
		anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: isNxt ? 20 : 14; topMargin: isNxt ? 16 : 10; bottomMargin: isNxt ? 16 : 10 }
		spacing: 4
		clip: true
		boundsBehavior: Flickable.StopAtBounds
		model: fields
		delegate: Rectangle {
			property bool selected: index === energySetupScreen.fieldIndex
			width: fieldList.width
			height: isNxt ? 60 : 48
			radius: 8
			color: selected ? "#fde7c2" : (fieldMouse.pressed ? "#ececec" : "transparent")
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
				id: fieldMouse
				anchors.fill: parent
				onClicked: { energySetupScreen.fieldIndex = index; refresh(); }
			}
		}
	}

	Rectangle {
		id: divider
		width: 1
		color: "#d6d6d6"
		anchors { top: fieldList.top; bottom: fieldList.bottom; left: fieldList.right; leftMargin: isNxt ? 14 : 10 }
	}

	// ---- the entities that fit ----
	Text {
		id: hint
		anchors { left: divider.right; leftMargin: isNxt ? 20 : 14; right: parent.right; rightMargin: isNxt ? 20 : 14; top: fieldList.top }
		wrapMode: Text.WordWrap
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 15 : 12
		color: "#6b6b6b"
		text: fields[fieldIndex].total
			? "Een meterstand die oploopt (" + fields[fieldIndex].units.join(", ") + "). Het verbruik van vandaag rekent de app zelf uit."
			: "Het vermogen nu (" + fields[fieldIndex].units.join(", ") + ")."
	}

	ListView {
		id: candidateList
		anchors { left: hint.left; right: hint.right; top: hint.bottom; topMargin: 8; bottom: fieldList.bottom }
		clip: true
		spacing: 2
		boundsBehavior: Flickable.StopAtBounds
		model: candidates
		delegate: Rectangle {
			width: candidateList.width
			height: isNxt ? 54 : 44
			radius: 6
			color: candMouse.pressed ? "#ececec" : (modelData.chosen ? "#fff6e6" : "#ffffff")
			border.color: modelData.chosen ? "#f5a623" : "#e8e8e8"
			Rectangle {
				id: check
				width: isNxt ? 26 : 22
				height: width
				radius: 4
				anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
				color: modelData.chosen ? "#f5a623" : "#ffffff"
				border.color: modelData.chosen ? "#f5a623" : "#b0b0b0"
				Text {
					visible: modelData.chosen
					anchors.centerIn: parent
					font.family: qfont.bold.name
					font.pixelSize: parent.height * 0.75
					color: "#ffffff"
					text: "✓"
				}
			}
			Column {
				anchors { left: check.right; leftMargin: 10; right: valueText.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
				Text {
					width: parent.width
					elide: Text.ElideRight
					font.family: qfont.semiBold.name
					font.pixelSize: isNxt ? 16 : 13
					color: "#1d1d1b"
					text: modelData.name
				}
				Text {
					width: parent.width
					elide: Text.ElideRight
					font.family: qfont.regular.name
					font.pixelSize: isNxt ? 13 : 11
					color: "#8a8a8a"
					text: modelData.id
				}
			}
			Text {
				id: valueText
				anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
				font.family: qfont.regular.name
				font.pixelSize: isNxt ? 15 : 12
				color: "#6b6b6b"
				text: modelData.state + (modelData.unit ? " " + modelData.unit : "")
			}
			MouseArea {
				id: candMouse
				anchors.fill: parent
				onClicked: toggle(modelData.id)
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
		text: app.loadingAll ? "Entiteiten ophalen…" : "Geen entiteiten met deze eenheid in Home Assistant"
	}
}
