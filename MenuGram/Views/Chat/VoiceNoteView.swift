import SwiftUI
import AVFoundation

struct VoiceNoteView: View {
    let fileId: Int
    let duration: Int
    let waveform: Data

    @Environment(TelegramService.self) private var telegram
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var isDownloading = false
    @State private var playablePath: String?
    @State private var errorText: String?
    @State private var timer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                // Play/Pause button
                Button {
                    Task { await togglePlayback() }
                } label: {
                    Group {
                        if isDownloading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16))
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(isDownloading)

                // Waveform / progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        WaveformShape(waveform: waveform)
                            .fill(.secondary.opacity(0.3))

                        WaveformShape(waveform: waveform)
                            .fill(.blue)
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(width: geo.size.width * progress)
                            }
                    }
                }
                .frame(height: 24)

                // Duration
                Text(formatDuration(isPlaying ? Int(Double(duration) * (1 - progress)) : duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear {
            stopPlayback()
        }
    }

    private func togglePlayback() async {
        if isPlaying {
            stopPlayback()
            return
        }

        errorText = nil

        // Download and prepare the file if needed
        if playablePath == nil {
            isDownloading = true
            defer { isDownloading = false }

            // Download from TDLib
            guard let downloadedPath = await telegram.downloadVoiceNote(fileId: fileId) else {
                errorText = "Download failed"
                return
            }

            // Telegram voice notes are OGG Opus — convert to WAV for reliable playback
            if let wavPath = OGGOpusConverter.convertToWAV(oggPath: downloadedPath) {
                playablePath = wavPath
            } else {
                // Fallback: use the downloaded file directly (works for MP3, M4A, etc.)
                playablePath = downloadedPath
            }
        }

        guard let path = playablePath else { return }

        do {
            let url = URL(fileURLWithPath: path)
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            player = audioPlayer

            guard audioPlayer.play() else {
                errorText = "Playback failed"
                playablePath = nil
                return
            }
            isPlaying = true

            // Schedule timer on the main run loop so it fires reliably
            let progressTimer = Timer(timeInterval: 0.05, repeats: true) { _ in
                guard let p = self.player, p.duration > 0 else { return }
                if p.isPlaying {
                    self.progress = p.currentTime / p.duration
                } else {
                    self.stopPlayback()
                }
            }
            RunLoop.main.add(progressTimer, forMode: .common)
            timer = progressTimer
        } catch {
            errorText = "Playback error"
            playablePath = nil
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        timer?.invalidate()
        timer = nil
        progress = 0
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Waveform Shape
struct WaveformShape: Shape {
    let waveform: Data
    private let barCount = 32

    func path(in rect: CGRect) -> Path {
        let samples = decodeSamples()
        guard !samples.isEmpty else { return Path() }

        var path = Path()
        let barWidth = rect.width / CGFloat(barCount)
        let gap: CGFloat = 1

        for i in 0..<min(barCount, samples.count) {
            let amplitude = CGFloat(samples[i]) / 31.0
            let barHeight = max(2, rect.height * amplitude)
            let x = CGFloat(i) * barWidth
            let y = (rect.height - barHeight) / 2

            let bar = RoundedRectangle(cornerRadius: 1)
                .path(in: CGRect(x: x + gap / 2, y: y, width: barWidth - gap, height: barHeight))
            path.addPath(bar)
        }
        return path
    }

    private func decodeSamples() -> [UInt8] {
        // TDLib waveform is 5-bit packed
        var samples: [UInt8] = []
        var bitBuffer: UInt32 = 0
        var bitsInBuffer = 0

        for byte in waveform {
            bitBuffer |= UInt32(byte) << bitsInBuffer
            bitsInBuffer += 8

            while bitsInBuffer >= 5 {
                samples.append(UInt8(bitBuffer & 0x1F))
                bitBuffer >>= 5
                bitsInBuffer -= 5
            }
        }

        // Resample to barCount
        guard !samples.isEmpty else { return [] }
        if samples.count <= barCount { return samples }

        var resampled: [UInt8] = []
        let step = Double(samples.count) / Double(barCount)
        for i in 0..<barCount {
            let index = min(Int(Double(i) * step), samples.count - 1)
            resampled.append(samples[index])
        }
        return resampled
    }
}
