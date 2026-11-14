import QtQuick 2.1

// today per hour as bars (0:00 - 23:00); optional bars below the line (e.g. electricity sent back)
Item {
	id: chart

	property variant values: []            // 24 numbers
	property variant downValues: []        // 24 numbers drawn downwards, or []
	property color barColor: "#f5a623"
	property color downColor: "#3b9b3b"
	property int labelHeight: isNxt ? 16 : 13

	property real maxUp: maxOf(values)
	property real maxDown: maxOf(downValues)
	property real plotHeight: height - labelHeight
	// where the zero line is: with bars downwards it moves up in proportion
	property real zeroY: maxDown > 0 ? plotHeight * maxUp / Math.max(0.0001, maxUp + maxDown) : plotHeight
	property int nowHour: new Date().getHours()

	function maxOf(list) {
		var m = 0;
		for (var i = 0; list && i < list.length; i++) if (list[i] > m) m = list[i];
		return m;
	}

	Rectangle {
		width: parent.width
		height: 1
		y: chart.zeroY
		color: "#d6d6d6"
	}

	Repeater {
		model: 24
		Item {
			x: index * chart.width / 24
			width: chart.width / 24
			height: chart.plotHeight
			Rectangle {
				property real v: chart.values && chart.values.length > index ? chart.values[index] : 0
				width: Math.max(2, parent.width - 2)
				anchors.horizontalCenter: parent.horizontalCenter
				height: chart.maxUp > 0 ? Math.max(v > 0 ? 2 : 0, (chart.zeroY - 1) * v / chart.maxUp) : 0
				y: chart.zeroY - height
				radius: 1
				color: chart.barColor
				opacity: index > chart.nowHour ? 0.3 : 1
			}
			Rectangle {
				property real v: chart.downValues && chart.downValues.length > index ? chart.downValues[index] : 0
				visible: v > 0
				width: Math.max(2, parent.width - 2)
				anchors.horizontalCenter: parent.horizontalCenter
				height: chart.maxDown > 0 ? Math.max(2, (chart.plotHeight - chart.zeroY - 1) * v / chart.maxDown) : 0
				y: chart.zeroY + 1
				radius: 1
				color: chart.downColor
			}
		}
	}

	Repeater {
		model: [0, 6, 12, 18]
		Text {
			x: modelData * chart.width / 24
			anchors.bottom: parent.bottom
			font.family: qfont.regular.name
			font.pixelSize: isNxt ? 12 : 10
			color: "#9a9a9a"
			text: modelData + ":00"
		}
	}
}
