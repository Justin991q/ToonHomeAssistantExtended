import QtQuick 2.1

// the Energie tab: electricity, solar panels, gas and water today. Each panel: today's total, the power
// now, and today per hour. Only the parts that have entities (Instellingen > Energie) are shown.
Item {
	id: view

	property int rev: 0
	property int gap: isNxt ? 14 : 10
	property variant panels: rev >= 0 ? panelList() : []
	property int columns: panels.length > 1 ? 2 : 1
	property int rows: Math.max(1, Math.ceil(panels.length / columns))

	function has(key) { return (app.energy[key] || []).length > 0; }

	// [{key, title, icon, color}]
	function panelList() {
		var out = [];
		if (has("power") || has("usage") || has("export")) out.push({key: "electricity", title: "Stroom", icon: "bolt-blue", color: "#2f7fd8"});
		if (has("solarPower") || has("solar")) out.push({key: "solar", title: "Zonnepanelen", icon: "energy-solar", color: "#e8a317"});
		if (has("gas")) out.push({key: "gas", title: "Gas", icon: "flame-gas", color: "#d9622b"});
		if (has("water")) out.push({key: "water", title: "Water", icon: "water-blue", color: "#2f7fd8"});
		return out;
	}

	Flow {
		anchors.fill: parent
		spacing: view.gap
		Repeater {
			model: view.panels
			Rectangle {
				id: panel
				property string key: modelData.key
				// the meter field for the total, the power field for "now"
				property string totalKey: key === "electricity" ? "usage" : key
				property string nowKey: key === "electricity" ? "power" : (key === "solar" ? "solarPower" : "")
				property variant today: view.rev >= 0 ? app.energyToday(totalKey) : null
				property variant sentBack: view.rev >= 0 && key === "electricity" ? app.energyToday("export") : null
				property variant now: view.rev >= 0 && nowKey !== "" ? app.energyNow(nowKey) : null

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
					anchors { left: icon.right; leftMargin: 8; verticalCenter: icon.verticalCenter }
					font.family: qfont.semiBold.name
					font.pixelSize: isNxt ? 18 : 15
					color: "#1d1d1b"
					text: modelData.title
				}
				// now, top right
				Text {
					visible: panel.now !== null
					anchors { right: parent.right; rightMargin: isNxt ? 12 : 8; verticalCenter: icon.verticalCenter }
					font.family: qfont.regular.name
					font.pixelSize: isNxt ? 15 : 13
					color: panel.key === "electricity" && panel.now < 0 ? "#3b7d16" : "#6b6b6b"
					text: panel.now === null ? "" : (panel.key === "electricity" && panel.now < 0
						? "Nu " + app.energyNumber(-panel.now, panel.nowKey) + " terug" : "Nu " + app.energyNumber(panel.now, panel.nowKey))
				}

				Column {
					id: totals
					anchors { left: parent.left; right: parent.right; top: icon.bottom; margins: isNxt ? 12 : 8; topMargin: isNxt ? 8 : 4 }
					spacing: 0
					Text {
						font.family: qfont.bold.name
						font.pixelSize: isNxt ? 28 : 22
						color: "#1d1d1b"
						text: panel.today !== null ? app.energyNumber(panel.today.total, panel.totalKey)
							: (panel.now !== null && !view.has(panel.totalKey) ? app.energyNumber(panel.now, panel.nowKey) : "-")
					}
					Text {
						font.family: qfont.regular.name
						font.pixelSize: isNxt ? 14 : 12
						color: "#6b6b6b"
						text: {
							var t = view.has(panel.totalKey) ? (panel.key === "solar" ? "opgewekt vandaag" : "vandaag") : "nu";
							if (panel.sentBack !== null) t += " · " + app.energyNumber(panel.sentBack.total, "export") + " teruggeleverd";
							return t;
						}
					}
				}

				HaBarChart {
					visible: panel.today !== null && height > (isNxt ? 30 : 24)
					anchors { left: parent.left; right: parent.right; top: totals.bottom; bottom: parent.bottom; margins: isNxt ? 12 : 8 }
					values: panel.today !== null ? panel.today.hours : []
					downValues: panel.sentBack !== null ? panel.sentBack.hours : []
					barColor: modelData.color
				}
			}
		}
	}
}
