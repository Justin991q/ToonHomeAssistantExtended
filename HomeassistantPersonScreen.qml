import QtQuick 2.1
import qb.components 1.0

// a person or device_tracker: photo, where (Thuis, Weg, a zone), since when, and a map with the location
// (Esri's street map; "mapTileUrl" in the settings file for another map). Zoom with - and +.
Screen {
	id: personScreen

	screenTitle: "Persoon"

	property string entityId: ""
	property int rev: 0
	property variant lat: undefined
	property variant lon: undefined
	property bool hasLocation: typeof lat === "number" && typeof lon === "number"
	property int zoom: 15
	property int tileErrors: 0
	property int tilesLoaded: 0
	property int fontSize: isNxt ? 20 : 16

	onShown: {
		if (args && args.entityId) entityId = args.entityId;
		screenTitle = app.displayName(entityId);
		app.statesUpdated.connect(update);
		update();
		app.pollStates();
	}
	onHidden: app.statesUpdated.disconnect(update)

	function update() {
		rev++;
		lat = app.attr(entityId, "latitude");
		lon = app.attr(entityId, "longitude");
	}

	// ---- photo, where, since ----
	Column {
		id: info
		width: isNxt ? 250 : 190
		anchors { left: parent.left; leftMargin: isNxt ? 40 : 28; top: parent.top; topMargin: isNxt ? 30 : 20 }
		spacing: isNxt ? 8 : 5

		Item {
			width: isNxt ? 120 : 90
			height: width
			Image {
				id: photo
				anchors.fill: parent
				fillMode: Image.PreserveAspectCrop
				asynchronous: true
				sourceSize.width: width
				source: rev >= 0 ? app.pictureUrl(entityId) : ""
			}
			Image {
				visible: photo.status !== Image.Ready
				anchors.fill: parent
				sourceSize.width: width
				sourceSize.height: height
				source: rev >= 0 ? app.iconUrl(entityId, false) : ""
			}
		}
		Text {
			width: parent.width
			elide: Text.ElideRight
			font.family: qfont.bold.name
			font.pixelSize: isNxt ? 32 : 26
			color: rev >= 0 && app.haStates[entityId] && app.haStates[entityId].state === "home" ? "#3b7d16" : "#1d1d1b"
			text: rev >= 0 ? app.stateText(entityId) : ""
		}
		Text {
			width: parent.width
			wrapMode: Text.WordWrap
			font.family: qfont.regular.name
			font.pixelSize: personScreen.fontSize
			color: "#6b6b6b"
			text: rev >= 0 ? app.sinceText(entityId) : ""
		}
		Text {
			visible: rev >= 0 && typeof app.attr(entityId, "gps_accuracy") === "number"
			width: parent.width
			wrapMode: Text.WordWrap
			font.family: qfont.regular.name
			font.pixelSize: personScreen.fontSize - 3
			color: "#8a8a8a"
			text: visible ? "Nauwkeurig tot " + Math.round(app.attr(entityId, "gps_accuracy")) + " m" : ""
		}
	}

	// ---- the map ----
	Rectangle {
		id: mapFrame
		anchors { left: info.right; leftMargin: isNxt ? 30 : 20; right: parent.right; rightMargin: isNxt ? 30 : 20; top: parent.top; bottom: parent.bottom; topMargin: isNxt ? 20 : 14; bottomMargin: isNxt ? 20 : 14 }
		radius: 10
		color: "#e9e5dc"
		border.color: "#d6d6d6"
		clip: true

		// the location in world pixels at this zoom (Web Mercator, 256-pixel tiles)
		property real worldX: hasLocation ? (lon + 180) / 360 * Math.pow(2, zoom) * 256 : 0
		property real worldY: {
			if (!hasLocation) return 0;
			var r = lat * Math.PI / 180;
			return (1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2 * Math.pow(2, zoom) * 256;
		}
		// the tiles that cover the frame: [{x, y, left, top}]
		property variant tiles: {
			if (!hasLocation || width <= 0) return [];
			var out = [];
			var n = Math.pow(2, zoom);
			var x0 = Math.floor((worldX - width / 2) / 256), x1 = Math.floor((worldX + width / 2) / 256);
			var y0 = Math.floor((worldY - height / 2) / 256), y1 = Math.floor((worldY + height / 2) / 256);
			for (var ty = y0; ty <= y1; ty++) {
				if (ty < 0 || ty >= n) continue;
				for (var tx = x0; tx <= x1; tx++) {
					out.push({url: tileUrl(((tx % n) + n) % n, ty), left: tx * 256 - worldX + width / 2, top: ty * 256 - worldY + height / 2});
				}
			}
			return out;
		}

		function tileUrl(x, y) {
			return app.mapTileUrl.split("{z}").join(String(zoom)).split("{x}").join(String(x)).split("{y}").join(String(y));
		}

		onTilesChanged: { personScreen.tileErrors = 0; personScreen.tilesLoaded = 0; }

		Repeater {
			model: mapFrame.tiles
			Image {
				x: modelData.left
				y: modelData.top
				width: 256
				height: 256
				asynchronous: true
				source: modelData.url
				onStatusChanged: {
					if (status === Image.Error) personScreen.tileErrors++;
					if (status === Image.Ready) personScreen.tilesLoaded++;
				}
			}
		}

		// how precise the location is
		Rectangle {
			visible: hasLocation && typeof app.attr(entityId, "gps_accuracy") === "number" && rev >= 0
			property real metresPerPixel: hasLocation ? 156543.03 * Math.cos(lat * Math.PI / 180) / Math.pow(2, zoom) : 1
			width: visible ? Math.min(mapFrame.width * 2, 2 * app.attr(entityId, "gps_accuracy") / metresPerPixel) : 0
			height: width
			radius: width / 2
			anchors.centerIn: parent
			color: "#302f7fd8"
			border.color: "#802f7fd8"
		}
		Image {
			visible: hasLocation
			width: isNxt ? 44 : 36
			height: width
			sourceSize.width: width
			sourceSize.height: height
			x: mapFrame.width / 2 - width / 2
			y: mapFrame.height / 2 - height + 3          // the pin's point on the spot
			source: Qt.resolvedUrl("drawables/icons/pin-on.svg")
		}

		Text {
			visible: !hasLocation || (personScreen.tileErrors > 0 && personScreen.tilesLoaded === 0)
			anchors.centerIn: parent
			width: parent.width * 0.8
			horizontalAlignment: Text.AlignHCenter
			wrapMode: Text.WordWrap
			font.family: qfont.regular.name
			font.pixelSize: personScreen.fontSize
			color: "#6b6b6b"
			text: !hasLocation ? "Geen locatie bekend" : "De kaart laden lukt niet"
		}

		// zoom
		Column {
			visible: hasLocation
			spacing: 8
			anchors { right: parent.right; top: parent.top; margins: 10 }
			HaRoundButton { icon: "plus"; enabled: zoom < 18; onClicked: zoom++ }
			HaRoundButton { icon: "minus"; enabled: zoom > 3; onClicked: zoom-- }
		}

		Rectangle {
			visible: hasLocation
			anchors { right: parent.right; bottom: parent.bottom }
			width: credit.implicitWidth + 10
			height: credit.implicitHeight + 4
			color: "#b0ffffff"
			Text {
				id: credit
				anchors.centerIn: parent
				font.family: qfont.regular.name
				font.pixelSize: isNxt ? 12 : 10
				color: "#444444"
				text: app.mapTileUrl.indexOf("arcgisonline") >= 0 ? "Kaart © Esri" : (app.mapTileUrl.indexOf("openstreetmap") >= 0 ? "© OpenStreetMap" : "")
			}
		}
	}
}
