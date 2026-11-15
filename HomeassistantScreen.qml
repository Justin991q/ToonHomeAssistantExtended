import QtQuick 2.1
import qb.components 1.0

// the main screen: Home Assistant's areas as tabs on the left (Favorieten first), the entities of
// the chosen tab as cards on the right, 6 per page (swipe up/down or the arrows)
Screen {
	id: homeassistantScreen

	screenTitle: app.appName
	screenTitleIconUrl: app.titleIconUrl

	property int rev: 0                       // raised on every state update: the cards re-read
	property variant tabs: []
	property string tabKey: ""
	property variant pages: []                // [[id, ...], ...] 6 per page
	property int columns: 3
	property int rows: 3
	property int gap: isNxt ? 14 : 10
	property real cellWidth: (pagesView.width - (columns - 1) * gap) / columns
	property real cellHeight: (pagesView.height - (rows - 1) * gap) / rows

	onShown: {
		addCustomTopRightButton("Instellingen");
		app.statesUpdated.connect(onStates);
		app.selectionChanged.connect(rebuild);
		rebuild();
		app.pollStates();
	}
	onHidden: {
		app.statesUpdated.disconnect(onStates);
		app.selectionChanged.disconnect(rebuild);
	}
	onCustomButtonClicked: stage.openFullscreen(app.setupScreenUrl)

	function onStates() {
		rev++;
		// the area of an entity may have come in only now
		var keys = tabKeys(app.tabList());
		if (keys !== tabKeys(tabs)) rebuild();
		else updateCounts();
	}

	function tabKeys(list) {
		var keys = [];
		for (var index = 0; index < list.length; index++) keys.push(list[index].key);
		return keys.join("|");
	}

	function rebuild() {
		tabs = app.tabList();
		var keep = false;
		for (var index = 0; index < tabs.length; index++) if (tabs[index].key === app.currentTab) keep = true;
		selectTab(keep ? app.currentTab : (tabs.length > 0 ? tabs[0].key : ""), true);
		tabModel.clear();
		for (var tabIndex = 0; tabIndex < tabs.length; tabIndex++) tabModel.append({key: tabs[tabIndex].key, label: tabs[tabIndex].label, count: app.tabOnCount(tabs[tabIndex].key)});
	}

	function updateCounts() {
		for (var index = 0; index < tabModel.count; index++) tabModel.setProperty(index, "count", app.tabOnCount(tabModel.get(index).key));
	}

	function selectTab(key, keepPage) {
		var keepIndex = keepPage && key === tabKey ? pagesView.currentIndex : 0;
		tabKey = key;
		app.currentTab = key;
		var ids = tabs.length > 0 ? app.tabEntities(key) : [];
		// fill pages row by row as the Flow will: a double card that does not fit on a row starts the next one
		var list = [], page = [], row = 0, col = 0;
		for (var index = 0; index < ids.length; index++) {
			var slots = Math.min(columns, app.cardSlots(ids[index]));
			if (col + slots > columns) { row++; col = 0; }
			if (row >= rows) { list.push(page); page = []; row = 0; col = 0; }
			page.push(ids[index]);
			col += slots;
		}
		if (page.length > 0) list.push(page);
		pages = list;
		for (var tabIndex = 0; tabIndex < tabs.length; tabIndex++) if (tabs[tabIndex].key === key) screenTitle = tabs[tabIndex].label;
		if (tabs.length === 0) screenTitle = app.appName;
		pagesView.positionViewAtIndex(Math.min(keepIndex, Math.max(0, list.length - 1)), ListView.Beginning);
		pagesView.currentIndex = Math.min(keepIndex, Math.max(0, list.length - 1));
	}

	function nextPage() { pagesView.incrementCurrentIndex(); }
	function previousPage() { pagesView.decrementCurrentIndex(); }

	function showToast(message) {
		toastText.text = message;
		toast.opacity = 1;
		toastTimer.restart();
	}

	ListModel { id: tabModel }

	// ---- the areas ----
	Item {
		id: tabColumn
		width: isNxt ? 210 : 165
		visible: tabs.length > 0
		anchors {
			top: parent.top
			bottom: parent.bottom
			left: parent.left
			leftMargin: isNxt ? 20 : 14
			topMargin: isNxt ? 16 : 10
			bottomMargin: isNxt ? 16 : 10
		}

		ListView {
			id: tabList
			anchors {
				top: parent.top
				left: parent.left
				right: parent.right
				bottom: statusColumn.top
				bottomMargin: 8
			}
			clip: true
			spacing: 4
			boundsBehavior: Flickable.StopAtBounds
			model: tabModel
			delegate: Rectangle {
				property bool selected: model.key === homeassistantScreen.tabKey
				width: tabList.width
				height: isNxt ? 54 : 44
				radius: 8
				color: selected ? "#fde7c2" : (tabMouse.pressed ? "#ececec" : "transparent")

				Image {
					id: starIcon
					visible: model.key === "*fav" || model.key === "*energy"
					width: isNxt ? 22 : 18
					height: width
					sourceSize.width: width
					sourceSize.height: height
					source: model.key === "*energy" ? Qt.resolvedUrl("drawables/icons/energy-on.svg") : "qrc:/images/star-on.svg"
					anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
				}
				Text {
					anchors {
						left: starIcon.visible ? starIcon.right : parent.left
						leftMargin: starIcon.visible ? 8 : 12
						right: countBadge.visible ? countBadge.left : parent.right
						rightMargin: 8
						verticalCenter: parent.verticalCenter
					}
					elide: Text.ElideRight
					font.family: selected ? qfont.bold.name : qfont.regular.name
					font.pixelSize: isNxt ? 19 : 15
					color: selected ? "#7a4500" : "#3c3c3a"
					text: model.label
				}
				// how many lights/switches are on here
				Rectangle {
					id: countBadge
					visible: model.count > 0
					height: isNxt ? 26 : 22
					width: Math.max(height, countText.implicitWidth + 12)
					radius: height / 2
					color: "#f5a623"
					anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
					Text {
						id: countText
						anchors.centerIn: parent
						font.family: qfont.bold.name
						font.pixelSize: isNxt ? 15 : 12
						color: "#ffffff"
						text: model.count
					}
				}
				MouseArea {
					id: tabMouse
					anchors.fill: parent
					onClicked: homeassistantScreen.selectTab(model.key, false)
				}
			}
		}

		// connection: a dot, words only when something is wrong; under it when data last came in
		Column {
			id: statusColumn
			spacing: 2
			anchors { left: parent.left; leftMargin: 12; right: parent.right; bottom: parent.bottom }
			Row {
				id: statusRow
				spacing: 8
				width: parent.width
				Rectangle {
					width: 10
					height: 10
					radius: 5
					anchors.verticalCenter: parent.verticalCenter
					color: app.connected ? "#4caf50" : "#d0021b"
				}
				Text {
					width: statusRow.width - 18
					elide: Text.ElideRight
					font.family: qfont.regular.name
					font.pixelSize: isNxt ? 14 : 12
					color: app.connected ? "#8a8a8a" : "#d0021b"
					text: app.connected ? (app.liveConnected ? "Verbonden · live" : "Verbonden") : app.friendlyError(app.lastError || "geen verbinding")
				}
			}
			Text {
				visible: text !== ""
				x: 18                                       // under the words, past the dot
				width: statusColumn.width - 18
				elide: Text.ElideRight
				font.family: qfont.regular.name
				font.pixelSize: isNxt ? 13 : 11
				color: "#a0a0a0"
				text: app.lastDataText()
			}
		}
	}

	Rectangle {
		width: 1
		color: "#d6d6d6"
		visible: tabColumn.visible
		anchors { top: tabColumn.top; bottom: tabColumn.bottom; left: tabColumn.right; leftMargin: isNxt ? 14 : 10 }
	}

	// ---- the cards, a page at a time ----
	ListView {
		id: pagesView
		anchors {
			top: parent.top
			bottom: parent.bottom
			left: tabColumn.visible ? tabColumn.right : parent.left
			right: pager.left
			leftMargin: isNxt ? 28 : 20
			rightMargin: isNxt ? 14 : 10
			topMargin: isNxt ? 16 : 10
			bottomMargin: isNxt ? 16 : 10
		}
		clip: true
		visible: tabKey !== "*energy"
		model: pages.length
		orientation: ListView.Vertical
		snapMode: ListView.SnapOneItem
		highlightRangeMode: ListView.StrictlyEnforceRange
		preferredHighlightBegin: 0
		preferredHighlightEnd: height
		highlightMoveDuration: 250
		boundsBehavior: Flickable.StopAtBounds

		delegate: Item {
			width: pagesView.width
			height: pagesView.height
			property variant ids: homeassistantScreen.pages[index] || []

			Flow {
				width: pagesView.width
				spacing: homeassistantScreen.gap
				Repeater {
					model: ids
					// an ordinary card, or a double one (alarm, speaker, camera, weather)
					Loader {
						id: cardLoader
						property int slots: Math.min(homeassistantScreen.columns, app.cardSlots(modelData))
						width: slots * homeassistantScreen.cellWidth + (slots - 1) * homeassistantScreen.gap
						height: homeassistantScreen.cellHeight
						source: app.cardFile(modelData)
						onLoaded: item.entityId = modelData
						Binding { target: cardLoader.item; property: "rev"; value: homeassistantScreen.rev; when: cardLoader.status === Loader.Ready }
						Connections {
							target: cardLoader.item
							ignoreUnknownSignals: true
							onFailed: homeassistantScreen.showToast(message)
						}
					}
				}
			}
		}
	}

	// ---- the Energie tab ----
	HaEnergyView {
		anchors.fill: pagesView
		visible: tabKey === "*energy"
		rev: homeassistantScreen.rev
	}

	// ---- pages: arrows and dots (only with more than one page) ----
	Column {
		id: pager
		width: isNxt ? 56 : 44
		spacing: isNxt ? 12 : 8
		anchors {
			right: parent.right
			rightMargin: isNxt ? 16 : 10
			verticalCenter: pagesView.verticalCenter
		}
		opacity: pages.length > 1 && tabKey !== "*energy" ? 1 : 0

		IconButton {
			width: parent.width
			height: width
			iconSource: "qrc:/images/arrow-up.svg"
			enabled: pagesView.currentIndex > 0
			onClicked: previousPage()
		}
		Column {
			anchors.horizontalCenter: parent.horizontalCenter
			spacing: 8
			Repeater {
				model: pages.length
				Rectangle {
					width: 10
					height: 10
					radius: 5
					anchors.horizontalCenter: parent.horizontalCenter
					color: index === pagesView.currentIndex ? "#f5a623" : "#c4c4c4"
				}
			}
		}
		IconButton {
			width: parent.width
			height: width
			iconSource: "qrc:/images/arrow-down.svg"
			enabled: pagesView.currentIndex < pages.length - 1
			onClicked: nextPage()
		}
	}

	// ---- nothing to show yet: one clear next step ----
	Column {
		anchors.centerIn: parent
		width: parent.width * 0.6
		spacing: isNxt ? 18 : 14
		visible: tabs.length === 0

		Image {
			anchors.horizontalCenter: parent.horizontalCenter
			width: isNxt ? 80 : 64
			height: width
			sourceSize.width: width
			sourceSize.height: height
			source: app.logoUrl
		}
		Text {
			width: parent.width
			horizontalAlignment: Text.AlignHCenter
			font.family: qfont.bold.name
			font.pixelSize: isNxt ? 26 : 21
			color: "#1d1d1b"
			text: app.isConfigured() ? "Kies je eerste lampen" : "Verbind met Home Assistant"
		}
		Text {
			width: parent.width
			horizontalAlignment: Text.AlignHCenter
			wrapMode: Text.WordWrap
			font.family: qfont.regular.name
			font.pixelSize: isNxt ? 17 : 14
			color: "#6b6b6b"
			text: app.isConfigured() ? "Op de Toon, of makkelijker op je telefoon of computer: " + app.webEditorUrl()
				: "Je hebt het adres van Home Assistant en een toegangstoken nodig."
		}
		StandardButton {
			anchors.horizontalCenter: parent.horizontalCenter
			primary: true
			text: app.isConfigured() ? "Entiteiten kiezen" : "Instellen"
			onClicked: stage.openFullscreen(app.isConfigured() ? app.entitiesScreenUrl : app.setupScreenUrl)
		}
	}

	// ---- a short notice when a command failed ----
	Rectangle {
		id: toast
		opacity: 0
		visible: opacity > 0
		Behavior on opacity { NumberAnimation { duration: 200 } }
		height: isNxt ? 48 : 40
		width: toastText.implicitWidth + 40
		radius: height / 2
		color: "#323232"
		anchors { horizontalCenter: pagesView.horizontalCenter; bottom: parent.bottom; bottomMargin: isNxt ? 24 : 16 }
		Text {
			id: toastText
			anchors.centerIn: parent
			font.family: qfont.semiBold.name
			font.pixelSize: isNxt ? 17 : 14
			color: "#ffffff"
		}
		Timer {
			id: toastTimer
			interval: 3500
			onTriggered: toast.opacity = 0
		}
	}
}
