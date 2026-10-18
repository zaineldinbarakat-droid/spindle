import Accelerate
import AppKit
import CoreAudio

/// How loud the music is right now, in a handful of frequency bands — so the waves
/// can move with the song itself rather than a made-up rhythm.
///
/// Uses a Core Audio process tap (macOS 14.2+): the system's own, permissioned way to
/// listen to what the Mac is playing. macOS asks once ("…would like to capture system
/// audio"). Nothing is recorded or kept: each buffer is reduced to a few band levels
/// and dropped. The tap only runs while a view is showing live waves.
@MainActor
final class AudioLevels {
    static let shared = AudioLevels()

    /// Bands from bass to treble, each 0…1 (a little over on a big moment). Smoothed:
    /// quick to rise, slower to fall.
    private(set) var bands: [Float] = Array(repeating: 0, count: AudioLevels.bandCount)
    nonisolated static let bandCount = 16
    /// A loud hit right now — a drum, a drop — from 0 (steady) to 1, for a flash of glow.
    private(set) var punch: Float = 0
    /// 0 (calm) … 1 (wild): how much loud moments and high notes are exaggerated.
    var intensity: Float = Float(Defaults.double(.waveIntensity, default: 0.6))

    // Each band's recent range, so every song — quiet or loud, bass-heavy or bright —
    // fills the bars, and what stands out is what's changing.
    private var peaks = [Float](repeating: 0.25, count: AudioLevels.bandCount)
    private var floors = [Float](repeating: 0, count: AudioLevels.bandCount)
    private var bandAverages = [Float](repeating: 0, count: AudioLevels.bandCount)
    private var energyAverage: Float = 0

    /// Whether the tap is up and delivering sound.
    private(set) var isRunning = false
    /// Set when macOS refused (no permission, or the API is missing).
    private(set) var failure: String?

    private var subscribers: [UUID: ([Float], Float) -> Void] = [:]
    private var ticker: Timer?
    private var tap: AnyObject?

    /// Calls `handler` about 30 times a second with fresh levels (bands, punch) while
    /// it's subscribed.
    func subscribe(_ handler: @escaping ([Float], Float) -> Void) -> UUID {
        let id = UUID()
        subscribers[id] = handler
        update()
        return id
    }

    func unsubscribe(_ id: UUID?) {
        guard let id else { return }
        subscribers[id] = nil
        update()
    }

    /// Runs exactly while something is watching: views subscribe only while music
    /// plays and "React to the music" is on.
    private func update() {
        let run = !subscribers.isEmpty
        if run && tap == nil { start() }
        if !run && tap != nil { stop() }
    }

    private func start() {
        guard #available(macOS 14.2, *) else {
            failure = "Needs macOS 14.2 or later."
            return
        }
        do {
            let systemTap = try SystemAudioTap { [weak self] levels in
                // Called on the audio queue; hop to the main actor with a copy.
                Task { @MainActor in self?.receive(levels.levels, silent: levels.silent) }
            }
            tap = systemTap
            isRunning = true
            failure = nil
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            ticker?.tolerance = 0.005
        } catch {
            failure = "macOS didn't allow listening to the system audio."
            isRunning = false
        }
    }

    private func stop() {
        ticker?.invalidate()
        ticker = nil
        tap = nil
        isRunning = false
        bands = Array(repeating: 0, count: Self.bandCount)
        punch = 0
        for handler in subscribers.values { handler(bands, punch) }
    }

    private var latest: [Float]?
    /// Analysis windows in a row that were exact digital silence.
    private var silentStreak = 0

    /// The first time Spindle runs with live waves on, listen for a moment so macOS
    /// asks for permission right away — not later, in the middle of a song.
    func askForPermissionOnce() {
        guard !Defaults.bool(.askedForAudio, default: false) else { return }
        Defaults.set(.askedForAudio, true)
        let probe = subscribe { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.unsubscribe(probe) }
    }

    /// Try again after the user changed something (e.g. turned the setting back on).
    func retry() {
        failure = nil
        silentStreak = 0
    }

    private func receive(_ levels: [Float], silent: Bool) {
        latest = levels
        silentStreak = silent ? silentStreak + 1 : 0
        // Music never comes as three seconds of exact zeros; macOS hands over silence
        // like that when the permission was declined. Say so, and let the waves go
        // back to their usual rhythm.
        if silentStreak > 140 {
            failure = "macOS isn't sharing the sound with Spindle — allow it under Privacy & Security → Screen & System Audio Recording."
            stop()
            // It might just have been a long pause in the music: look again later
            // (the waves pick it up on the next play or pause).
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.retry() }
        }
    }

    /// Turns the newest levels into motion that talks back to the song, and hands it
    /// out: each band is read against its own recent range, the contrast is stretched
    /// so quiet passages sit low and loud ones reach high, and sudden changes are
    /// exaggerated — a loud hit lifts every bar and flashes the glow, a high note makes
    /// the treble bars on the right leap.
    private func tick() {
        let raw = latest ?? Array(repeating: 0, count: Self.bandCount)
        let intensity = min(max(self.intensity, 0), 1)

        let energy = raw.reduce(0, +) / Float(raw.count)
        energyAverage = energyAverage * 0.97 + energy * 0.03
        let onset = max(0, energy / max(energyAverage, 0.02) - 1)
        punch = max(punch * 0.85, min(onset * 1.6, 1))

        let contrast = 1 + 0.9 * intensity
        for index in bands.indices {
            let level = raw[index]
            peaks[index] = max(level, peaks[index] * 0.996)
            floors[index] = min(level, floors[index] + 0.0015)
            let span = max(peaks[index] - floors[index], 0.12)
            // Steady music sits around the middle, leaving headroom for the big moments.
            var value = pow(min(max((level - floors[index]) / span, 0), 1) * 0.8, contrast)

            bandAverages[index] = bandAverages[index] * 0.94 + level * 0.06
            let bandOnset = max(0, level / max(bandAverages[index], 0.02) - 1)
            // Treble jumps count for more: high notes carry little energy but catch the eye.
            let trebleWeight = 0.8 + 0.8 * Float(index) / Float(bands.count - 1)
            value *= 1 + intensity * (0.9 * onset + 1.1 * bandOnset * trebleWeight)
            value = min(value, 1.15)

            // Rise fast, fall gently — how a VU meter reads.
            bands[index] = value > bands[index] ? value : bands[index] * 0.8 + value * 0.2
        }
        for handler in subscribers.values { handler(bands, punch) }
    }
}

/// The Core Audio side: a private, unmuted tap of everything the Mac plays, wrapped in
/// a private aggregate device whose input callback turns each buffer into band levels.
@available(macOS 14.2, *)
private final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "com.spindle.audiolevels", qos: .userInteractive)
    private let analyzer = BandAnalyzer(bandCount: AudioLevels.bandCount)

    enum TapError: Error { case failed(OSStatus) }

    init(onLevels: @escaping (BandAnalyzer.Result) -> Void) throws {
        // Everything the Mac plays, mixed to stereo; it keeps playing out loud.
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        description.name = "Spindle waves"
        try check(AudioHardwareCreateProcessTap(description, &tapID))

        let outputUID = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Spindle waves",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]]
        ]
        do {
            try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID))
        } catch {
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }

        let analyzer = self.analyzer
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let first = buffers.first, let data = first.mData else { return }
            let channels = Int(max(first.mNumberChannels, 1))
            let count = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
            if let levels = analyzer.feed(samples, channels: channels) { onLevels(levels) }
        }
        guard status == noErr, procID != nil else {
            teardown()
            throw TapError.failed(status)
        }
        do {
            try check(AudioDeviceStart(deviceID, procID))
        } catch {
            teardown()
            throw error
        }
    }

    deinit { teardown() }

    private func teardown() {
        if let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            self.procID = nil
        }
        if deviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(deviceID)
            deviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw TapError.failed(status) }
    }

    private static func defaultOutputUID() throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr else { throw TapError.failed(status) }
        address.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw TapError.failed(status) }
        return uid.takeRetainedValue() as String
    }
}

/// Turns a stream of samples into band levels: every 1024 mono samples, a windowed
/// FFT, summed into log-spaced bands from deep bass to treble, mapped from decibels
/// to 0…1. Runs on the audio queue only.
private final class BandAnalyzer: @unchecked Sendable {
    struct Result {
        var levels: [Float]
        /// Every sample in the window was exactly zero.
        var silent: Bool
    }

    private let size = 1024
    private let bandCount: Int
    private var buffer: [Float]
    private var filled = 0
    private let window: [Float]
    private let setup: vDSP_DFT_Setup
    private var real: [Float]
    private var imaginary: [Float]
    private var outReal: [Float]
    private var outImaginary: [Float]
    private let edges: [Int]

    init(bandCount: Int) {
        self.bandCount = bandCount
        buffer = Array(repeating: 0, count: size)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD)!
        real = Array(repeating: 0, count: size)
        imaginary = Array(repeating: 0, count: size)
        outReal = Array(repeating: 0, count: size)
        outImaginary = Array(repeating: 0, count: size)
        // Log-spaced FFT bin edges from ~45 Hz to ~14 kHz at 48 kHz.
        let low = 1.0, high = Double(size / 2 - 40)
        edges = (0...bandCount).map { Int(low * pow(high / low, Double($0) / Double(bandCount))) }
    }

    deinit { vDSP_DFT_DestroySetup(setup) }

    /// Adds samples; returns fresh levels whenever a full window is ready.
    func feed(_ samples: UnsafeBufferPointer<Float>, channels: Int) -> Result? {
        var result: Result?
        var index = 0
        while index + channels <= samples.count {
            var mono: Float = 0
            for channel in 0..<channels { mono += samples[index + channel] }
            buffer[filled] = mono / Float(channels)
            filled += 1
            index += channels
            if filled == size {
                result = analyze()
                filled = 0
            }
        }
        return result
    }

    private func analyze() -> Result {
        let silent = vDSP.maximumMagnitude(buffer) == 0
        vDSP.multiply(buffer, window, result: &real)
        for i in 0..<size { imaginary[i] = 0 }
        vDSP_DFT_Execute(setup, real, imaginary, &outReal, &outImaginary)
        var levels = [Float](repeating: 0, count: bandCount)
        for band in 0..<bandCount {
            let start = max(edges[band], 1), end = max(edges[band + 1], start + 1)
            var energy: Float = 0
            for bin in start..<min(end, size / 2) {
                energy += outReal[bin] * outReal[bin] + outImaginary[bin] * outImaginary[bin]
            }
            let magnitude = sqrt(energy / Float(end - start)) / Float(size)
            // -64 dB … -14 dB → 0 … 1, with a little lift for the treble, which carries
            // less energy but matters to the eye.
            let decibels = 20 * log10(max(magnitude, 1e-7)) + Float(band) * 0.35
            levels[band] = min(max((decibels + 64) / 50, 0), 1)
        }
        return Result(levels: levels, silent: silent)
    }
}
