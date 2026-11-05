import AVFoundation
import MediaPlayer

/// Turns the phone's volume buttons into page-turn presses while reading.
///
/// iOS has no API for the hardware buttons, so this watches the system volume instead: the volume is parked
/// in the middle, every change is reported as a press, and the volume is put back in the middle. The
/// original volume is restored when reading stops. A volume view somewhere on screen also hides the
/// system volume indicator.
final class VolumeKeys: NSObject {
    var onPress: ((_ up: Bool) -> Void)?
    private var observation: NSKeyValueObservation?
    private var original: Float?
    private let baseline: Float = 0.5
    private weak var volumeView: MPVolumeView?

    var isActive: Bool { observation != nil }

    func start(volumeView: MPVolumeView) {
        guard observation == nil else { return }
        self.volumeView = volumeView
        let session = AVAudioSession.sharedInstance()
        // Ambient + mixWithOthers: music that is already playing keeps playing.
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        original = session.outputVolume
        setSystemVolume(baseline)
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let v = change.newValue else { return }
            DispatchQueue.main.async { self?.volumeChanged(v) }
        }
    }

    func stop() {
        guard observation != nil else { return }
        observation = nil // first, so restoring the volume is not reported as a press
        if let original { setSystemVolume(original) }
        original = nil
    }

    private func volumeChanged(_ v: Float) {
        guard abs(v - baseline) > 0.001 else { return }
        onPress?(v > baseline)
        setSystemVolume(baseline)
    }

    private func setSystemVolume(_ value: Float) {
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.value = value
    }
}
