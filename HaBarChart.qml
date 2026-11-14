import QtQuick 2.1

// today per hour as bars (0:00 - 23:00); optional bars below the line (e.g. electricity sent back, a negative
// price), yesterday as light bars behind, and one hour highlighted (now)
Item {
	id: chart

	property variant values: []            // 24 numbers
	property variant downValues: []        // 24 numbers drawn downwards, or []
	property variant ghostValues: []       // 24 numbers drawn light behind (yesterday), or []
	property color barColor: "#f5a623"
	property color downColor: "#3b9b3b"
	property color ghostColor: "#e4e4e4"
	property color highlightColor: "#1d1d1b"
	property bool dimFuture: true          // the hours still to come lighter (a meter); a price: all the same
	property int highlight: -1             // this hour in highlightColor
	property int labelHeight: isNxt ? 16 : 13

	property real maxUp: Math.max(maxOf(values), maxOf(ghostValues))
	property real maxDown: maxOf(downValues)
	property real plotHeight: height - labelHeight
	// where the zero line is: with bars downwards it moves up in proportion
	property real zeroY: maxDown > 0 ? plotHeight * maxUp / Math.max(0.0001, maxUp + maxDown) : plotHeight
	property int nowHour: new Date().getHours()

	function maxOf(list) {
		var highest = 0;
		for (var i = 0; list && i < list.length; i++) if (list[i] > highest) highest = list[i];
		return highest;
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
			// yesterday, behind
			Rectangle {
				property real amount: chart.ghostValues && chart.ghostValues.length > index ? chart.ghostValues[index] : 0
				visible: amount > 0
				width: Math.max(2, parent.width - 2)
				anchors.horizontalCenter: parent.horizontalCenter
				height: chart.maxUp > 0 ? Math.max(2, (chart.zeroY - 1) * amount / chart.maxUp) : 0
				y: chart.zeroY - height
				radius: 1
				color: chart.ghostColor
			}
			Rectangle {
				property real amount: chart.values && chart.values.length > index ? chart.values[index] : 0
				width: Math.max(2, parent.width - 2) * (chart.ghostValues && chart.ghostValues.length ? 0.6 : 1)
				anchors.horizontalCenter: parent.horizontalCenter
				height: chart.maxUp > 0 ? Math.max(amount > 0 ? 2 : 0, (chart.zeroY - 1) * amount / chart.maxUp) : 0
				y: chart.zeroY - height
				radius: 1
				color: index === chart.highlight ? chart.highlightColor : chart.barColor
				opacity: chart.dimFuture && index > chart.nowHour ? 0.3 : 1
			}
			Rectangle {
				property real amount: chart.downValues && chart.downValues.length > index ? chart.downValues[index] : 0
				visible: amount > 0
				width: Math.max(2, parent.width - 2) * (chart.ghostValues && chart.ghostValues.length ? 0.6 : 1)
				anchors.horizontalCenter: parent.horizontalCenter
				height: chart.maxDown > 0 ? Math.max(2, (chart.plotHeight - chart.zeroY - 1) * amount / chart.maxDown) : 0
				y: chart.zeroY + 1
				radius: 1
				color: index === chart.highlight ? chart.highlightColor : chart.downColor
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
