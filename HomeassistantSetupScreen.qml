import QtQuick 2.1
import qb.components 1.0
import BasicUIControls 1.0

// the Home Assistant address and token, a connection test, and the way to the entity chooser and web editor
Screen {
	id: homeassistantSetupScreen

	screenTitle: app.appName + " instellingen"
	isSaveCancelDialog: true

	property bool firstShown: true     // closing the keyboard shows the screen again: keep what was typed
	property string tempUrl: ""
	property string tempToken: ""      // "" = keep the saved one
	property string testResult: ""
	property bool testOk: false
	property bool tempSystray: false

	onShown: {
		if (firstShown) {
			tempUrl = app.haUrl;
			tempToken = "";
			testResult = "";
			tempSystray = app.enableSystray;
			systrayToggle.isSwitchedOn = tempSystray;
			firstShown = false;
		}
	}

	onSaved: {
		app.setSystray(tempSystray);
		app.setConnection(tempUrl, tempToken);
		firstShown = true;
	}
	onCanceled: firstShown = true

	function tokenText() {
		if (tempToken !== "") return "nieuw: " + tempToken.substring(0, 6) + "…" + " (" + tempToken.length + " tekens)";
		return app.haToken !== "" ? "ingesteld (" + app.haToken.length + " tekens)" : "nog niet ingesteld";
	}

	function test() {
		testResult = "Testen…";
		testOk = false;
		app.testConnection(tempUrl, tempToken, function(ok, msg) {
			testOk = ok;
			testResult = ok ? "Verbonden: " + msg : msg;
		});
	}

	Text {
		id: introText
		width: parent.width - (isNxt ? 120 : 96)
		wrapMode: Text.WordWrap
		anchors {
			top: parent.top
			topMargin: isNxt ? 24 : 18
			horizontalCenter: parent.horizontalCenter
		}
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 17 : 14
		color: colors.singleLabelLeftText
		text: "Het adres van Home Assistant (bijv. 192.168.1.10:8123) en een long-lived access token: in Home Assistant onder je profiel > Beveiliging > Langdurige toegangstokens. Het token typ je makkelijker in de webeditor."
	}

	SingleLabel {
		id: urlLabel
		width: introText.width - (isNxt ? 60 : 50)
		leftText: "Adres"
		rightText: tempUrl
		anchors {
			top: introText.bottom
			topMargin: isNxt ? 18 : 14
			left: introText.left
		}
	}
	IconButton {
		width: isNxt ? 45 : 36
		height: urlLabel.height
		iconSource: "qrc:/images/edit.svg"
		anchors {
			top: urlLabel.top
			left: urlLabel.right
			leftMargin: 10
		}
		onClicked: qkeyboard.open("Adres van Home Assistant", tempUrl, function(text) { tempUrl = app.cleanUrl(text); })
	}

	SingleLabel {
		id: tokenLabel
		width: urlLabel.width
		leftText: "Token"
		rightText: tokenText()
		anchors {
			top: urlLabel.bottom
			topMargin: isNxt ? 10 : 8
			left: introText.left
		}
	}
	IconButton {
		width: isNxt ? 45 : 36
		height: tokenLabel.height
		iconSource: "qrc:/images/edit.svg"
		anchors {
			top: tokenLabel.top
			left: tokenLabel.right
			leftMargin: 10
		}
		onClicked: qkeyboard.open("Long-lived access token", tempToken, function(text) { tempToken = text.trim(); })
	}

	StandardButton {
		id: testButton
		text: "Test verbinding"
		anchors {
			top: tokenLabel.bottom
			topMargin: isNxt ? 16 : 12
			left: introText.left
		}
		onClicked: test()
	}

	// what the tile shows
	StandardButton {
		id: tileButton
		text: app.tileEntities.length > 0 ? "Tegel (" + app.tileEntities.length + ")" : "Tegel"
		enabled: app.isConfigured() && app.entities.length > 0
		anchors {
			verticalCenter: testButton.verticalCenter
			left: defaultTabButton.right
			leftMargin: 16
		}
		onClicked: stage.openFullscreen(app.tileSetupScreenUrl)
	}

	// the tab the main screen opens on: each tap the next choice
	StandardButton {
		id: defaultTabButton
		property int rev: 0
		text: "Openen op: " + (rev >= 0 ? app.defaultTabLabel() : "")
		enabled: app.isConfigured()
		anchors {
			verticalCenter: testButton.verticalCenter
			left: testButton.right
			leftMargin: 16
		}
		onClicked: {
			var list = app.defaultTabChoices();
			var position = 0;
			for (var i = 0; i < list.length; i++) if (list[i].key === app.defaultTab) position = i;
			app.setDefaultTab(list[(position + 1) % list.length].key);
			rev++;
		}
	}
	// the result of "Test verbinding": on a line of its own under the buttons (the row is full)
	Text {
		id: testResultText
		visible: testResult !== ""
		anchors {
			top: testButton.bottom
			topMargin: isNxt ? 10 : 8
			left: introText.left
			right: introText.right
		}
		elide: Text.ElideRight
		font.family: qfont.semiBold.name
		font.pixelSize: isNxt ? 17 : 14
		color: testOk ? "#417505" : (testResult === "Testen…" ? colors.singleLabelLeftText : "#d0021b")
		text: testResult
	}

	OnOffToggle {
		id: systrayToggle
		anchors {
			verticalCenter: testButton.verticalCenter
			right: introText.right
		}
		leftIsSwitchedOn: false
		onSelectedChangedByUser: tempSystray = isSwitchedOn
	}
	Text {
		id: systrayText
		anchors {
			verticalCenter: testButton.verticalCenter
			right: systrayToggle.left
			rightMargin: 12
		}
		font.family: qfont.semiBold.name
		font.pixelSize: isNxt ? 17 : 14
		color: colors.singleLabelLeftText
		text: "Icoon in systray"
	}

	Rectangle {
		id: line
		height: 1
		color: "#d0d0d0"
		anchors {
			top: testResultText.visible ? testResultText.bottom : testButton.bottom
			topMargin: isNxt ? 22 : 16
			left: introText.left
			right: introText.right
		}
	}

	StandardButton {
		id: chooseButton
		text: "Entiteiten kiezen (" + app.entities.length + " gekozen)"
		primary: true
		enabled: app.isConfigured()
		anchors {
			top: line.bottom
			topMargin: isNxt ? 22 : 16
			left: introText.left
		}
		onClicked: stage.openFullscreen(app.entitiesScreenUrl)
	}
	// the Energie tab has entities of its own
	StandardButton {
		id: energyButton
		text: app.energyConfigured() ? "Energie (" + app.energyIds().length + ")" : "Energie instellen"
		enabled: app.isConfigured()
		anchors {
			verticalCenter: chooseButton.verticalCenter
			left: chooseButton.right
			leftMargin: 16
		}
		onClicked: stage.openFullscreen(app.energySetupScreenUrl)
	}
	// the cached list of all entities: forget it and fetch it again (after changes in Home Assistant)
	StandardButton {
		id: clearCacheButton
		property bool cleared: false
		text: "Cache wissen"
		enabled: app.isConfigured() && !app.loadingAll
		anchors {
			verticalCenter: chooseButton.verticalCenter
			left: energyButton.right
			leftMargin: 16
		}
		onClicked: { cleared = true; app.clearEntitiesCache(); }
	}
	Text {
		visible: clearCacheButton.cleared && app.isConfigured()
		anchors {
			verticalCenter: chooseButton.verticalCenter
			left: clearCacheButton.right
			leftMargin: 12
			right: introText.right
		}
		wrapMode: Text.WordWrap
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 15 : 12
		color: colors.singleLabelLeftText
		text: app.loadingAll ? "Entiteiten ophalen…" : (app.allEntities.length > 0 ? app.allEntities.length + " entiteiten opgehaald" : app.friendlyError(app.lastError || "geen verbinding"))
	}
	Text {
		visible: !app.isConfigured()
		anchors {
			verticalCenter: chooseButton.verticalCenter
			left: clearCacheButton.right
			leftMargin: 16
			right: introText.right
		}
		wrapMode: Text.WordWrap
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 15 : 12
		color: colors.singleLabelLeftText
		text: "Sla eerst adres en token op."
	}

	Text {
		id: webTitle
		anchors {
			top: chooseButton.bottom
			topMargin: isNxt ? 24 : 18
			left: introText.left
		}
		font.family: qfont.semiBold.name
		font.pixelSize: isNxt ? 18 : 15
		color: colors.singleLabelLeftText
		text: "Webeditor: makkelijker bij veel entiteiten. Scan de code met je telefoon of typ het adres:"
		width: introText.width - qrFrame.width - 24
		wrapMode: Text.WordWrap
	}
	Text {
		id: webUrl
		anchors {
			top: webTitle.bottom
			topMargin: 6
			left: introText.left
		}
		font.family: qfont.bold.name
		width: webTitle.width
		elide: Text.ElideRight
		font.pixelSize: isNxt ? 22 : 18
		color: app.webEditorKnown() ? "#4a90e2" : "#808080"
		text: app.webEditorKnown() ? app.webEditorUrl() : "IP-adres van de Toon nog niet bekend"
	}
	Text {
		anchors {
			top: webUrl.bottom
			topMargin: 6
			left: introText.left
			right: qrFrame.left
			rightMargin: 24
		}
		wrapMode: Text.WordWrap
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 14 : 12
		color: "#808080"
		text: (app.webEditorKnown() ? "" : "Het adres staat ook onder Instellingen > Internet. ")
			+ "De webeditor gebruikt poort " + app.webPort + ". Geen verbinding vanuit de webeditor? Druk op \"Flush firewall rules\" (Instellingen > TSC), een herstart is niet nodig."
			+ (app.appVersion ? "   Versie " + app.appVersion : "")
	}

	// the web editor's address as a QR code: scan it with a phone, no typing
	Rectangle {
		id: qrFrame
		visible: app.webEditorKnown()
		width: visible ? qrCode.width + 16 : 0
		height: qrCode.height + 16
		radius: 6
		color: "#ffffff"
		anchors {
			top: webTitle.top
			right: introText.right
		}
		QrCode {
			id: qrCode
			anchors.centerIn: parent
			height: Math.round(120 * verticalScaling)
			width: height * designElements.pixelAspectRatio
			content: app.webEditorUrl()
			color: "#000000"
		}
	}
}
