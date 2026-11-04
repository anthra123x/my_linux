import QtQuick
import Quickshell.Services.Mpris
import qs.theme

// Boton de la barra para visualizar el estado de reproduccion y desplegar el mini reproductor.
StatusButton {
    id: root

    readonly property var players: Mpris.players.values
    readonly property var activePlayer: {
        if (!players || players.length === 0) return null
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing) return players[i]
        }
        return players[0]
    }

    readonly property bool isPlaying: activePlayer?.playbackState === MprisPlaybackState.Playing
    readonly property string title: activePlayer?.trackTitle || ""
    readonly property string artist: activePlayer?.trackArtist || ""

    icon: isPlaying ? "music_note" : (activePlayer ? "play_arrow" : "music_note")
    label: {
        if (!activePlayer || title === "") return ""
        const text = artist !== "" ? `${artist} - ${title}` : title
        return text.length > 22 ? text.slice(0, 21) + "…" : text
    }
    dim: !activePlayer
    highlighted: isPlaying
    tooltip: activePlayer ? (artist !== "" ? `${artist}: ${title}` : title) : "Reproductor multimedia"
}
