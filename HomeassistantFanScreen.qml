import QtQuick 2.1
import qb.components 1.0

// a fan: on/off, the speed (slider, - and + in the fan's own steps), presets, oscillation and direction,
// each only when the fan has it. The speed goes to Home Assistant when you let go of the slider.
Screen {
	id: fanScreen

	screenTitle: "Ventilator"

	property string entityId: ""
	property int rev: 0
	property bool isOn: false
	property int percent: 0
	property int fontSize: isNxt ? 20 : 16

	onShown: {
		if (args && args.entityId) entityId = args.entityId;
		screenTitle = app.displayName(entityId);
		app.statesUpdated.connect(update);
		update();
		app.pollStates();
	}
	onHidden: app.statesUpdated.disconnect(update)

	// the button rows are only rebuilt when they change (chipRev): a redraw would drop a tap that is going on,
	// and other entities (a power meter every few seconds) bring updates too
	property int chipRev: 0
	property string chipKey: ""

	function update() {
		rev++;
		var key = entityId + JSON.stringify([app.attr(entityId, "preset_modes"), app.haStates[entityId] ? app.haStates[entityId].features : 0]);
		if (key !== chipKey) { chipKey = key; chipRev++; }
		var entry = app.haStates[entityId];
		isOn = entry ? entry.state === "on" : false;
		if (!speedSlider.dragging) {
			var percentage = app.attr(entityId, "percentage");
			percent = isOn && typeof percentage === "number" ? Math.round(percentage) : 0;
			speedSlider.value = percent / 100;
		}
	}

	function stepTo(delta) {
		var step = app.fanStep(entityId);
		var percentage = Math.max(0, Math.min(100, percent + delta * step));
		percent = percentage;
		speedSlider.value = percentage / 100;
		app.fanSetPercentage(entityId, percentage);
	}

	// ---- icon, state, on/off ----
	Image {
		id: icon
		width: isNxt ? 56 : 44
		height: width
		sourceSize.width: width
		sourceSize.height: height
		source: Qt.resolvedUrl("drawables/icons/fan" + (isOn ? "-on" : "") + ".svg")
		anchors { top: parent.top; topMargin: isNxt ? 24 : 18; left: parent.left; leftMargin: isNxt ? 60 : 44 }
	}
	Text {
		anchors { left: icon.right; leftMargin: isNxt ? 20 : 14; verticalCenter: icon.verticalCenter }
		font.family: qfont.bold.name
		font.pixelSize: isNxt ? 30 : 24
		color: "#000000"
		text: rev >= 0 ? app.stateText(entityId) : ""
	}
	Rectangle {
		id: onOff
		width: isNxt ? 110 : 88
		height: isNxt ? 50 : 40
		radius: height / 2
		color: isOn ? "#f5a623" : "#c8c8c8"
		anchors { right: parent.right; rightMargin: isNxt ? 60 : 44; verticalCenter: icon.verticalCenter }
		Rectangle {
			width: parent.height - 8
			height: width
			radius: width / 2
			color: "#ffffff"
			anchors.verticalCenter: parent.verticalCenter
			x: isOn ? parent.width - width - 4 : 4
			Behavior on x { NumberAnimation { duration: 120 } }
		}
		MouseArea { anchors.fill: parent; onClicked: app.fanPower(entityId, !isOn) }
	}

	Column {
		anchors { left: icon.left; right: onOff.right; top: icon.bottom; topMargin: isNxt ? 30 : 20 }
		spacing: isNxt ? 22 : 14

		// ---- speed ----
		Column {
			visible: rev >= 0 && app.fanSupports(entityId, "speed")
			width: parent.width
			spacing: isNxt ? 8 : 5
			Text {
				font.family: qfont.regular.name
				font.pixelSize: fanScreen.fontSize
				color: "#6b6b6b"
				text: "Snelheid " + percent + "%"
			}
			Row {
				spacing: isNxt ? 16 : 12
				HaRoundButton { anchors.verticalCenter: parent.verticalCenter; icon: "minus"; onClicked: stepTo(-1) }
				HaSlider {
					id: speedSlider
					width: fanScreen.width - 2 * (isNxt ? 60 : 44) - 2 * (isNxt ? 48 : 38) - 2 * parent.spacing
					anchors.verticalCenter: parent.verticalCenter
					fillToKnob: true
					onMoved: percent = Math.round(value * 100)
					onReleased: app.fanSetPercentage(entityId, value * 100)
				}
				HaRoundButton { anchors.verticalCenter: parent.verticalCenter; icon: "plus"; onClicked: stepTo(1) }
			}
		}

		// ---- presets, oscillation, direction: rows of buttons ----
		Repeater {
			model: [{kind: "preset", label: "Stand"}, {kind: "oscillate", label: "Zwenken"}, {kind: "direction", label: "Richting"}]
			// the label, then the buttons: on more lines when they don't fit on one
			Item {
				id: chipRow
				width: parent.width
				height: chipFlow.height
				property string kind: modelData.kind
				property variant chips: {
					if (chipRev < 0) return [];
					if (kind === "preset") {
						var list = app.fanSupports(entityId, "preset") ? (app.attr(entityId, "preset_modes") || []) : [];
						var out = [];
						for (var i = 0; i < list.length; i++) out.push({value: list[i], label: app.presetText(list[i])});
						return out;
					}
					if (kind === "oscillate") return app.fanSupports(entityId, "oscillate") ? [{value: false, label: "Uit"}, {value: true, label: "Aan"}] : [];
					return app.fanSupports(entityId, "direction") ? [{value: "forward", label: "Vooruit"}, {value: "reverse", label: "Achteruit"}] : [];
				}
				visible: chips.length > 0
				Text {
					width: isNxt ? 120 : 90
					y: ((isNxt ? 44 : 36) - height) / 2
					font.family: qfont.regular.name
					font.pixelSize: fanScreen.fontSize - 2
					color: "#6b6b6b"
					text: modelData.label
				}
				Flow {
					id: chipFlow
					x: (isNxt ? 120 : 90) + (isNxt ? 10 : 7)
					width: parent.width - x
					spacing: isNxt ? 10 : 7
					Repeater {
						model: chipRow.chips
						Rectangle {
							property bool picked: {
								if (rev < 0) return false;
								if (chipRow.kind === "preset") return app.attr(entityId, "preset_mode") === modelData.value;
								if (chipRow.kind === "oscillate") return (app.attr(entityId, "oscillating") === true) === modelData.value;
								return app.attr(entityId, "direction") === modelData.value;
							}
							width: chipText.implicitWidth + (isNxt ? 30 : 22)
							height: isNxt ? 44 : 36
							radius: height / 2
							color: picked ? "#f5a623" : (chipMouse.pressed ? "#d8d8d8" : "#f0f0f0")
							border.color: picked ? "#f5a623" : "#d6d6d6"
							Text {
								id: chipText
								anchors.centerIn: parent
								font.family: qfont.semiBold.name
								font.pixelSize: isNxt ? 16 : 13
								color: parent.picked ? "#ffffff" : "#1d1d1b"
								text: modelData.label
							}
							MouseArea {
								id: chipMouse
								anchors.fill: parent
								onClicked: {
									if (chipRow.kind === "preset") app.fanSetPreset(entityId, modelData.value);
									else if (chipRow.kind === "oscillate") app.fanOscillate(entityId, modelData.value);
									else app.fanDirection(entityId, modelData.value);
								}
							}
						}
					}
				}
			}
		}
	}
}
