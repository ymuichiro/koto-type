import AppKit
import Foundation

enum AppImageLoader {
    static func loadPNG(named name: String) -> NSImage? {
        if let image = imageFromMainBundle(named: name) {
            return image
        }

        // Fallback for local `swift run` execution where bundle resources may
        // not be copied into an app bundle yet.
        for path in developmentCandidatePaths(for: name) {
            if let image = NSImage(contentsOfFile: path) {
                return image
            }
        }

        return nil
    }

    private static func imageFromMainBundle(named name: String) -> NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }

        guard let resourcePath = Bundle.main.resourcePath else {
            return nil
        }

        let filePath = URL(fileURLWithPath: resourcePath)
            .appendingPathComponent("\(name).png")
            .path
        return NSImage(contentsOfFile: filePath)
    }

    private static func developmentCandidatePaths(for name: String) -> [String] {
        let cwd = FileManager.default.currentDirectoryPath
        return [
            "\(cwd)/Sources/KotoType/Resources/\(name).png",
            "\(cwd)/.build/arm64-apple-macosx/debug/KotoType_KotoType.bundle/\(name).png",
            "\(cwd)/.build/arm64-apple-macosx/release/KotoType_KotoType.bundle/\(name).png",
        ]
    }
}
