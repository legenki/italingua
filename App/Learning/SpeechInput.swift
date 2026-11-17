@preconcurrency import AVFoundation
import Foundation
import Observation
import Speech

/// Spoken answers: the microphone is transcribed on device in Italian
/// (SpeechAnalyzer + SpeechTranscriber, no network after the one-time
/// language download). It checks what was understood, not the accent.
@Observable
final class SpeechInput {
    enum State: Equatable {
        case idle
        case downloading(Double)
        case listening
        case finishing
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Live transcript while listening.
    private(set) var heard = ""

    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var mic: MicCapture?
    @ObservationIgnored private var resultsTask: Task<String, Never>?

    static let italian = Locale(identifier: "it-IT")

    var isListening: Bool { state == .listening }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [],
                          reportingOptions: [.volatileResults], attributeOptions: [])
    }

    /// Whether the Italian speech package is on the device.
    static func packageStatus() async -> AssetInventory.Status {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: italian) else {
            return .unsupported
        }
        return await AssetInventory.status(forModules: [makeTranscriber(locale: locale)])
    }

    /// Downloads the Italian package if needed (once, about a few hundred MB).
    func preparePackage() async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Self.italian) else {
            throw Failure("Распознавание итальянской речи на этом устройстве не поддерживается.")
        }
        let module = Self.makeTranscriber(locale: locale)
        guard await AssetInventory.status(forModules: [module]) != .installed else { return }
        _ = try? await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            state = .downloading(0)
            let watcher = Task { [weak self] in
                while !Task.isCancelled {
                    self?.state = .downloading(request.progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { watcher.cancel() }
            try await request.downloadAndInstall()
            state = .idle
        }
    }

    /// Starts listening; call `stop()` to get the final transcript.
    func start() async {
        guard state == .idle || isFailed else { return }
        heard = ""
        do {
            guard await AVAudioApplication.requestRecordPermission() else {
                throw Failure("Нет доступа к микрофону. Разреши его в Настройках → Конфиденциальность → Микрофон.")
            }
            try await preparePackage()
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Self.italian) else {
                throw Failure("Итальянский не поддерживается.")
            }
            let transcriber = Self.makeTranscriber(locale: locale)
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw Failure("Не удалось подобрать формат звука.")
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)

            resultsTask = Task { [weak self] in
                var final = ""
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        if result.isFinal {
                            final += text
                            self?.heard = final
                        } else {
                            self?.heard = final + text
                        }
                    }
                } catch {}
                return final
            }

            let mic = MicCapture()
            try mic.start(converting: format, into: input)
            self.mic = mic
            self.analyzer = analyzer
            state = .listening
            try await analyzer.start(inputSequence: stream)
        } catch let failure as Failure {
            cleanUp()
            state = .failed(failure.message)
        } catch {
            cleanUp()
            state = .failed("Не получилось включить распознавание: \(error.localizedDescription)")
        }
    }

    /// Stops the microphone and returns everything that was understood.
    func stop() async -> String {
        guard state == .listening else { return heard }
        state = .finishing
        mic?.stop()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        let text = await resultsTask?.value ?? heard
        cleanUp()
        heard = text
        state = .idle
        return text
    }

    func cancel() {
        mic?.stop()
        resultsTask?.cancel()
        Task { [analyzer] in await analyzer?.cancelAndFinishNow() }
        cleanUp()
        state = .idle
    }

    private var isFailed: Bool { if case .failed = state { true } else { false } }

    private func cleanUp() {
        mic = nil
        analyzer = nil
        resultsTask = nil
    }

    private struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    /// The answer to check, taken from what was heard: if the expected word or
    /// phrase is among the spoken words it counts as said, so "è la casa" or
    /// "Casa." for "casa" is right; otherwise the whole transcript is checked.
    nonisolated static func answer(from transcript: String, expected: String) -> String {
        func words(_ s: String) -> [String] {
            AnswerChecker.normalize(s)
                .components(separatedBy: CharacterSet(charactersIn: " .,!?;:¿¡\"«»"))
                .filter { !$0.isEmpty }
        }
        let said = words(transcript)
        let target = words(expected)
        guard !target.isEmpty, said.count >= target.count else { return said.joined(separator: " ") }
        for start in 0...(said.count - target.count) {
            if Array(said[start..<start + target.count]) == target { return expected }
        }
        return said.joined(separator: " ")
    }
}

/// Microphone capture, off the main actor: the tap runs on the audio thread
/// and feeds converted buffers to the analyzer.
private nonisolated final class MicCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?

    func start(converting target: AVAudioFormat, into input: AsyncStream<AnalyzerInput>.Continuation) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        continuation = input
        let node = engine.inputNode
        let source = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: source, to: target) else {
            throw NSError(domain: "Italingua.Mic", code: 1)
        }
        node.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
            let ratio = target.sampleRate / source.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, out.frameLength > 0 {
                input.yield(AnalyzerInput(buffer: out))
            }
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
