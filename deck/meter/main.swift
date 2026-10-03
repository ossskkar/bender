// ArisuMeter: how loud Spotify is on the Mac, 30 times a second, as UDP
// datagrams to the deck on 127.0.0.1:8885 (Oscar, 2026-10-01). Her idle
// voice visual moves with it on the iPad.
//
// A Core Audio process tap on Spotify's own processes, so nothing else the Mac
// plays moves her and the audio itself never leaves this process -- only one
// number does. Needs "System Audio Recording" once (Privacy & Security).
//
// Build: deck/meter/build.sh -- the app lives in ~/Applications because
// launchd may not read ~/Documents.

import AudioToolbox
import CoreAudio
import Foundation

/// Mastered music is loud all the time, so plain RMS barely moves. The level
/// is a quiet base from loudness plus a kick from how far this 33 ms rose above
/// the last second -- which is the beat.
///
/// Both are measured against a decaying peak rather than against 1.0, because
/// the fixed gains only worked for one playback volume: his Spotify was coming
/// through the tap at an RMS of about 0.005 and she never moved (Oscar,
/// 2026-10-03). Normalised, a quiet track moves her as much as a loud one.
let base: Float = 0.55, kick: Float = 2.6
/// Below this the tap is carrying silence, not quiet music, and she holds
/// still rather than dancing to the noise floor.
let floorRMS: Float = 0.0004
/// How fast the peak forgets: about seven seconds at 30 Hz, so one loud
/// moment does not flatten the rest of the track and a pause is noticed
/// quickly.
let peakDecay: Float = 0.995
let port: UInt16 = 8885

func get<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ value: inout T) -> OSStatus {
    var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value)
}

/// Every audio process object belonging to Spotify (it plays from a helper).
func spotify() -> [AudioObjectID] {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == 0
    else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == 0
    else { return [] }
    return ids.filter { id in
        var bundle: CFString = "" as CFString
        return get(id, kAudioProcessPropertyBundleID, &bundle) == 0
            && (bundle as String).hasPrefix("com.spotify.client")
    }.sorted()
}

let sock = socket(AF_INET, SOCK_DGRAM, 0)
var dest = sockaddr_in()
dest.sin_family = sa_family_t(AF_INET)
dest.sin_port = port.bigEndian
dest.sin_addr.s_addr = inet_addr("127.0.0.1")

func send(_ level: Float) {
    let text = String(format: "%.3f", level)
    _ = text.withCString { p in
        withUnsafePointer(to: &dest) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(sock, p, strlen(p), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
}

final class Tap {
    var tap = AudioObjectID(0), device = AudioObjectID(0)
    var proc: AudioDeviceIOProcID?
    var sum: Float = 0, count = 0
    var slow: Float = 0
    /// The loudest 33 ms lately, which is what everything is measured against.
    var peak: Float = 0
    var last = Date()

    init?(_ processes: [AudioObjectID]) {
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted
        desc.isPrivate = true
        guard AudioHardwareCreateProcessTap(desc, &tap) == 0 else { return nil }

        var output = AudioObjectID(0)
        _ = get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice, &output)
        var uid: CFString = "" as CFString
        _ = get(output, kAudioDevicePropertyDeviceUID, &uid)
        let spec: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ArisuMeter",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: uid as String,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid as String]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(spec as CFDictionary, &device) == 0 else {
            AudioHardwareDestroyProcessTap(tap); return nil
        }
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) { [weak self] _, input, _, _, _ in
            self?.feed(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)))
        }
        guard status == 0, AudioDeviceStart(device, proc) == 0 else { stop(); return nil }
    }

    func feed(_ buffers: UnsafeMutableAudioBufferListPointer) {
        for b in buffers {
            guard let data = b.mData else { continue }
            let n = Int(b.mDataByteSize) / MemoryLayout<Float>.size
            let f = data.assumingMemoryBound(to: Float.self)
            for i in 0..<n { sum += f[i] * f[i] }
            count += n
        }
        guard Date().timeIntervalSince(last) >= 1.0 / 30, count > 0 else { return }
        let fast = (sum / Float(count)).squareRoot()
        slow += (fast - slow) * 0.06          // about a second at 30 Hz
        peak = max(fast, peak * peakDecay)
        // Silence is silence at any gain: the second-long average decides
        // whether anything is playing, and the peak only decides the scale.
        // Without this, a pause left her dancing to the noise floor, which is
        // exactly what normalising does to nothing (Oscar, 2026-10-03).
        if slow < floorRMS * 3 || peak < floorRMS {
            send(0)
        } else {
            let loud = fast / peak                       // 0…1 whatever the volume
            let beat = max(0, fast - slow) / peak        // the rise, same scale
            send(min(1, loud * base + beat * kick))
        }
        sum = 0; count = 0; last = Date()
    }

    func stop() {
        if let proc { AudioDeviceStop(device, proc); AudioDeviceDestroyIOProcID(device, proc) }
        if device != 0 { AudioHardwareDestroyAggregateDevice(device) }
        AudioHardwareDestroyProcessTap(tap)
    }
}

// Spotify starts, quits and moves its audio between helpers: look again every
// few seconds and rebuild the tap when the set of processes changed.
var current: [AudioObjectID] = []
var tap: Tap?
Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
    let now = spotify()
    guard now != current else { return }
    tap?.stop(); tap = nil
    current = now
    if !now.isEmpty { tap = Tap(now) }
    if tap == nil { send(0) }
}.fire()
RunLoop.main.run()
