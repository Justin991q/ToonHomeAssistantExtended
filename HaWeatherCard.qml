import QtQuick 2.1

// the weather as a double card: now on the left (icon, temperature, what it is), the forecast on the right
// (days, or hours when the weather entity has no daily forecast), as many as fit
Rectangle {
	id: card

	property string entityId: ""
	property int rev: 0
	property string condition: rev >= 0 && app.haStates[entityId] ? app.haStates[entityId].state : ""
	property variant forecast: rev >= 0 && app.forecasts[entityId] ? app.forecasts[entityId] : []
	property int margin: isNxt ? 12 : 8
	property int columnWidth: isNxt ? 64 : 50
	property int maxColumns: Math.max(0, Math.floor((width - nowPart.width - 3 * margin) / columnWidth))

	signal failed(string message)

	radius: isNxt ? 12 : 10
	color: "#ffffff"
	border.width: 1
	border.color: "#e2e2e2"
	opacity: condition === "unavailable" ? 0.5 : 1

	// the forecast from now on: [{label, icon, high, low}]
	function columns() {
		var out = [];
		var now = new Date().getTime();
		var days = ["zo", "ma", "di", "wo", "do", "vr", "za"];
		for (var i = 0; i < forecast.length && out.length < maxColumns; i++) {
			var f = forecast[i];
			if (f.daily) {
				var d = new Date(f.time);
				if (d.toDateString() === new Date().toDateString()) continue;   // today is on the left
				out.push({label: days[d.getDay()], icon: app.weatherIconUrl(f.condition), high: f.temp, low: f.low});
			} else {
				if (f.time < now - 30 * 60 * 1000) continue;
				var h = new Date(f.time);
				out.push({label: app.pad2(h.getHours()) + ":00", icon: app.weatherIconUrl(f.condition), high: f.temp, low: undefined});
			}
		}
		return out;
	}

	Item {
		id: nowPart
		width: Math.max(nowColumn.width, isNxt ? 170 : 130)
		anchors { left: parent.left; top: parent.top; bottom: parent.bottom; leftMargin: card.margin }

		Image {
			id: nowIcon
			width: isNxt ? 48 : 38
			height: width
			sourceSize.width: width
			sourceSize.height: height
			anchors { left: parent.left; top: parent.top; topMargin: card.margin }
			source: app.weatherIconUrl(card.condition)
		}
		Text {
			anchors { left: nowIcon.right; leftMargin: isNxt ? 10 : 6; verticalCenter: nowIcon.verticalCenter }
			font.family: qfont.bold.name
			font.pixelSize: isNxt ? 30 : 23
			color: "#1d1d1b"
			text: card.rev >= 0 ? app.degrees(app.attr(card.entityId, "temperature")) : ""
		}
		Column {
			id: nowColumn
			anchors { left: parent.left; bottom: parent.bottom; bottomMargin: card.margin }
			spacing: 1
			Text {
				font.family: qfont.semiBold.name
				font.pixelSize: isNxt ? 17 : 14
				color: "#1d1d1b"
				text: app.weatherConditionText(card.condition)
			}
			Text {
				font.family: qfont.regular.name
				font.pixelSize: isNxt ? 14 : 12
				color: "#6b6b6b"
				text: {
					if (card.rev < 0) return "";
					var parts = [];
					var hum = app.attr(card.entityId, "humidity"), wind = app.attr(card.entityId, "wind_speed");
					if (typeof hum === "number") parts.push(Math.round(hum) + "%");
					if (typeof wind === "number") parts.push(Math.round(wind) + " " + (app.attr(card.entityId, "wind_speed_unit") || "km/h"));
					return parts.length > 0 ? parts.join(" · ") : app.displayName(card.entityId);
				}
			}
		}
	}

	Rectangle {
		visible: forecastRow.children.length > 1
		width: 1
		color: "#ececec"
		anchors { top: parent.top; bottom: parent.bottom; margins: card.margin; left: nowPart.right; leftMargin: card.margin / 2 }
	}

	Row {
		id: forecastRow
		anchors { right: parent.right; rightMargin: card.margin; verticalCenter: parent.verticalCenter }
		Repeater {
			model: card.rev >= 0 ? card.columns() : []
			Column {
				width: card.columnWidth
				spacing: isNxt ? 4 : 2
				Text {
					anchors.horizontalCenter: parent.horizontalCenter
					font.family: qfont.regular.name
					font.pixelSize: isNxt ? 14 : 12
					color: "#6b6b6b"
					text: modelData.label
				}
				Image {
					anchors.horizontalCenter: parent.horizontalCenter
					width: isNxt ? 32 : 26
					height: width
					sourceSize.width: width
					sourceSize.height: height
					source: modelData.icon
				}
				Text {
					anchors.horizontalCenter: parent.horizontalCenter
					font.family: qfont.semiBold.name
					font.pixelSize: isNxt ? 16 : 13
					color: "#1d1d1b"
					text: typeof modelData.high === "number" ? Math.round(modelData.high) + "°" : ""
				}
				Text {
					visible: typeof modelData.low === "number"
					anchors.horizontalCenter: parent.horizontalCenter
					font.family: qfont.regular.name
					font.pixelSize: isNxt ? 13 : 11
					color: "#8a8a8a"
					text: typeof modelData.low === "number" ? Math.round(modelData.low) + "°" : ""
				}
			}
		}
	}
}
