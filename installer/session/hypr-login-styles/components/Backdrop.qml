import QtQuick
import QtMultimedia

// The desktop wallpaper: a still image, or the live video with its first frame
// shown until playback has really started.
Item {
    id: b
    property string source
    property string placeholder
    property color fill: "black"
    readonly property bool isVideo: /\.(mp4|mkv|webm|mov|m4v|avi)$/i.test(source)
    property bool started: false

    Rectangle { anchors.fill: parent; color: b.fill }

    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        visible: b.isVideo
    }
    MediaPlayer {
        id: player
        videoOutput: output
        loops: MediaPlayer.Infinite
        onPositionChanged: if (position > 0) b.started = true
    }
    Image {
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
        source: b.isVideo ? (b.placeholder ? "file://" + b.placeholder : "") : (b.source ? "file://" + b.source : "")
        visible: !b.isVideo || !b.started
    }
    Component.onCompleted: if (isVideo) { player.source = "file://" + source; player.play() }
}
