import Foundation
import Vision

// Check the actual Simulator pixels, not merely an app-launch log marker.
// In particular, reject the first-use WebKit bug that dropped cached letters.
guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift verify-ios-menu.swift app-launched.png\n", stderr)
    exit(1)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["en-US"]
request.usesLanguageCorrection = false
let handler = VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1]))
do {
    try handler.perform([request])
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    print(lines.joined(separator: "\n"))
    let normalized = lines.joined(separator: " ").uppercased()
        .replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)
    for label in ["COLLACK", "BRICKBREAKER", "AUTOBATTLER", "NEWEXPEDITION", "HOWTOPLAY"] {
        guard normalized.contains(label) else {
            fputs("[ios-menu] ERROR: visible menu is missing readable \(label)\n", stderr)
            exit(1)
        }
    }
    print("[ios-menu] OK: title, genre, and both primary actions are readable")
} catch {
    fputs("[ios-menu] ERROR: \(error)\n", stderr)
    exit(1)
}
