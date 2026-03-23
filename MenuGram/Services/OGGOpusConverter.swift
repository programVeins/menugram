import Foundation
import AVFoundation
import AudioToolbox

/// Converts OGG Opus audio files to WAV for playback on macOS.
/// macOS supports the Opus codec but not the OGG container,
/// so we parse OGG pages, decode Opus via AudioToolbox, and write WAV.
enum OGGOpusConverter {

    /// Converts an OGG Opus file to WAV. Returns the WAV file path, or nil on failure.
    /// Results are cached — subsequent calls with the same path return the cached WAV.
    static func convertToWAV(oggPath: String) -> String? {
        let wavPath = oggPath + ".wav"

        // Return cached conversion if it exists
        if FileManager.default.fileExists(atPath: wavPath) {
            return wavPath
        }

        guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: oggPath)) else { return nil }

        // Parse OGG pages
        let pages = parseOGGPages(from: fileData)
        guard pages.count >= 3 else { return nil }

        // Page 0 contains OpusHead header
        let headerPackets = assemblePackets(from: [pages[0]])
        guard let header = headerPackets.first, header.count >= 19 else { return nil }

        // Verify "OpusHead" magic bytes
        guard header.count >= 8,
              header[header.startIndex] == 0x4F,     // O
              header[header.startIndex+1] == 0x70,   // p
              header[header.startIndex+2] == 0x75,   // u
              header[header.startIndex+3] == 0x73,   // s
              header[header.startIndex+4] == 0x48,   // H
              header[header.startIndex+5] == 0x65,   // e
              header[header.startIndex+6] == 0x61,   // a
              header[header.startIndex+7] == 0x64    // d
        else { return nil }

        let channels = UInt32(header[header.startIndex + 9])
        let preSkip = Int(UInt16(header[header.startIndex + 10]) | (UInt16(header[header.startIndex + 11]) << 8))

        // Extract audio packets from pages 2+ (skip header and comment pages)
        let audioPages = Array(pages.dropFirst(2))
        let opusPackets = assemblePackets(from: audioPages)
        guard !opusPackets.isEmpty else { return nil }

        // Decode Opus to PCM
        guard let pcmData = decodeOpusToPCM(packets: opusPackets, channels: channels, preSkip: preSkip) else { return nil }

        // Write as WAV
        guard writeWAV(pcmData: pcmData, channels: channels, sampleRate: 48000, to: wavPath) else { return nil }

        return wavPath
    }

    // MARK: - OGG Page Parser

    private struct OGGPage {
        let headerType: UInt8
        let segments: [Data]
    }

    private static func parseOGGPages(from data: Data) -> [OGGPage] {
        var pages: [OGGPage] = []
        var offset = data.startIndex

        while offset + 27 <= data.endIndex {
            // Check "OggS" sync pattern
            guard data[offset] == 0x4F,
                  data[offset+1] == 0x67,
                  data[offset+2] == 0x67,
                  data[offset+3] == 0x53
            else {
                // Try to find next sync point
                offset += 1
                continue
            }

            let headerType = data[offset + 5]
            let numSegments = Int(data[offset + 26])

            guard offset + 27 + numSegments <= data.endIndex else { break }

            // Read segment table
            var segmentSizes: [Int] = []
            for i in 0..<numSegments {
                segmentSizes.append(Int(data[offset + 27 + i]))
            }

            // Read segment data
            var dataOffset = offset + 27 + numSegments
            var segments: [Data] = []
            var valid = true
            for size in segmentSizes {
                guard dataOffset + size <= data.endIndex else {
                    valid = false
                    break
                }
                segments.append(Data(data[dataOffset..<dataOffset+size]))
                dataOffset += size
            }

            if valid {
                pages.append(OGGPage(headerType: headerType, segments: segments))
            }
            offset = dataOffset
        }

        return pages
    }

    /// Assembles complete packets from OGG segments.
    /// In OGG, a segment of exactly 255 bytes means "continued in next segment".
    /// A segment shorter than 255 bytes marks the end of a packet.
    private static func assemblePackets(from pages: [OGGPage]) -> [Data] {
        var packets: [Data] = []
        var current = Data()

        for page in pages {
            for segment in page.segments {
                current.append(segment)
                if segment.count < 255 {
                    if !current.isEmpty {
                        packets.append(current)
                    }
                    current = Data()
                }
            }
        }

        if !current.isEmpty {
            packets.append(current)
        }

        return packets
    }

    // MARK: - Opus Decoding via AudioToolbox

    private static func decodeOpusToPCM(packets: [Data], channels: UInt32, preSkip: Int) -> Data? {
        var inputFormat = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 960, // 20ms at 48kHz
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        var outputFormat = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: UInt32(kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked),
            mBytesPerPacket: 2 * channels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2 * channels,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var converterRef: AudioConverterRef?
        let createStatus = AudioConverterNew(&inputFormat, &outputFormat, &converterRef)
        guard createStatus == noErr, let converter = converterRef else { return nil }
        defer { AudioConverterDispose(converter) }

        var allPCMData = Data()

        for packet in packets {
            guard !packet.isEmpty else { continue }

            // Output buffer: 960 frames per Opus packet (20ms at 48kHz)
            let maxFrames: UInt32 = 5760 // max Opus frame size (120ms)
            let outputByteSize = Int(maxFrames * 2 * channels)
            let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outputByteSize)
            defer { outputBuffer.deallocate() }

            var outputBufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: channels,
                    mDataByteSize: UInt32(outputByteSize),
                    mData: outputBuffer
                )
            )

            var ioOutputPackets: UInt32 = maxFrames

            // Context for the input callback
            let packetCopy = [UInt8](packet)
            var context = InputContext(packetData: packetCopy, consumed: false)

            let status = withUnsafeMutablePointer(to: &context) { ctxPtr in
                AudioConverterFillComplexBuffer(
                    converter,
                    opusInputCallback,
                    ctxPtr,
                    &ioOutputPackets,
                    &outputBufferList,
                    nil
                )
            }

            if status == noErr || status == 100 /* end of data */ {
                let bytesProduced = Int(outputBufferList.mBuffers.mDataByteSize)
                if bytesProduced > 0 {
                    allPCMData.append(outputBuffer, count: bytesProduced)
                }
            }
        }

        // Apply pre-skip: remove initial samples as specified by Opus header
        let bytesToSkip = preSkip * Int(2 * channels)
        if bytesToSkip > 0 && bytesToSkip < allPCMData.count {
            allPCMData = Data(allPCMData.dropFirst(bytesToSkip))
        }

        return allPCMData.isEmpty ? nil : allPCMData
    }

    // Context passed through the AudioConverter callback
    private struct InputContext {
        let packetData: [UInt8]
        var consumed: Bool
    }

    // C-compatible callback for AudioConverterFillComplexBuffer
    private static let opusInputCallback: AudioConverterComplexInputDataProc = {
        (
            _: AudioConverterRef,
            ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
            ioData: UnsafeMutablePointer<AudioBufferList>,
            outPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
            inUserData: UnsafeMutableRawPointer?
        ) -> OSStatus in

        guard let userData = inUserData else {
            ioNumberDataPackets.pointee = 0
            return -50 // paramErr
        }

        let context = userData.assumingMemoryBound(to: InputContext.self)

        if context.pointee.consumed {
            ioNumberDataPackets.pointee = 0
            return 100 // no more data
        }

        // Point the buffer to our packet data (stored in context, stable for callback lifetime)
        let dataPtr = context.pointee.packetData.withUnsafeBufferPointer { $0.baseAddress! }
        let dataCount = context.pointee.packetData.count

        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mNumberChannels = 0
        ioData.pointee.mBuffers.mDataByteSize = UInt32(dataCount)
        ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: dataPtr)

        // Provide packet description
        if let outDesc = outPacketDescription {
            // We need a stable pointer for the packet description
            let descPtr = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
            descPtr.pointee = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(dataCount)
            )
            outDesc.pointee = descPtr
        }

        ioNumberDataPackets.pointee = 1
        context.pointee.consumed = true
        return noErr
    }

    // MARK: - WAV Writer

    private static func writeWAV(pcmData: Data, channels: UInt32, sampleRate: UInt32, to path: String) -> Bool {
        var wav = Data()
        let dataSize = UInt32(pcmData.count)
        let fileSize = 36 + dataSize
        let byteRate = sampleRate * channels * 2
        let blockAlign = UInt16(channels * 2)

        // RIFF header
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendUInt32LE(&wav, fileSize)
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt chunk
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendUInt32LE(&wav, 16) // chunk size
        appendUInt16LE(&wav, 1)  // PCM format
        appendUInt16LE(&wav, UInt16(channels))
        appendUInt32LE(&wav, sampleRate)
        appendUInt32LE(&wav, byteRate)
        appendUInt16LE(&wav, blockAlign)
        appendUInt16LE(&wav, 16) // bits per sample

        // data chunk
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendUInt32LE(&wav, dataSize)
        wav.append(pcmData)

        do {
            try wav.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }

    private static func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
