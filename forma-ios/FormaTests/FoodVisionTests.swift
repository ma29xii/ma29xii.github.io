import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Forma

final class FoodVisionTests: XCTestCase {
    private static let validJSON = """
    {"foods":[{"name":" Apfel ","grams":150,"kcal":78,"protein":0.4,"carbs":21,"fat":0.3,"confidence":0.9}]}
    """

    func testImageIsResizedRotatedAndEncodedWithoutLocationMetadata() throws {
        let original = try Self.jpeg(width: 2_100, height: 1_050, orientation: 6)
        let originalSource = try XCTUnwrap(CGImageSourceCreateWithData(original as CFData, nil))
        let originalMetadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [String: Any])
        XCTAssertNotNil(originalMetadata[kCGImagePropertyGPSDictionary as String])
        let result = try CoachProviders.prepareImage(original)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source).map { $0 as String }, UTType.jpeg.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.height, 1_568)
        XCTAssertEqual(image.width, 784)
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertNil(metadata[kCGImagePropertyGPSDictionary as String])
        XCTAssertLessThanOrEqual(result.count, 1_000_000)
    }

    func testHighDetailImageMeetsByteLimit() throws {
        let original = try Self.jpeg(width: 1_568, height: 1_568, noisy: true)
        XCTAssertGreaterThan(original.count, 1_000_000)
        let result = try CoachProviders.prepareImage(original)
        XCTAssertLessThanOrEqual(result.count, 1_000_000)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func testUnreadableImageIsRejected() {
        XCTAssertThrowsError(try CoachProviders.prepareImage(Data("kein Bild".utf8))) {
            XCTAssertEqual($0 as? CoachProviders.ReplyError, .invalidImage)
        }
    }

    func testParserReturnsPortionValuesAndAcceptsNoRecognizableFood() throws {
        let guesses = try FoodVision.parse(Self.validJSON)
        XCTAssertEqual(guesses, [
            FoodGuess(name: "Apfel", grams: 150, kcal: 78, protein: 0.4, carbs: 21, fat: 0.3, confidence: 0.9)
        ])
        XCTAssertEqual(try FoodVision.parse(#"{"foods":[]}"#), [])
    }

    func testParserRejectsBrokenJSONAndImplausiblePortions() {
        let item = #"{"name":"Apfel","grams":150,"kcal":78,"protein":0.4,"carbs":21,"fat":0.3,"confidence":0.9}"#
        let invalid = [
            #"{"foods":["#, "{}", "[]",
            Self.validJSON.replacingOccurrences(of: #""fat":0.3,"#, with: ""),
            Self.validJSON.replacingOccurrences(of: "150", with: #""150""#),
            Self.validJSON.replacingOccurrences(of: "150", with: "-1"),
            Self.validJSON.replacingOccurrences(of: "78", with: "1e400"),
            Self.validJSON.replacingOccurrences(of: "78", with: "2000"),
            Self.validJSON.replacingOccurrences(of: "21", with: "200"),
            Self.validJSON.replacingOccurrences(of: "0.9", with: "1.1"),
            Self.validJSON.replacingOccurrences(of: "Apfel", with: " "),
            "{\"foods\":[\(Array(repeating: item, count: 13).joined(separator: ","))]}"
        ]
        for json in invalid {
            XCTAssertThrowsError(try FoodVision.parse(json), json)
        }
    }

    func testChatAttachesFourJPEGsOnlyToCurrentMessageInBothRequests() async throws {
        let original = try Self.jpeg()
        let calls = VisionCalls()
        let answer = try await CoachProviders.reply(
            context: "", history: [
                ChatMessage(role: .user, text: "Privat", localOnly: true),
                ChatMessage(role: .user, text: "Vorige Frage"),
                ChatMessage(role: .coach, text: "Vorige Antwort"),
                ChatMessage(role: .user, text: "Was siehst du?")
            ], images: Array(repeating: original, count: 4),
            anthropicKey: "fixture-a", openAIKey: "fixture-o", maySend: { true }
        ) { request in
            let host = try XCTUnwrap(request.url?.host)
            await calls.record(host)
            let primary = host == "api.anthropic.com"
            let body = try Self.body(of: request)
            let messages = try XCTUnwrap(body[primary ? "messages" : "input"] as? [[String: Any]])
            XCTAssertEqual(messages.dropLast().compactMap { $0["content"] as? String }, ["Vorige Frage", "Vorige Antwort"])
            let last = try XCTUnwrap(messages.last)
            XCTAssertEqual(last["role"] as? String, "user")
            let blocks = try XCTUnwrap(last["content"] as? [[String: Any]])
            XCTAssertEqual(blocks.count, 5)
            XCTAssertEqual(blocks.last?["type"] as? String, primary ? "text" : "input_text")
            XCTAssertEqual(blocks.last?["text"] as? String, "Was siehst du?")
            for block in blocks.dropLast() {
                try Self.assertJPEGBlock(block, primary: primary)
            }
            if primary { throw URLError(.timedOut) }
            XCTAssertEqual(body["store"] as? Bool, false)
            return try Self.response(text: "Ich sehe einen Apfel.", primary: false)
        }
        let hosts = await calls.hosts
        XCTAssertEqual(hosts, ["api.anthropic.com", "api.openai.com"])
        XCTAssertEqual(answer, "Ich sehe einen Apfel.")
    }

    func testChatRejectsTooManyImagesBeforeSending() async throws {
        do {
            _ = try await CoachProviders.reply(
                context: "", history: [ChatMessage(role: .user, text: "Hallo")],
                images: Array(repeating: Data(), count: 5), anthropicKey: "fixture-a",
                openAIKey: nil, maySend: { true }
            ) { _ in
                XCTFail("Zu viele Bilder dürfen nicht gesendet werden.")
                return Data()
            }
            XCTFail("Das Limit für Anhänge wurde ignoriert.")
        } catch {
            XCTAssertEqual(error as? CoachProviders.ReplyError, .tooManyImages)
        }
    }

    func testImageOnlyMessageWorksWithOpenAIAlone() async throws {
        let answer = try await CoachProviders.reply(
            context: "", history: [ChatMessage(role: .user, text: " ")],
            images: [Self.jpeg()], anthropicKey: nil, openAIKey: "fixture-o", maySend: { true }
        ) { request in
            XCTAssertEqual(request.url?.host, "api.openai.com")
            let body = try Self.body(of: request)
            let messages = try XCTUnwrap(body["input"] as? [[String: Any]])
            let blocks = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            try Self.assertJPEGBlock(XCTUnwrap(blocks.first), primary: false)
            let prompt = try XCTUnwrap(blocks.last?["text"] as? String)
            XCTAssertFalse(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            return try Self.response(text: "Ich sehe einen Apfel.", primary: false)
        }
        XCTAssertEqual(answer, "Ich sehe einen Apfel.")
    }

    func testFoodUsesStrictSchemaAndFallsBackWhenPrimaryPortionIsInvalid() async throws {
        let calls = VisionCalls()
        let result = try await FoodVision.estimate(
            photo: Self.jpeg(), anthropicKey: "fixture-a", openAIKey: "fixture-o", maySend: { true }
        ) { request in
            let host = try XCTUnwrap(request.url?.host)
            await calls.record(host)
            let primary = host == "api.anthropic.com"
            let body = try Self.body(of: request)
            let config = try XCTUnwrap(body[primary ? "output_config" : "text"] as? [String: Any])
            let format = try XCTUnwrap(config["format"] as? [String: Any])
            XCTAssertEqual(format["type"] as? String, "json_schema")
            let schema = try XCTUnwrap(format["schema"] as? [String: Any])
            XCTAssertEqual(schema["required"] as? [String], ["foods"])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            let foods = try XCTUnwrap(properties["foods"] as? [String: Any])
            let item = try XCTUnwrap(foods["items"] as? [String: Any])
            XCTAssertEqual(item["required"] as? [String], ["name", "grams", "kcal", "protein", "carbs", "fat", "confidence"])
            XCTAssertEqual(item["additionalProperties"] as? Bool, false)
            let messages = try XCTUnwrap(body[primary ? "messages" : "input"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1)
            let blocks = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
            XCTAssertEqual(blocks.count, 2)
            try Self.assertJPEGBlock(XCTUnwrap(blocks.first), primary: primary)
            if primary {
                XCTAssertEqual(body["model"] as? String, "claude-sonnet-5-5")
                return try Self.response(text: Self.validJSON.replacingOccurrences(of: "150", with: "-1"), primary: true)
            }
            XCTAssertEqual(format["strict"] as? Bool, true)
            XCTAssertEqual(body["store"] as? Bool, false)
            return try Self.response(text: Self.validJSON, primary: false)
        }
        let hosts = await calls.hosts
        XCTAssertEqual(hosts, ["api.anthropic.com", "api.openai.com"])
        XCTAssertEqual(result.first?.name, "Apfel")
    }

    func testFoodRequiresConsentBeforeReadingPhotoOrSending() async {
        do {
            _ = try await FoodVision.estimate(
                photo: Data(), anthropicKey: "fixture-a", openAIKey: "fixture-o", maySend: { false }
            ) { _ in
                XCTFail("Das Foto darf ohne Einwilligung nicht gesendet werden.")
                return Data()
            }
            XCTFail("Die Anfrage hätte abgebrochen werden müssen.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testRevokedConsentKeepsFoodPhotoOutOfFallback() async throws {
        let consent = VisionConsent()
        let calls = VisionCalls()
        do {
            _ = try await FoodVision.estimate(
                photo: Self.jpeg(), anthropicKey: "fixture-a", openAIKey: "fixture-o",
                maySend: { consent.allowed }
            ) { request in
                let host = try XCTUnwrap(request.url?.host)
                await calls.record(host)
                consent.revoke()
                throw URLError(.timedOut)
            }
            XCTFail("Widerruf hätte die Anfrage abbrechen müssen.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let hosts = await calls.hosts
        XCTAssertEqual(hosts, ["api.anthropic.com"])
    }

    private static func body(of request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
    }

    private static func assertJPEGBlock(_ block: [String: Any], primary: Bool) throws {
        let base64: String
        if primary {
            XCTAssertEqual(block["type"] as? String, "image")
            let source = try XCTUnwrap(block["source"] as? [String: Any])
            XCTAssertEqual(source["type"] as? String, "base64")
            XCTAssertEqual(source["media_type"] as? String, "image/jpeg")
            base64 = try XCTUnwrap(source["data"] as? String)
        } else {
            XCTAssertEqual(block["type"] as? String, "input_image")
            let url = try XCTUnwrap(block["image_url"] as? String)
            let prefix = "data:image/jpeg;base64,"
            XCTAssertTrue(url.hasPrefix(prefix))
            base64 = String(url.dropFirst(prefix.count))
        }
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetType(source).map { $0 as String }, UTType.jpeg.identifier)
        XCTAssertLessThanOrEqual(data.count, 1_000_000)
    }

    private static func response(text: String, primary: Bool) throws -> Data {
        if primary {
            return try JSONSerialization.data(withJSONObject: [
                "stop_reason": "end_turn", "content": [["type": "text", "text": text]]
            ])
        }
        return try JSONSerialization.data(withJSONObject: [
            "status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": text]]]]
        ])
    }

    private static func jpeg(width: Int = 48, height: Int = 32, orientation: Int = 1, noisy: Bool = false) throws -> Data {
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo
        ))
        if noisy {
            let pixels = try XCTUnwrap(context.data).bindMemory(to: UInt32.self, capacity: width * height)
            var value: UInt32 = 42
            for index in 0..<(width * height) {
                value = 1_664_525 &* value &+ 1_013_904_223
                pixels[index] = value
            }
        } else {
            context.setFillColor(red: 0.4, green: 0.6, blue: 0.2, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            bytes as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ))
        let properties = [
            kCGImageDestinationLossyCompressionQuality as String: 1.0,
            kCGImagePropertyOrientation as String: orientation,
            kCGImagePropertyGPSDictionary as String: [
                kCGImagePropertyGPSLatitude as String: 12.0, kCGImagePropertyGPSLatitudeRef as String: "N",
                kCGImagePropertyGPSLongitude as String: 13.0, kCGImagePropertyGPSLongitudeRef as String: "E"
            ]
        ] as [String: Any]
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}

private actor VisionCalls {
    private(set) var hosts: [String] = []

    func record(_ host: String) {
        hosts.append(host)
    }
}

private final class VisionConsent: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true

    var allowed: Bool { lock.withLock { value } }

    func revoke() {
        lock.withLock { value = false }
    }
}
