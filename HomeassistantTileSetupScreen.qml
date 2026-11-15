import QtQuick 2.1
import qb.components 1.0

// what the tile shows: up to four of your chosen entities, in the order you tick them. Nothing ticked:
// the favourites. Saved at once.
Screen {
	id: tileSetupScreen

	screenTitle: "Tegel"

	property int rev: 0

	onShown: {
		app.selectionChanged.connect(update);
		update();
	}
	onHidden: app.selectionChanged.disconnect(update)

	function update() { rev++; }

	function position(id) { return rev >= 0 ? app.tileEntities.indexOf(id) : -1; }

	function toggle(id) {
		var list = app.tileEntities.slice(0);
		var position = list.indexOf(id);
		if (position >= 0) list.splice(position, 1);
		else if (list.length < app.tileMax) list.push(id);
		else return;
		app.setTileEntities(list);
	}

	Text {
		id: hint
		anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: isNxt ? 30 : 20; rightMargin: isNxt ? 30 : 20; topMargin: isNxt ? 16 : 10 }
		wrapMode: Text.WordWrap
		font.family: qfont.regular.name
		font.pixelSize: isNxt ? 16 : 13
		color: "#6b6b6b"
		text: rev < 0 ? "" : (app.tileEntities.length === 0
			? "Kies tot vier entiteiten voor de tegel, in de volgorde waarin je ze aantikt. Nu toont de tegel je favorieten."
			: (app.tileEntities.length >= app.tileMax ? "De tegel is vol (vier). Tik er een uit om een andere te kiezen."
				: "Nog " + (app.tileMax - app.tileEntities.length) + " te kiezen. Niets gekozen: de favorieten."))
	}

	ListView {
		id: list
		anchors { left: hint.left; right: hint.right; top: hint.bottom; topMargin: 10; bottom: parent.bottom; bottomMargin: isNxt ? 16 : 10 }
		clip: true
		spacing: 3
		boundsBehavior: Flickable.StopAtBounds
		model: app.entities
		delegate: Rectangle {
			property int pos: tileSetupScreen.position(modelData.id)
			width: list.width
			height: isNxt ? 54 : 44
			radius: 6
			color: rowMouse.pressed ? "#ececec" : (pos >= 0 ? "#fff6e6" : "#ffffff")
			border.color: pos >= 0 ? "#f5a623" : "#e8e8e8"
			opacity: pos < 0 && app.tileEntities.length >= app.tileMax ? 0.5 : 1
			// the place on the tile: 1-4
			Rectangle {
				id: badge
				width: isNxt ? 28 : 24
				height: width
				radius: width / 2
				anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
				color: pos >= 0 ? "#f5a623" : "#ffffff"
				border.color: pos >= 0 ? "#f5a623" : "#b0b0b0"
				Text {
					visible: pos >= 0
					anchors.centerIn: parent
					font.family: qfont.bold.name
					font.pixelSize: parent.height * 0.6
					color: "#ffffff"
					text: pos + 1
				}
			}
			Image {
				id: rowIcon
				width: isNxt ? 26 : 20
				height: width
				sourceSize.width: width
				sourceSize.height: height
				anchors { left: badge.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
				source: tileSetupScreen.rev >= 0 ? app.iconUrl(modelData.id, false) : ""
			}
			Text {
				anchors { left: rowIcon.right; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
				elide: Text.ElideRight
				font.family: qfont.semiBold.name
				font.pixelSize: isNxt ? 17 : 14
				color: "#1d1d1b"
				text: tileSetupScreen.rev >= 0 ? app.displayName(modelData.id) + (modelData.fav ? "  ★" : "") : ""
			}
			MouseArea {
				id: rowMouse
				anchors.fill: parent
				onClicked: tileSetupScreen.toggle(modelData.id)
			}
		}
	}
}
