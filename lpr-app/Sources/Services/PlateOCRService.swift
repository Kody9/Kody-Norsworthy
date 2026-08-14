import UIKit
import Vision

/// Runs on-device text recognition (Apple's Vision framework) over a captured
/// photo and filters the results down to strings that plausibly look like a
/// license plate. This is heuristic, not a specialized ALPR model — always let
/// the user confirm/edit the result before saving.
enum PlateOCRService {
    struct Candidate: Identifiable, Hashable {
        let id = UUID()
        let text: String
        let confidence: Float
    }

    struct Result {
        let candidates: [Candidate]
        /// Best-effort guess from any state name/slogan text Vision also
        /// found on the plate. Nil when nothing matched — the caller
        /// should fall back to "Unknown" and let the user fill it in.
        let detectedState: String?
    }

    static func recognizePlates(in image: UIImage, completion: @escaping (Result) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(Result(candidates: [], detectedState: nil))
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard error == nil, let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(Result(candidates: [], detectedState: nil))
                return
            }
            let recognizedStrings = observations.compactMap { $0.topCandidates(1).first?.string }
            let candidates = observations.compactMap { observation -> Candidate? in
                guard let top = observation.topCandidates(1).first else { return nil }
                let cleaned = sanitize(top.string)
                guard isPlausiblePlate(cleaned) else { return nil }
                return Candidate(text: cleaned, confidence: top.confidence)
            }
            let detectedState = StateDetector.detectState(from: recognizedStrings)
            completion(Result(
                candidates: dedupe(candidates).sorted { $0.confidence > $1.confidence },
                detectedState: detectedState
            ))
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgOrientation(from: image.imageOrientation))
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    private static func sanitize(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func isPlausiblePlate(_ text: String) -> Bool {
        (4...8).contains(text.count) && text.contains { $0.isNumber }
    }

    private static func dedupe(_ candidates: [Candidate]) -> [Candidate] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.text).inserted }
    }

    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
