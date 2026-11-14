import QtQuick 2.1

// a camera picture without flicker: a new url loads into the hidden image, which is shown once it is in
Item {
	id: view

	property string entityId: ""
	property string url: ""
	property int fillMode: Image.PreserveAspectCrop
	property bool front: false                 // which image is shown: a (false) or b (true)
	property bool hasPicture: a.status === Image.Ready || b.status === Image.Ready

	onUrlChanged: {
		if (url === "") return;
		var back = front ? a : b;
		back.source = url;
	}

	Image {
		id: a
		anchors.fill: parent
		fillMode: view.fillMode
		asynchronous: true
		cache: false
		visible: !view.front && status === Image.Ready
		onStatusChanged: if (status === Image.Ready && view.front) view.front = false
	}
	Image {
		id: b
		anchors.fill: parent
		fillMode: view.fillMode
		asynchronous: true
		cache: false
		visible: view.front && status === Image.Ready
		onStatusChanged: if (status === Image.Ready && !view.front) view.front = true
	}

	Image {
		visible: !view.hasPicture
		anchors.centerIn: parent
		width: isNxt ? 48 : 38
		height: width
		sourceSize.width: width
		sourceSize.height: height
		source: Qt.resolvedUrl("drawables/icons/camera-dim.svg")
	}
}
