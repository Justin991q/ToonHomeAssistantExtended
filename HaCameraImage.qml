import QtQuick 2.1

// a camera picture without flicker: a new url loads into the hidden image, which is shown once it is in.
// AnimatedImage, so a moving picture plays (e.g. a rain radar, an animated GIF); a photo shows as usual.
// animated: the picture has more than one frame (then it isn't reloaded every few seconds).
// No asynchronous: AnimatedImage then loads a GIF as a still (a network picture loads in the background anyway)
Item {
	id: view

	property string entityId: ""
	property string url: ""
	property int fillMode: Image.PreserveAspectCrop
	property bool front: false                 // which image is shown: a (false) or b (true)
	property bool hasPicture: imageA.status === Image.Ready || imageB.status === Image.Ready
	// once seen moving, remembered for this camera: a picture that is still loading doesn't know its frames yet
	property bool animated: false
	onEntityIdChanged: animated = false
	onVisibleChanged: updatePlaying(false)

	// playing only when it can be seen (whether it moves only shows once it plays; a photo costs nothing).
	// A picture from the network plays once: at its end it starts again (after a short pause, as a radar does)
	function updatePlaying(restart) {
		var list = [imageA, imageB];
		for (var index = 0; index < list.length; index++) {
			var want = list[index].visible && view.visible && list[index].status === Image.Ready;
			if (want && restart) list[index].currentFrame = 0;
			if (list[index].playing !== want) list[index].playing = want;
		}
	}
	Timer { id: loopTimer; interval: 700; onTriggered: view.updatePlaying(true) }

	onUrlChanged: {
		if (url === "") return;
		var back = front ? imageA : imageB;
		var shown = front ? imageB : imageA;
		if (shown.source.toString() === url) return;
		back.source = url;
	}

	AnimatedImage {
		id: imageA
		anchors.fill: parent
		fillMode: view.fillMode
		cache: true                // keeps the frames: a picture from the network can only be read once, so without this it can't loop
		visible: !view.front && status === Image.Ready
		playing: false
		onVisibleChanged: view.updatePlaying(false)
		onPlayingChanged: if (!playing && visible && view.visible) loopTimer.restart()   // played to the end: from the start again
		onStatusChanged: if (status === Image.Ready && view.front) { view.front = false; imageB.source = ""; }
		onFrameChanged: if (currentFrame > 0) view.animated = true       // it moved on to a next frame (frameCount is 0 while a network picture plays)
	}
	AnimatedImage {
		id: imageB
		anchors.fill: parent
		fillMode: view.fillMode
		cache: true                // keeps the frames: a picture from the network can only be read once, so without this it can't loop
		visible: view.front && status === Image.Ready
		playing: false
		onVisibleChanged: view.updatePlaying(false)
		onPlayingChanged: if (!playing && visible && view.visible) loopTimer.restart()
		onStatusChanged: if (status === Image.Ready && !view.front) { view.front = true; imageA.source = ""; }
		onFrameChanged: if (currentFrame > 0) view.animated = true       // it moved on to a next frame (frameCount is 0 while a network picture plays)
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
