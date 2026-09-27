// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nicholas Smith

import Foundation
@testable import MenuCraneCore

enum Fixtures {
    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    static var emojiJSON: URL { packageRoot.appending(path: "Resources/bundle/emoji.json") }
    static func emojiStore() throws -> EmojiStore { try EmojiStore(data: Data(contentsOf: emojiJSON)) }

    static func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "menucrane-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
