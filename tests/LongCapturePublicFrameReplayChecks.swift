import AppKit
import ImageIO

/// Public region screenshot exports, not the user's rejected Codex stream frames.
/// Remove export rounding consistently, then preserve all remaining original pixels.
@main
struct LongCapturePublicFrameReplayChecks {
    @MainActor static func main() throws {
        let root = CommandLine.arguments.count > 1
            ? URL(fileURLWithPath: CommandLine.arguments[1])
            : URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("fixtures/long-capture-pointer")
        func load(_ name: String) -> CGImage {
            let url = root.appendingPathComponent(name).appendingPathExtension("png")
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let cropped = image.cropping(to: CGRect(x: 12, y: 12, width: 521, height: 691)),
                  let detached = LongCaptureDocumentStore.detached(cropped) else {
                fatalError("Cannot load public fixture: \(url.path)")
            }
            return detached
        }
        let seed = load("probe-start")
        let wheel = load("probe-wheel")
        let clean = load("probe-redraw")
        let matcher = LongCaptureOverlapMatcher()
        let proposed = matcher.match(previous: seed, current: wheel)
        precondition(proposed != nil && seed.height - proposed!.overlapHeight == 122,
                     "A translation proposal alone must not authorize the contaminated seam")
        precondition(!LongCaptureSeamVerifier.verify(previous: seed, current: wheel,
                                                   shift: 122, footerHeight: 0))
        precondition(LongCaptureSeamVerifier.verify(previous: seed, current: clean,
                                                  shift: 122, footerHeight: 0))

        let accumulator = LongCaptureFrameAccumulator()
        _ = try accumulator.seed(image: seed)
        let rejected = accumulator.process(frame: .init(image: wheel, timestamp: 1))
        precondition(rejected?.warning != nil && rejected?.acceptedFrameCount == 1)
        do {
            _ = try accumulator.renderFinalImage()
            fatalError("The contaminated pair must not export only the accepted prefix")
        } catch LongCaptureError.incompleteCapture {}

        let recovered = accumulator.process(frame: .init(image: clean, timestamp: 2))
        precondition(recovered?.warning == nil && recovered?.acceptedFrameCount == 2 &&
                     recovered?.appendedPixelHeight == 813)
        let output = try accumulator.renderFinalImage()
        precondition(output.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height == 813)
        print("PASS: public frames reject pointer contamination, recover at the same position, and export 813px")
    }
}
