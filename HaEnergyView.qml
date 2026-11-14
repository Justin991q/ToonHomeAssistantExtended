import QtQuick 2.1

// the Energie tab: electricity, solar panels, gas, water and the electricity price. Each panel: today's total
// (and its costs when there is a price), yesterday up to this time, the power now, and today per hour with
// yesterday as light bars behind. Only the parts that have entities (Instellingen > Energie) are shown.
Item {
	id: view

	property int rev: 0
	property int gap: isNxt ? 14 : 10
	property variant panels: []
	property string panelsKey: ""
	property int columns: panels.length > 4 ? 3 : (panels.length > 1 ? 2 : 1)
	property int rows: Math.max(1, Math.ceil(panels.length / columns))
	property bool compact: columns > 2 || !isNxt          // narrow panels: smaller text, fewer words

	// the panels are only rebuilt when the set changes (not with every update)
	onRevChanged: {
		var list = panelList();
		var key = JSON.stringify(list);
		if (key !== panelsKey) { panelsKey = key; panels = list; }
	}
	Component.onCompleted: revChanged()

	function has(key) { return (app.energy[key] || []).length > 0; }

	// [{key, title, icon, color}]
	function panelList() {
		var out = [];
		if (has("power") || has("usage") || has("export")) out.push({key: "electricity", title: "Stroom", icon: "bolt-blue", color: "#2f7fd8"});
		if (has("solarPower") || has("solar")) out.push({key: "solar", title: "Zonnepanelen", icon: "energy-solar", color: "#e8a317"});
		if (has("gas")) out.push({key: "gas", title: "Gas", icon: "flame-gas", color: "#d9622b"});
		if (has("water")) out.push({key: "water", title: "Water", icon: "water-blue", color: "#2f7fd8"});
		if (has("priceUsage")) out.push({key: "price", title: "Stroomprijs", icon: "bolt", color: "#8e6ad8"});
		return out;
	}

	// the cheapest and dearest hour still to come today: "goedkoopst 03:00 € 0,12"
	function priceSummary(prices) {
		if (!prices) return "";
		var now = new Date().getHours(), cheapest = -1, dearest = -1;
		for (var hour = now; hour < 24; hour++) {
			if (cheapest < 0 || prices[hour] < prices[cheapest]) cheapest = hour;
			if (dearest < 0 || prices[hour] > prices[dearest]) dearest = hour;
		}
		if (cheapest < 0 || prices[cheapest] === prices[dearest]) return "";
		return "goedkoopst " + app.pad2(cheapest) + ":00 " + app.euro(prices[cheapest]) + (view.compact ? "" : " · duurst " + app.pad2(dearest) + ":00 " + app.euro(prices[dearest]));
	}

	function positive(list) {
		var out = [];
		for (var i = 0; list && i < list.length; i++) out.push(list[i] > 0 ? list[i] : 0);
		return out;
	}
	function negative(list) {
		var out = [], any = false;
		for (var i = 0; list && i < list.length; i++) { out.push(list[i] < 0 ? -list[i] : 0); if (list[i] < 0) any = true; }
		return any ? out : [];
	}

	Flow {
		anchors.fill: parent
		spacing: view.gap
		Repeater {
			model: view.panels
			Rectangle {
				id: panel
				property string key: modelData.key
				property bool isPrice: key === "price"
				// the meter field for the total, the power field for "now"
				property string totalKey: key === "electricity" ? "usage" : key
				property string nowKey: key === "electricity" ? "power" : (key === "solar" ? "solarPower" : "")
				property variant today: view.rev >= 0 && !isPrice ? app.energyToday(totalKey) : null
				property variant yesterday: view.rev >= 0 && !isPrice ? app.energyYesterday(totalKey) : null
				property variant sentBack: view.rev >= 0 && key === "electricity" ? app.energyToday("export") : null
				property variant now: view.rev >= 0 && nowKey !== "" ? app.energyNow(nowKey) : null
				property variant cost: view.rev >= 0 && (key === "electricity" || key === "gas" || key === "water") ? app.energyCost(key) : null
				property variant prices: view.rev >= 0 && isPrice ? app.priceToday("priceUsage") : null

				width: (view.width - (view.columns - 1) * view.gap) / view.columns
				height: (view.height - (view.rows - 1) * view.gap) / view.rows
				radius: isNxt ? 12 : 10
				color: "#ffffff"
				border.color: "#e2e2e2"

				Image {
					id: icon
					width: isNxt ? 28 : 22
					height: width
					sourceSize.width: width
					sourceSize.height: height
					anchors { left: parent.left; top: parent.top; margins: isNxt ? 12 : 8 }
					source: Qt.resolvedUrl("drawables/icons/" + modelData.icon + ".svg")
				}
				Text {
					anchors { left: icon.right; leftMargin: 8; verticalCenter: icon.verticalCenter; right: nowText.left; rightMargin: 6 }
					elide: Text.ElideRight
					font.family: qfont.semiBold.name
					font.pixelSize: isNxt ? 18 : 15
					color: "#1d1d1b"
					text: modelData.title
				}
				// now, top right
				Text {
					id: nowText
					visible: text !== ""
					anchors { right: parent.right; rightMargin: isNxt ? 12 : 8; verticalCenter: icon.verticalCenter }
					font.family: qfont.regular.name
					font.pixelSize: isNxt ? 15 : 13
					color: panel.key === "electricity" && panel.now < 0 ? "#3b7d16" : "#6b6b6b"
					text: {
						var prefix = view.compact ? "" : "Nu ";              // narrow: just the number, so the title fits
						if (panel.isPrice) return view.compact ? "/kWh" : "per kWh";
						if (panel.now === null) return "";
						if (panel.key === "electricity" && panel.now < 0) return prefix + app.energyNumber(-panel.now, panel.nowKey) + " terug";
						return prefix + app.energyNumber(panel.now, panel.nowKey);
					}
				}

				Column {
					id: totals
					anchors { left: parent.left; right: parent.right; top: icon.bottom; margins: isNxt ? 12 : 8; topMargin: isNxt ? 8 : 4 }
					spacing: 0
					Row {
						spacing: isNxt ? 10 : 6
						Text {
							id: bigText
							font.family: qfont.bold.name
							font.pixelSize: view.compact ? (isNxt ? 24 : 19) : (isNxt ? 28 : 22)
							color: "#1d1d1b"
							text: {
								if (panel.isPrice) return app.euro(app.priceNow("priceUsage"), 3).replace(/0$/, "");
								if (panel.today !== null) return app.energyNumber(panel.today.total, panel.totalKey);
								return panel.now !== null && !view.has(panel.totalKey) ? app.energyNumber(panel.now, panel.nowKey) : "-";
							}
						}
						// today's costs, next to the total
						Text {
							visible: panel.cost !== null
							anchors.baseline: bigText.baseline
							font.family: qfont.semiBold.name
							font.pixelSize: isNxt ? 17 : 14
							color: panel.cost !== null && panel.cost < 0 ? "#3b7d16" : "#6b6b6b"
							text: panel.cost !== null ? app.euro(panel.cost) : ""
						}
					}
					Text {
						width: parent.width
						elide: Text.ElideRight
						font.family: qfont.regular.name
						font.pixelSize: isNxt ? 14 : 12
						color: "#6b6b6b"
						text: {
							if (panel.isPrice) return view.priceSummary(panel.prices) || "nu";
							var line = view.has(panel.totalKey) ? (panel.key === "solar" ? "opgewekt vandaag" : "vandaag") : "nu";
							if (panel.sentBack !== null) line += " · " + app.energyNumber(panel.sentBack.total, "export") + (view.compact ? " terug" : " teruggeleverd");
							return line;
						}
					}
					// yesterday up to this time of day
					Text {
						visible: panel.yesterday !== null
						width: parent.width
						elide: Text.ElideRight
						font.family: qfont.regular.name
						font.pixelSize: isNxt ? 14 : 12
						color: "#9a9a9a"
						text: panel.yesterday !== null ? "gisteren tot nu " + app.energyNumber(panel.yesterday.sameTime, panel.totalKey)
							+ (view.compact ? "" : " (hele dag " + app.energyNumber(panel.yesterday.total, panel.totalKey) + ")") : ""
					}
				}

				HaBarChart {
					visible: (panel.today !== null || panel.prices !== null) && height > (isNxt ? 30 : 24)
					anchors { left: parent.left; right: parent.right; top: totals.bottom; bottom: parent.bottom; margins: isNxt ? 12 : 8 }
					values: panel.isPrice ? view.positive(panel.prices) : (panel.today !== null ? panel.today.hours : [])
					downValues: panel.isPrice ? view.negative(panel.prices) : (panel.sentBack !== null ? panel.sentBack.hours : [])
					ghostValues: panel.yesterday !== null ? panel.yesterday.hours : []
					barColor: modelData.color
					dimFuture: !panel.isPrice
					highlight: panel.isPrice ? new Date().getHours() : -1
				}
			}
		}
	}
}
