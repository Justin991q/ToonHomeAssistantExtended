import QtQuick 2.1
import qb.components 1.0

// a number that can be set (number, input_number): the value with - and +, in the entity's own steps, and
// as Home Assistant shows it: a slider (mode "slider", and "auto"), or a box to type the value in (mode "box").
// A counter is a number too: - and + count by its own step (counter.decrement / increment, at once), Reset
// puts it back to its initial value, and a count can be typed.
// And a choice (select, input_select): its options as buttons.
// A number goes to Home Assistant when you let go of the slider, a moment after the last tap on - or +, or
// when you typed it.
Screen {
	id: inputScreen

	screenTitle: "Instellen"

	property string entityId: ""
	property bool counter: entityId.indexOf("counter.") === 0
	property bool numeric: counter || entityId.indexOf("number.") === 0 || entityId.indexOf("input_number.") === 0
	property bool bounded: true               // has a lowest and a highest value (a counter may have none)
	property int rev: 0
	property real minValue: 0
	property real maxValue: 100
	property real step: 1
	property real shownValue: 0               // the number on the screen
	property string unit: ""
	property bool boxMode: false              // Home Assistant's mode "box": the value is typed, no slider
	property string currentOption: ""
	property bool editing: sendTimer.running || valueSlider.dragging    // our own taps win over an update until they are sent
	property int fontSize: isNxt ? 20 : 16
	property int sideMargin: isNxt ? 60 : 44

	// the option buttons are only rebuilt when the options change: a redraw would drop a tap that is going on
	property variant options: []
	property string optionsKey: ""

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

	function numberOr(value, fallback) { return typeof value === "number" ? value : fallback; }

	function update() {
		rev++;
		var entry = app.haStates[entityId];
		if (!numeric) {
			currentOption = entry ? entry.state : "";
			var optionList = app.attr(entityId, "options") || [];
			var key = entityId + JSON.stringify(optionList);
			if (key !== optionsKey) { optionsKey = key; options = optionList; }
			return;
		}
		unit = entry ? entry.unit : "";
		if (counter) {
			bounded = typeof app.attr(entityId, "minimum") === "number" && typeof app.attr(entityId, "maximum") === "number";
			minValue = numberOr(app.attr(entityId, "minimum"), -2000000000);
			maxValue = numberOr(app.attr(entityId, "maximum"), 2000000000);
		} else {
			bounded = true;
			minValue = numberOr(app.attr(entityId, "min"), 0);
			maxValue = numberOr(app.attr(entityId, "max"), 100);
		}
		step = numberOr(app.attr(entityId, "step"), 1);
		if (step <= 0) step = 1;
		boxMode = counter || app.attr(entityId, "mode") === "box";
		if (editing) return;
		var valueNow = entry ? parseFloat(entry.state) : NaN;
		if (!isNaN(valueNow)) show(valueNow);
	}

	// within the entity's range, and on its own steps. In a box any value goes (Home Assistant takes a typed
	// "21,37" with steps of 1 too): only the range counts there
	function snap(value) {
		var stepped = counter ? Math.round(value) : (boxMode ? value : minValue + Math.round((value - minValue) / step) * step);
		return Math.max(minValue, Math.min(maxValue, Math.round(stepped * 10000) / 10000));
	}

	// how many decimals a number has, at most 4: 21 -> 0, 21.5 -> 1, 21.37 -> 2
	function decimalsOf(number) {
		var fraction = String(Math.round(Math.abs(number) * 10000) / 10000).split(".")[1];
		return fraction ? fraction.length : 0;
	}

	// what was typed -> a number, or NaN: "21,5", "21.5", "1.250,5", " -3,25 "
	function parseTyped(typedText) {
		var cleaned = String(typedText).replace(/\s/g, "");
		if (cleaned.indexOf(",") >= 0) cleaned = cleaned.replace(/\./g, "").replace(",", ".");     // a comma is the decimal sign: dots group thousands
		return /^-?\d*\.?\d+$/.test(cleaned) ? parseFloat(cleaned) : NaN;
	}

	function show(value) {
		shownValue = snap(value);
		valueSlider.value = maxValue > minValue ? (shownValue - minValue) / (maxValue - minValue) : 0;
	}

	function stepBy(direction) {
		show(shownValue + direction * step);
		// a counter counts itself: every tap is its own command
		if (counter) app.counterCommand(entityId, direction > 0 ? "increment" : "decrement");
		else sendTimer.restart();
	}

	function send() {
		if (counter) app.counterSetValue(entityId, shownValue);
		else app.numberSetValue(entityId, shownValue);
	}

	function rangeText() { return bounded ? valueText(minValue) + " – " + valueText(maxValue) : ""; }

	// the box: the value typed on the Toon's keyboard, with a comma or a point ("21,5", "21.37"), kept as
	// typed (within the range) and sent at once
	function typeValue() {
		qkeyboard.open(screenTitle + (bounded ? " (" + rangeText() + ")" : ""), String(shownValue).replace(".", ","), function(typedText) {
			var typedValue = parseTyped(typedText);
			if (isNaN(typedValue)) return;
			show(typedValue);
			sendTimer.stop();
			send();
		});
	}

	function valueText(value) {
		// as many decimals as the steps have; in a box as many as the value itself has, when that is more
		var decimals = decimalsOf(step);
		if (boxMode) decimals = Math.max(decimals, decimalsOf(value));
		return i18n.number(value, decimals, 0) + (unit ? " " + unit : "");
	}

	Timer { id: sendTimer; interval: 1200; onTriggered: send() }

	// ---- a number ----
	Column {
		visible: numeric
		anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: sideMargin; rightMargin: sideMargin; topMargin: isNxt ? 50 : 36 }
		spacing: isNxt ? 30 : 22

		Text {
			anchors.horizontalCenter: parent.horizontalCenter
			font.family: qfont.bold.name
			font.pixelSize: isNxt ? 64 : 50
			color: "#9a5a06"
			text: valueText(shownValue)
		}
		Row {
			anchors.horizontalCenter: parent.horizontalCenter
			spacing: boxMode ? (isNxt ? 28 : 20) : (isNxt ? 16 : 12)
			HaRoundButton { id: minusButton; anchors.verticalCenter: parent.verticalCenter; icon: "minus"; enabled: shownValue > minValue; onClicked: stepBy(-1) }
			HaSlider {
				id: valueSlider
				visible: !boxMode
				width: inputScreen.width - 2 * sideMargin - 2 * minusButton.width - 2 * parent.spacing
				anchors.verticalCenter: parent.verticalCenter
				fillToKnob: true
				onMoved: shownValue = snap(minValue + value * (maxValue - minValue))
				onReleased: { show(shownValue); sendTimer.stop(); send(); }
			}
			StandardButton {
				visible: boxMode
				anchors.verticalCenter: parent.verticalCenter
				text: "Waarde invoeren"
				onClicked: typeValue()
			}
			HaRoundButton { anchors.verticalCenter: parent.verticalCenter; icon: "plus"; enabled: shownValue < maxValue; onClicked: stepBy(1) }
		}
		StandardButton {
			visible: counter
			anchors.horizontalCenter: parent.horizontalCenter
			text: "Reset"
			onClicked: app.counterCommand(entityId, "reset")
		}
		Text {
			anchors.horizontalCenter: parent.horizontalCenter
			font.family: qfont.regular.name
			font.pixelSize: inputScreen.fontSize - 2
			color: "#8a8a8a"
			visible: bounded
			text: rangeText()
		}
	}

	// ---- a choice: the options as buttons, scrolling when there are many ----
	Flickable {
		id: optionsView
		visible: !numeric
		anchors { fill: parent; leftMargin: sideMargin; rightMargin: sideMargin; topMargin: isNxt ? 30 : 20; bottomMargin: isNxt ? 20 : 14 }
		clip: true
		contentHeight: optionFlow.height
		boundsBehavior: Flickable.StopAtBounds

		Flow {
			id: optionFlow
			width: optionsView.width
			spacing: isNxt ? 12 : 9
			Repeater {
				model: inputScreen.options
				Rectangle {
					property bool picked: inputScreen.currentOption === modelData
					width: Math.min(optionFlow.width, optionText.implicitWidth + (isNxt ? 40 : 30))
					height: isNxt ? 52 : 42
					radius: height / 2
					color: picked ? "#f5a623" : (optionMouse.pressed ? "#d8d8d8" : "#f0f0f0")
					border.color: picked ? "#f5a623" : "#d6d6d6"
					Text {
						id: optionText
						anchors.centerIn: parent
						width: Math.min(implicitWidth, parent.width - (isNxt ? 24 : 18))
						elide: Text.ElideRight
						font.family: qfont.semiBold.name
						font.pixelSize: isNxt ? 18 : 15
						color: parent.picked ? "#ffffff" : "#1d1d1b"
						text: modelData
					}
					MouseArea {
						id: optionMouse
						anchors.fill: parent
						onClicked: app.selectOption(entityId, modelData)
					}
				}
			}
		}
	}

	Text {
		visible: !numeric && inputScreen.options.length === 0
		anchors.centerIn: parent
		font.family: qfont.regular.name
		font.pixelSize: inputScreen.fontSize
		color: "#6b6b6b"
		text: "Geen keuzes bekend"
	}
}
