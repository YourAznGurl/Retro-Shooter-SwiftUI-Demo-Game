import AVFoundation

/// Original synthesized cues: no external sound files or copyrighted recordings.
@MainActor
final class ArcadeAudio {
    private var voices: [AVAudioPlayer] = []
    func play(_ event: String) {
        let duration: Double = event == "start" ? 0.65 : event == "dive" ? 0.45 : 0.16
        let rate = 22050
        let count = Int(duration * Double(rate))
        var samples = Data()
        var phase = 0.0
        var noise: UInt32 = 12345
        for i in 0..<count {
            let t = Double(i) / Double(count)
            let frequency: Double
            switch event {
            case "start", "rescue": frequency = [523.0, 659, 784, 1046][min(3, Int(t * 4))]
            case "dive", "capture": frequency = 650 - t * 470
            case "fire": frequency = 1400 - t * 1000
            default: frequency = 180 + t * 100
            }
            phase += frequency / Double(rate)
            noise = noise &* 1664525 &+ 1013904223
            let wave = event == "explosion" ? Double(Int(noise % 2000) - 1000) / 1000 : (phase.truncatingRemainder(dividingBy: 1) < 0.5 ? 1.0 : -1.0)
            var sample = Int16(wave * (1-t) * 3200).littleEndian
            withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
        }
        var data = Data()
        func word(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func long(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        data.append(contentsOf: "RIFF".utf8); long(UInt32(36 + samples.count))
        data.append(contentsOf: "WAVEfmt ".utf8); long(16); word(1); word(1)
        long(UInt32(rate)); long(UInt32(rate * 2)); word(2); word(16)
        data.append(contentsOf: "data".utf8); long(UInt32(samples.count)); data.append(samples)
        voices.removeAll { !$0.isPlaying }
        guard voices.count < 8, let player = try? AVAudioPlayer(data: data) else { return }
        voices.append(player); player.play()
    }
}
