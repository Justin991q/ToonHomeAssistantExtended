import QtQuick 2.1
import qb.components 1.0

// a thermostat (climate) or a humidifier: the value now, the target with - and +, the mode and the presets.
// - and + only change the screen; the target goes to Home Assistant a moment after the last tap.
Screen {
	id: climateScreen

	screenTitle: "Thermostaat"

	property string entityId: ""
	property bool humidifier: entityId.indexOf("humidifier.") === 0
	property int rev: 0
	property string haState: ""
	// the target(s) on the screen: one, or low/high for a range (heat_cool)
	property bool range: false
	property real target: 0
	property real low: 0
	property real high: 0
	property real minValue: humidifier ? 0 : 7
	property real maxValue: humidifier ? 100 : 35
	property real step: humidifier ? 1 : 0.5
	property bool editing: sendTimer.running    // our own taps win over a poll until they are sent
	property int fontSize: isNxt ? 20 : 16

	onShown: {
		if (args && args.entityId) entityId = args.entityId;
		screenTitle = app.displayName(entityId);
		app.statesUpdated.connect(update);
		update();
		app.pollStates();
	}
	onHidden: {
		if (sendTimer.running) { sendTimer.stop(); send(); }
		app.statesUpdated.disconnect(update);
	}

	function num(v, fallback) { return typeof v === "number" ? v : fallback; }

	function update() {
		rev++;
		var s = app.haStates[entityId];
		haState = s ? s.state : "";
		if (humidifier) {
			minValue = num(app.attr(entityId, "min_humidity"), 0);
			maxValue = num(app.attr(entityId, "max_humidity"), 100);
			step = 1;
		} else {
			minValue = num(app.attr(entityId, "min_temp"), 7);
			maxValue = num(app.attr(entityId, "max_temp"), 35);
			step = num(app.attr(entityId, "target_temp_step"), 0.5);
		}
		if (editing) return;
		var t = app.attr(entityId, humidifier ? "humidity" : "temperature");
		var lo = app.attr(entityId, "target_temp_low"), hi = app.attr(entityId, "target_temp_high");
		range = !humidifier && typeof t !== "number" && typeof lo === "number" && typeof hi === "number";
		if (typeof t === "number") target = t;
		if (range) { low = lo; high = hi; }
	}

	function hasTarget() {
		if (humidifier) return typeof app.attr(entityId, "humidity") === "number";
		return range || typeof app.attr(entityId, "temperature") === "number";
	}

	function clamp(v) {
		v = Math.round(v / step) * step;
		return Math.max(minValue, Math.min(maxValue, Math.round(v * 10) / 10));
	}

	function change(which, delta) {
		if (which === "low") low = Math.min(clamp(low + delta), high);
		else if (which === "high") high = Math.max(clamp(high + delta), low);
		else target = clamp(target + delta);
		sendTimer.restart();
	}

	function send() {
		if (humidifier) app.humidifierSetHumidity(entityId, target);
		else if (range) app.climateSetRange(entityId, low, high);
		else app.climateSetTemperature(entityId, target);
	}

	function valueText(v) { return humidifier ? Math.round(v) + "%" : app.degrees(v); }

	// the mode buttons: [{value, label}] and which one is on
	function modeList() {
		if (rev < 0) return [];
		if (humidifier) return [{value: "off", label: "Uit"}, {value: "on", label: "Aan"}];
		var modes = app.attr(entityId, "hvac_modes") || [];
		var out = [];
		for (var i = 0; i < modes.length; i++) out.push({value: modes[i], label: app.hvacModeText(modes[i])});
		return out;
	}
	function presetList() {
		if (rev < 0) return [];
		var list = app.attr(entityId, humidifier ? "available_modes" : "preset_modes") || [];
		var out = [];
		for (var i = 0; i < list.length; i++) out.push({value: list[i], label: app.presetText(list[i])});
		return out;
	}
	function currentPreset() { return rev >= 0 ? (app.attr(entityId, humidifier ? "mode" : "preset_mode") || "") : ""; }

	function pickMode(v) {
		if (humidifier) app.humidifierPower(entityId, v === "on");
		else app.climateSetMode(entityId, v);
	}
	function pickPreset(v) {
		if (humidifier) app.humidifierSetMode(entityId, v);
		else app.climateSetPreset(entityId, v);
	}

	Timer { id: sendTimer; interval: 1200; onTriggered: send() }

	// ---- now ----
	Column {
		id: nowColumn
		width: isNxt ? 240 : 190
		anchors { left: parent.left; leftMargin: isNxt ? 50 : 36; top: parent.top; topMargin: isNxt ? 40 : 28 }
		spacing: isNxt ? 4 : 2
		Text {
			font.family: qfont.regular.name
			font.pixelSize: climateScreen.fontSize
			color: "#6b6b6b"
			text: humidifier ? "Luchtvochtigheid nu" : "Temperatuur nu"
		}
		Text {
			font.family: qfont.bold.name
			font.pixelSize: isNxt ? 64 : 50
			color: "#1d1d1b"
			text: rev >= 0 ? (humidifier ? (typeof app.attr(entityId, "current_humidity") === "number" ? Math.round(app.attr(entityId, "current_humidity")) + "%" : "-")
				: app.degrees(app.attr(entityId, "current_temperature"))) : ""
		}
		Text {
			width: parent.width
			wrapMode: Text.WordWrap
			font.family: qfont.semiBold.name
			font.pixelSize: climateScreen.fontSize
			color: rev >= 0 && app.isLit(entityId) ? "#9a5a06" : "#6b6b6b"
			text: {
				if (rev < 0) return "";
				if (humidifier) return haState === "on" ? (app.attr(entityId, "action") === "humidifying" ? "Bevochtigt" : (app.attr(entityId, "action") === "drying" ? "Droogt" : "Aan")) : "Uit";
				var a = app.hvacActionText(app.attr(entityId, "hvac_action"));
				return a ? a.charAt(0).toUpperCase() + a.substring(1) : app.hvacModeText(haState);
			}
		}
		Text {
			visible: !humidifier && rev >= 0 && typeof app.attr(entityId, "current_humidity") === "number"
			font.family: qfont.regular.name
			font.pixelSize: climateScreen.fontSize - 2
			color: "#8a8a8a"
			text: visible ? "Luchtvochtigheid " + Math.round(app.attr(entityId, "current_humidity")) + "%" : ""
		}
	}

	// ---- target: - value + (or low and high) ----
	Column {
		id: targetColumn
		visible: rev >= 0 && hasTarget() && haState !== "off"
		anchors { left: nowColumn.right; right: parent.right; rightMargin: isNxt ? 50 : 36; top: nowColumn.top }
		spacing: isNxt ? 14 : 10

		Repeater {
			model: range ? [{which: "low", label: "Laag"}, {which: "high", label: "Hoog"}] : [{which: "target", label: humidifier ? "Gewenst" : "Gewenste temperatuur"}]
			Item {
				width: targetColumn.width
				height: range ? (isNxt ? 80 : 64) : (isNxt ? 120 : 96)
				Text {
					anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
					font.family: qfont.regular.name
					font.pixelSize: climateScreen.fontSize
					color: "#6b6b6b"
					text: modelData.label
				}
				Row {
					anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
					spacing: isNxt ? 28 : 20
					HaRoundButton {
						width: isNxt ? 64 : 50
						anchors.verticalCenter: parent.verticalCenter
						icon: "minus"
						onClicked: change(modelData.which, -step)
					}
					Text {
						width: isNxt ? 170 : 130
						horizontalAlignment: Text.AlignHCenter
						anchors.verticalCenter: parent.verticalCenter
						font.family: qfont.bold.name
						font.pixelSize: range ? (isNxt ? 40 : 32) : (isNxt ? 56 : 44)
						color: "#9a5a06"
						text: valueText(modelData.which === "low" ? low : (modelData.which === "high" ? high : target))
					}
					HaRoundButton {
						width: isNxt ? 64 : 50
						anchors.verticalCenter: parent.verticalCenter
						icon: "plus"
						onClicked: change(modelData.which, step)
					}
				}
			}
		}
	}

	// ---- mode and presets ----
	Column {
		anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: isNxt ? 50 : 36; rightMargin: isNxt ? 50 : 36; bottomMargin: isNxt ? 30 : 20 }
		spacing: isNxt ? 12 : 8

		Repeater {
			model: [{kind: "mode", label: humidifier ? "Aan/uit" : "Stand"}, {kind: "preset", label: humidifier ? "Modus" : "Voorkeur"}]
			// the label, then the buttons: on more lines when they don't fit on one
			Item {
				id: chipRow
				width: parent.width
				height: chipFlow.height
				property string kind: modelData.kind
				property variant chips: modelData.kind === "mode" ? modeList() : presetList()
				visible: chips.length > 0
				Text {
					width: isNxt ? 120 : 90
					y: ((isNxt ? 44 : 36) - height) / 2
					font.family: qfont.regular.name
					font.pixelSize: climateScreen.fontSize - 2
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
							property bool picked: chipRow.kind === "mode" ? haState === modelData.value : currentPreset() === modelData.value
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
								onClicked: chipRow.kind === "mode" ? pickMode(modelData.value) : pickPreset(modelData.value)
							}
						}
					}
				}
			}
		}
	}
}
