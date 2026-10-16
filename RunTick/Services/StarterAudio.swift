import AVFoundation

/// All cues share one hardware host clock; the timestamp describes scheduled speaker output.
@MainActor final class StarterAudio {
    private let engine = AVAudioEngine()
    private var nodes: [AVAudioPlayerNode] = []
    private var generation = UUID()
    func stop() { generation = UUID(); nodes.forEach { $0.stop() }; engine.stop(); nodes.forEach { engine.detach($0) }; nodes.removeAll() }
    func play(settings: [StageDelay], cue: @escaping (String) -> Void, gun: @escaping (Double, Double) -> Void) async throws {
        stop()
        guard settings.count == 3, settings.allSatisfy(\.valid) else { throw ClientError.message("等待时间须为 0–30 秒，随机上限不得小于下限") }
        let token = generation, clicked = MonotonicClock.now()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        let names = ["on-your-marks", "set", "gun"]
        let files = try names.map { name -> AVAudioFile in
            guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { throw ClientError.message("发令原声缺失") }
            return try AVAudioFile(forReading: url)
        }
        for file in files {
            let node = AVAudioPlayerNode(); engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: file.processingFormat)
            node.scheduleFile(file, at: nil); nodes.append(node)
        }
        try engine.start()
        let delays = settings.map { $0.sample() }
        let localAnchor = MonotonicClock.now(), hostAnchor = mach_absolute_time()
        var at = max(localAnchor + 100, clicked + delays[0] * 1000)
        var times: [Double] = []
        for i in 0..<3 {
            if i > 0 { at += Double(files[i-1].length) / files[i-1].processingFormat.sampleRate * 1000 + delays[i] * 1000 }
            times.append(at)
            let host = hostAnchor + AVAudioTime.hostTime(forSeconds: (at - localAnchor) / 1000)
            nodes[i].play(at: AVAudioTime(hostTime: host))
        }
        cue("等待各就位…")
        for i in 0..<3 {
            let remaining = times[i] - MonotonicClock.now()
            if remaining > 0 { try await Task.sleep(for: .milliseconds(remaining)) }
            guard generation == token, engine.isRunning else { throw CancellationError() }
            cue(["各就位", "预备", "砰！"][i])
            if i == 2 { gun(times[i] + (session.outputLatency + session.ioBufferDuration) * 1000, 20) }
        }
    }
}
