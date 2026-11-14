import QtQuick 2.1
import qb.components 1.0

// one light: on/off, brightness, and colour / colour temperature when the lamp supports them
Screen {
	id: homeassistantLightScreen

	screenTitle: "Lamp"

	property string entityId: ""
	property bool isOn: false
	property bool dimmable: false
	property bool hasColor: false
	property bool hasColorTemp: false
	property int percent: 0
	property real minKelvin: 2000
	property real maxKelvin: 6500
	property int fontSize: isNxt ? 20 : 16
	property int sliderWidth: isNxt ? 560 : 440

	// colour buttons: white (no saturation) and the usual colours
	property variant swatches: [
		{hue: 0, sat: 0, color: "#ffffff"}, {hue: 0, sat: 100, color: "#ff0000"}, {hue: 30, sat: 100, color: "#ff8000"},
		{hue: 55, sat: 100, color: "#ffea00"}, {hue: 120, sat: 100, color: "#00d000"}, {hue: 180, sat: 100, color: "#00e0e0"},
		{hue: 230, sat: 100, color: "#2050ff"}, {hue: 280, sat: 100, color: "#a040ff"}, {hue: 320, sat: 100, color: "#ff40b0"}]

	onShown: {
		if (args && args.entityId) entityId = args.entityId;
		screenTitle = app.displayName(entityId);
		app.statesUpdated.connect(update);
		update();
		app.pollStates();
	}
	onHidden: app.statesUpdated.disconnect(update)

	function update() {
		var entry = app.haStates[entityId];
		var light = app.lightOf(entityId);
		isOn = entry ? entry.state === "on" : false;
		dimmable = light ? light.dimmable : false;
		hasColor = light ? light.color : false;
		hasColorTemp = light ? light.colorTemp : false;
		if (light) {
			minKelvin = light.minKelvin;
			maxKelvin = light.maxKelvin;
		}
		// a slider being dragged keeps its own position
		if (!brightnessSlider.dragging) {
			percent = isOn ? app.lightPercent(entityId) : 0;
			brightnessSlider.value = percent / 100;
		}
		if (light && !hueSlider.dragging) hueSlider.value = light.hue / 360;
		if (light && !tempSlider.dragging && light.kelvin > 0) tempSlider.value = (light.kelvin - minKelvin) / Math.max(1, maxKelvin - minKelvin);
		currentColor.color = currentColorOf(light);
	}

	function currentColorOf(light) {
		if (!isOn || !light) return "#d0d0d0";
		if (light.colorMode === "color_temp" && light.kelvin > 0) return kelvinColor(light.kelvin);
		if (light.color) return Qt.hsla(light.hue / 360, 1, 1 - light.saturation / 200, 1);
		return "#f5a623";
	}

	// roughly the colour of white light at this temperature: warm orange to cool blue-white
	function kelvinColor(k) {
		var fraction = Math.max(0, Math.min(1, (k - 2000) / 4500));
		return Qt.rgba(1, 0.62 + 0.33 * fraction, 0.25 + 0.72 * fraction, 1);
	}

	function sliderKelvin(position) { return minKelvin + position * (maxKelvin - minKelvin); }

	// ---- name, state, on/off ----
	Image {
		id: logo
		width: isNxt ? 56 : 44
		height: width
		sourceSize.width: width
		sourceSize.height: height
		source: app.logoUrl
		anchors {
			top: parent.top
			topMargin: isNxt ? 24 : 18
			left: parent.left
			leftMargin: isNxt ? 60 : 44
		}
	}
	Rectangle {
		id: currentColor
		width: isNxt ? 40 : 32
		height: width
		radius: width / 2
		border.color: "#a0a0a0"
		anchors {
			left: logo.right
			leftMargin: isNxt ? 20 : 16
			verticalCenter: logo.verticalCenter
		}
	}
	Text {
		id: stateLabel
		anchors {
			left: currentColor.right
			leftMargin: isNxt ? 16 : 12
			verticalCenter: logo.verticalCenter
		}
		font.family: qfont.bold.name
		font.pixelSize: isNxt ? 30 : 24
		color: "#000000"
		text: isOn ? (dimmable ? "Aan, " + percent + "%" : "Aan") : "Uit"
	}

	Rectangle {
		id: onOff
		width: isNxt ? 110 : 88
		height: isNxt ? 50 : 40
		radius: height / 2
		color: isOn ? "#f5a623" : "#c8c8c8"
		anchors {
			right: parent.right
			rightMargin: isNxt ? 60 : 44
			verticalCenter: logo.verticalCenter
		}
		Rectangle {
			width: parent.height - 8
			height: width
			radius: width / 2
			y: 4
			x: isOn ? parent.width - width - 4 : 4
			color: "#ffffff"
			Behavior on x { NumberAnimation { duration: 120 } }
		}
		MouseArea {
			anchors.fill: parent
			anchors.margins: -8
			onClicked: app.activate(entityId)
		}
	}

	Column {
		id: controls
		spacing: isNxt ? 14 : 10
		anchors {
			top: logo.bottom
			topMargin: isNxt ? 26 : 18
			left: logo.left
		}

		// ---- brightness ----
		Text {
			visible: dimmable
			font.family: qfont.semiBold.name
			font.pixelSize: fontSize
			color: colors.singleLabelLeftText
			text: "Helderheid"
		}
		Row {
			visible: dimmable
			spacing: isNxt ? 16 : 12
			StandardButton {
				text: "-"
				width: isNxt ? 56 : 44
				anchors.verticalCenter: parent.verticalCenter
				onClicked: app.setBrightness(entityId, Math.max(1, percent - 10))
			}
			HaSlider {
				id: brightnessSlider
				width: sliderWidth
				anchors.verticalCenter: parent.verticalCenter
				fillToKnob: true
				stops: [{pos: 0, color: "#e8e8e8"}, {pos: 1, color: "#e8e8e8"}]
				onMoved: percent = Math.max(1, Math.round(value * 100))
				onReleased: app.setBrightness(entityId, Math.max(1, Math.round(value * 100)))
			}
			StandardButton {
				text: "+"
				width: isNxt ? 56 : 44
				anchors.verticalCenter: parent.verticalCenter
				onClicked: app.setBrightness(entityId, Math.min(100, (isOn ? percent : 0) + 10))
			}
		}

		// ---- colour ----
		Text {
			visible: hasColor
			font.family: qfont.semiBold.name
			font.pixelSize: fontSize
			color: colors.singleLabelLeftText
			text: "Kleur"
		}
		HaSlider {
			id: hueSlider
			visible: hasColor
			width: sliderWidth + 2 * (isNxt ? 72 : 56)
			knobColor: Qt.hsla(value, 1, 0.5, 1)
			stops: [{pos: 0, color: "#ff0000"}, {pos: 0.17, color: "#ffff00"}, {pos: 0.33, color: "#00ff00"}, {pos: 0.5, color: "#00ffff"},
				{pos: 0.67, color: "#0000ff"}, {pos: 0.83, color: "#ff00ff"}, {pos: 1, color: "#ff0000"}]
			onReleased: app.setColor(entityId, value * 360, 100)
		}
		Row {
			visible: hasColor
			spacing: isNxt ? 12 : 9
			Repeater {
				model: swatches
				Rectangle {
					width: isNxt ? 52 : 42
					height: width
					radius: width / 2
					color: modelData.color
					border.color: "#909090"
					border.width: 1
					MouseArea {
						anchors.fill: parent
						onClicked: app.setColor(entityId, modelData.hue, modelData.sat)
					}
				}
			}
		}

		// ---- colour temperature ----
		Text {
			visible: hasColorTemp
			font.family: qfont.semiBold.name
			font.pixelSize: fontSize
			color: colors.singleLabelLeftText
			text: "Kleurtemperatuur" + (tempSlider.dragging ? ": " + Math.round(sliderKelvin(tempSlider.value)) + " K" : "")
		}
		Row {
			visible: hasColorTemp
			spacing: isNxt ? 12 : 9
			Text {
				anchors.verticalCenter: parent.verticalCenter
				width: isNxt ? 60 : 47
				font.family: qfont.regular.name
				font.pixelSize: isNxt ? 16 : 13
				color: colors.singleLabelLeftText
				text: "Warm"
			}
			HaSlider {
				id: tempSlider
				width: sliderWidth
				anchors.verticalCenter: parent.verticalCenter
				knobColor: kelvinColor(sliderKelvin(value))
				stops: [{pos: 0, color: "#ff9e40"}, {pos: 0.5, color: "#fff1d8"}, {pos: 1, color: "#cfe3ff"}]
				onReleased: app.setColorTemp(entityId, sliderKelvin(value))
			}
			Text {
				anchors.verticalCenter: parent.verticalCenter
				font.family: qfont.regular.name
				font.pixelSize: isNxt ? 16 : 13
				color: colors.singleLabelLeftText
				text: "Koel"
			}
		}

		Text {
			visible: !dimmable
			font.family: qfont.regular.name
			font.pixelSize: fontSize
			color: colors.singleLabelLeftText
			text: "Deze lamp kan alleen aan en uit."
		}
	}
}
