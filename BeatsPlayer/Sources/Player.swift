import AVFoundation
import MediaPlayer
import SwiftUI

struct Track: Identifiable {
    let id = UUID()
    let url: URL
    var title: String
    var artist: String
    var cover: UIImage?
}

final class Player: ObservableObject {
    static let defaultColors: [Color] = [
        Color(red: 0.63, green: 0.40, blue: 0.25),
        Color(red: 0.42, green: 0.29, blue: 0.23),
        Color(red: 0.48, green: 0.35, blue: 0.19)]

    @Published var tracks: [Track] = []
    @Published var index = 0
    @Published var isPlaying = false
    @Published var time = 0.0
    @Published var duration = 1.0
    @Published var levels = [Float](repeating: 0, count: 5)
    @Published var colors = Player.defaultColors
    @Published var volume: Float = 0.8 { didSet { applyFx() } }
    @Published var bass: Float = 0 { didSet { applyFx() } }

    var current: Track? { tracks.indices.contains(index) ? tracks[index] : nil }

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)
    private var file: AVAudioFile?
    private var offset = 0.0
    private var gen = 0

    init() {
        let lo = eq.bands[0]; lo.filterType = .lowShelf; lo.frequency = 90; lo.bypass = false
        let mid = eq.bands[1]; mid.filterType = .parametric; mid.frequency = 55; mid.bandwidth = 1; mid.bypass = false
        engine.attach(node); engine.attach(eq)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buf, _ in
            let l = Player.analyze(buf)
            DispatchQueue.main.async { self?.feed(l) }
        }
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        applyFx(); setupRemote()
    }

    // MARK: Effects
    private func applyFx() {
        engine.mainMixerNode.outputVolume = volume * volume
        eq.bands[0].gain = bass * 14
        eq.bands[1].gain = bass * 8
    }

    // 5 bands via Goertzel: 60, 150, 400, 1500, 5000 Hz
    static func analyze(_ buf: AVAudioPCMBuffer) -> [Float] {
        guard let ch = buf.floatChannelData?[0] else { return [0, 0, 0, 0, 0] }
        let n = min(Int(buf.frameLength), 1024)
        let sr = Float(buf.format.sampleRate)
        guard n > 0 else { return [0, 0, 0, 0, 0] }
           let freqs: [Float] = [60, 150, 400, 1500, 5000]
        var result = [Float]()
        for (i, f) in freqs.enumerated() {
            let c: Float = 2 * cosf(2 * Float.pi * f / sr)
            var s1: Float = 0
            var s2: Float = 0
            for k in 0..<n {
                let s0: Float = ch[k] + c * s1 - s2
                s2 = s1
                s1 = s0
            }
            let p: Float = max(0, s1 * s1 + s2 * s2 - c * s1 * s2)
            let boost: Float = 1 + Float(i) * 0.6
            let amp: Float = sqrtf(p) / Float(n) * 7 * boost
            result.append(min(1, powf(amp, 0.8)))
        }
        return result

    private func feed(_ l: [Float]) {
        guard isPlaying else { return }
        for i in 0..<5 { levels[i] = max(l[i], levels[i] * 0.82) }
    }

    private func tick() {
        if isPlaying {
            if let nt = node.lastRenderTime, let pt = node.playerTime(forNodeTime: nt) {
                time = min(duration, offset + Double(pt.sampleTime) / pt.sampleRate)
            }
        } else {
            levels = levels.map { $0 * 0.85 }
        }
    }

    // MARK: Library
    func add(_ urls: [URL]) {
        Task { @MainActor in
            for u in urls {
                let ok = u.startAccessingSecurityScopedResource()
                defer { if ok { u.stopAccessingSecurityScopedResource() } }
                let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let dst = dir.appendingPathComponent(UUID().uuidString + "-" + u.lastPathComponent)
                do { try FileManager.default.copyItem(at: u, to: dst) } catch { continue }
                var t = Track(url: dst, title: u.deletingPathExtension().lastPathComponent, artist: "", cover: nil)
                let items = (try? await AVURLAsset(url: dst).load(.commonMetadata)) ?? []
                func find(_ id: AVMetadataIdentifier) -> AVMetadataItem? {
                    AVMetadataItem.metadataItems(from: items, filteredByIdentifier: id).first
                }
                if let x = find(.commonIdentifierTitle), let s = try? await x.load(.stringValue), !s.isEmpty { t.title = s }
                if let x = find(.commonIdentifierArtist), let s = try? await x.load(.stringValue) { t.artist = s }
                if let x = find(.commonIdentifierArtwork), let d = try? await x.load(.dataValue) { t.cover = UIImage(data: d) }
                tracks.append(t)
            }
            if file == nil, !tracks.isEmpty { load(0) }
        }
    }

    // MARK: Playback
    func load(_ i: Int, play go: Bool = true) {
        guard !tracks.isEmpty else { return }
        index = (i + tracks.count) % tracks.count
        let t = tracks[index]
        guard let f = try? AVAudioFile(forReading: t.url) else { return }
        file = f
        duration = max(1, Double(f.length) / f.processingFormat.sampleRate)
        node.stop(); engine.stop()
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: eq, format: f.processingFormat)
        try? engine.start()
        schedule(0); time = 0
        withAnimation(.easeInOut(duration: 1.5)) {
            colors = t.cover.flatMap(Player.palette) ?? Player.defaultColors
        }
        if go { play() } else { isPlaying = false }
        updateInfo()
    }

    private func schedule(_ frame: AVAudioFramePosition) {
        guard let f = file else { return }
        node.stop(); gen += 1; let g = gen
        let remaining = AVAudioFrameCount(max(1, f.length - frame))
        node.scheduleSegment(f, startingFrame: frame, frameCount: remaining, at: nil) { [weak self] in
            DispatchQueue.main.async { if let s = self, s.gen == g { s.next() } }
        }
        offset = Double(frame) / f.processingFormat.sampleRate
    }

    func play() {
        guard file != nil else { return }
        if !engine.isRunning { try? engine.start() }
        node.play(); isPlaying = true
        UIApplication.shared.isIdleTimerDisabled = true   // screen stays on
        updateInfo()
    }
    func pause() {
        node.pause(); isPlaying = false
        UIApplication.shared.isIdleTimerDisabled = false
        updateInfo()
    }
    func toggle() { isPlaying ? pause() : play() }
    func next() { load(index + 1) }
    func prev() { time > 3 ? seek(0) : load(index - 1) }
    func skip(_ s: Double) { seek(time + s) }

    func seek(_ sec: Double) {
        guard let f = file else { return }
        let t = min(max(0, sec), duration - 0.1)
        let was = isPlaying
        schedule(AVAudioFramePosition(t * f.processingFormat.sampleRate))
        time = t
        if was { node.play() }
        updateInfo()
    }

    // MARK: Lock screen
    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.prev(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            if let e = e as? MPChangePlaybackPositionCommandEvent { self?.seek(e.positionTime) }
            return .success
        }
    }
    private func updateInfo() {
        guard let t = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.title, MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if let img = t.cover { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: Colors from cover
    static func palette(_ img: UIImage) -> [Color]? {
        guard let cg = img.cgImage else { return nil }
        let n = 32
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var B = [(r: Double, g: Double, b: Double, w: Double)](repeating: (0, 0, 0, 0), count: 12)
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]) / 255, g = Double(px[i + 1]) / 255, b = Double(px[i + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
            if d < 0.04 { continue }
            let s = d / (1 - abs(2 * l - 1) + 0.0001)
            let h = mx == r ? ((g - b) / d + 6).truncatingRemainder(dividingBy: 6) : (mx == g ? (b - r) / d + 2 : (r - g) / d + 4)
            let k = Int(h * 2) % 12
            let w = (s + 0.15) * max(0.1, 1 - abs(l - 0.5) * 1.5)
            B[k].r += r * w; B[k].g += g * w; B[k].b += b * w; B[k].w += w
        }
        var out = B.filter { $0.w > 0 }.sorted { $0.w > $1.w }.prefix(3)
            .map { Color(red: $0.r / $0.w, green: $0.g / $0.w, blue: $0.b / $0.w) }
        guard !out.isEmpty else { return nil }
        while out.count < 3 { out.append(out.last!.opacity(0.8)) }
        return out
    }
}
