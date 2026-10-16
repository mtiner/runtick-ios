import AVFoundation

/// Retained by the celebration view so playback lasts for its visible lifetime.
@MainActor final class PBAudio {
    private var player: AVAudioPlayer?

    func play() {
        guard let url = Bundle.main.url(forResource: "pb", withExtension: "mp3") else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            let audio = try AVAudioPlayer(contentsOf: url)
            player = audio
            audio.prepareToPlay()
            audio.play()
        } catch {
            // An unavailable audio route must never interrupt saving a result.
            player = nil
        }
    }

    func stop() { player?.stop(); player = nil }
}
