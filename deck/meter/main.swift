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

/// Music RMS sits around 0.05-0.3; this maps a loud track near 1.
/// ponytail: one fixed gain, an auto-gain if quiet and loud tracks differ too much.
let gain: Float = 3.5
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
        send(min(1, (sum / Float(count)).squareRoot() * gain))
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
