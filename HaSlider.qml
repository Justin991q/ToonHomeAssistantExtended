import QtQuick 2.1

// a horizontal slider for touch: tap or drag anywhere on the bar. value 0..1.
// moved(value) while dragging (for the display), released(value) once at the end (for Home Assistant).
Item {
	id: slider

	property real value: 0
	property variant stops: [{pos: 0, color: "#d0d0d0"}, {pos: 1, color: "#d0d0d0"}]   // the bar's colours, left to right
	property color knobColor: "#ffffff"
	property bool fillToKnob: false        // brightness: the part left of the knob in fillColor
	property color fillColor: "#f5a623"
	property bool dragging: mouse.pressed

	signal moved(real value)
	signal released(real value)

	height: isNxt ? 44 : 36

	function valueAt(x) {
		return Math.max(0, Math.min(1, (x - knob.width / 2) / (width - knob.width)));
	}

	Item {
		id: track
		anchors.verticalCenter: parent.verticalCenter
		width: parent.width
		height: Math.round(parent.height * 0.5)

		// Rectangle gradients run top to bottom: turned a quarter, left to right
		Rectangle {
			width: parent.height
			height: parent.width
			anchors.centerIn: parent
			rotation: -90
			radius: width / 2
			border.color: "#b0b0b0"
			border.width: 1
			gradient: Gradient {
				id: grad
			}
		}
		Rectangle {
			visible: fillToKnob
			height: parent.height
			width: knob.x + knob.width / 2
			radius: height / 2
			color: fillColor
		}
	}

	Rectangle {
		id: knob
		width: slider.height
		height: width
		radius: width / 2
		color: knobColor
		border.color: "#606060"
		border.width: 2
		anchors.verticalCenter: parent.verticalCenter
		x: slider.value * (slider.width - width)
	}

	MouseArea {
		id: mouse
		anchors.fill: parent
		anchors.topMargin: -8
		anchors.bottomMargin: -8
		preventStealing: true
		onPressed: { slider.value = valueAt(mouse.x); slider.moved(slider.value); }
		onPositionChanged: { slider.value = valueAt(mouse.x); slider.moved(slider.value); }
		onReleased: slider.released(slider.value)
	}

	Component {
		id: stopComponent
		GradientStop {}
	}

	onStopsChanged: buildGradient()
	Component.onCompleted: buildGradient()

	function buildGradient() {
		var list = [];
		for (var index = 0; index < stops.length; index++) list.push(stopComponent.createObject(grad, {position: stops[index].pos, color: stops[index].color}));
		grad.stops = list;
	}
}
