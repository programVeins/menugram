import SwiftUI
import AVFoundation

struct MessageInputView: View {
    @Environment(TelegramService.self) private var telegram
    @State private var text: String = ""
    @FocusState private var isFocused: Bool
    @State private var recorder: VoiceRecorder?
    @State private var isRecording = false
    @State private var recordingDuration: TimeInterval = 0
    @State private var recordingTimer: Timer?
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isRecording {
                    recordingIndicator
                        .matchedGeometryEffect(id: "bar", in: ns)
                } else {
                    TextField("Message", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($isFocused)
                        .onSubmit { send() }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.quaternary)
                        )
                        .glassEffect(in: .rect(cornerRadius: 12))
                        .matchedGeometryEffect(id: "bar", in: ns)
                }
            }

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRecording {
                // Mic button — tap to record
                Button {
                    startRecording()
                } label: {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else if isRecording {
                // Cancel button
                Button {
                    cancelRecording()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.red.gradient.opacity(0.5))
                }
                .buttonStyle(.borderless)
                .transition(.scale(scale: 0.8).combined(with: .opacity))

                // Send button
                Button {
                    stopAndSend()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue.gradient)
                }
                .buttonStyle(.borderless)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue.gradient)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.return, modifiers: .command)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .onAppear { isFocused = true }
        .animation(.snappy, value: text)
    }

    // MARK: - Recording Indicator
    
    @State private var scale: CGFloat = 1

    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(.red.opacity(0.4))
                    .frame(width: 16, height: 16)
                    .scaleEffect(scale)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                            scale = 1.3
                        }
                    }
                    .onDisappear {
                        scale = 1.0
                    }
                
                Circle()
                    .fill(.red)
                    .frame(width: 12, height: 12)
            }

            Text(formatDuration(recordingDuration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: recordingDuration))

            Spacer()

            Text("Recording...")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.red.opacity(0.1))
        )
    }

    // MARK: - Actions

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chatId = telegram.currentChatId else { return }
        let messageText = trimmed
        text = ""
        Task {
            await telegram.sendMessage(chatId: chatId, text: messageText)
        }
    }

    private func startRecording() {
        let voiceRecorder = VoiceRecorder()
        guard voiceRecorder.start() else { return }
        recorder = voiceRecorder
        NSSound(named: "Morse")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        withAnimation(.snappy) {
            isRecording = true
        }
        recordingDuration = 0

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let recorder {
                withAnimation(.snappy) {
                    self.recordingDuration = recorder.currentTime
                }
            }
        }
    }

    private func stopAndSend() {
        recordingTimer?.invalidate()
        recordingTimer = nil

        guard let recorder, let chatId = telegram.currentChatId else {
            cancelRecording()
            return
        }

        let result = recorder.stop()
        self.recorder = nil

        withAnimation(.snappy) {
            isRecording = false
        }

        guard let filePath = result?.filePath, result!.duration >= 1 else {
            // Too short, discard
            return
        }

        let duration = Int(result!.duration)
        let waveform = result!.waveform
        
        NSSound(named: "Purr")?.play()

        Task {
            await telegram.sendVoiceNote(
                chatId: chatId,
                filePath: filePath,
                duration: duration,
                waveform: waveform
            )
        }
    }

    private func cancelRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recorder?.cancel()
        recorder = nil
        withAnimation(.snappy) {
            isRecording = false
        }
        recordingDuration = 0
        NSSound(named: "Pop")?.play()
    }

    private func formatDuration(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Voice Recorder

struct VoiceRecordingResult {
    let filePath: String
    let duration: TimeInterval
    let waveform: Data
}

final class VoiceRecorder {
    private var audioRecorder: AVAudioRecorder?
    private let filePath: String

    init() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voice_\(UUID().uuidString).m4a"
        self.filePath = tempDir.appendingPathComponent(fileName).path
    }

    var currentTime: TimeInterval {
        audioRecorder?.currentTime ?? 0
    }

    func start() -> Bool {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64000
        ]

        do {
            let recorder = try AVAudioRecorder(
                url: URL(fileURLWithPath: filePath),
                settings: settings
            )
            recorder.isMeteringEnabled = true
            guard recorder.record() else { return false }
            audioRecorder = recorder
            return true
        } catch {
            return false
        }
    }

    func stop() -> VoiceRecordingResult? {
        guard let recorder = audioRecorder else { return nil }
        let duration = recorder.currentTime // must capture before stop() resets it to 0
        recorder.stop()
        audioRecorder = nil

        guard FileManager.default.fileExists(atPath: filePath) else { return nil }

        let waveform = generateWaveform()

        return VoiceRecordingResult(
            filePath: filePath,
            duration: duration,
            waveform: waveform
        )
    }

    func cancel() {
        audioRecorder?.stop()
        audioRecorder?.deleteRecording()
        audioRecorder = nil
        try? FileManager.default.removeItem(atPath: filePath)
    }

    /// Generates a 5-bit packed waveform from the recorded audio for TDLib.
    private func generateWaveform() -> Data {
        let url = URL(fileURLWithPath: filePath)
        guard let file = try? AVAudioFile(forReading: url) else { return Data() }

        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount)
        else { return Data() }

        do { try file.read(into: buffer) } catch { return Data() }

        guard let floatData = buffer.floatChannelData?[0] else { return Data() }

        // Sample down to ~100 bars, then take 63 for the waveform
        let sampleCount = 63
        let samplesPerBar = max(1, Int(frameCount) / sampleCount)
        var peaks: [Float] = []

        for i in 0..<sampleCount {
            let start = i * samplesPerBar
            let end = min(start + samplesPerBar, Int(frameCount))
            var peak: Float = 0
            for j in start..<end {
                peak = max(peak, abs(floatData[j]))
            }
            peaks.append(peak)
        }

        // Normalize to 0-31 (5-bit range)
        let maxPeak = peaks.max() ?? 1
        let normalized: [UInt8] = peaks.map { p in
            let val = maxPeak > 0 ? (p / maxPeak) * 31 : 0
            return UInt8(min(31, max(0, val)))
        }

        // Pack into 5-bit format
        return pack5Bit(normalized)
    }

    private func pack5Bit(_ samples: [UInt8]) -> Data {
        var result = Data()
        var bitBuffer: UInt32 = 0
        var bitsInBuffer = 0

        for sample in samples {
            bitBuffer |= UInt32(sample & 0x1F) << bitsInBuffer
            bitsInBuffer += 5

            while bitsInBuffer >= 8 {
                result.append(UInt8(bitBuffer & 0xFF))
                bitBuffer >>= 8
                bitsInBuffer -= 8
            }
        }

        if bitsInBuffer > 0 {
            result.append(UInt8(bitBuffer & 0xFF))
        }

        return result
    }
}
