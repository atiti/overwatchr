import XCTest
@testable import OverwatchrCore

final class AzureSpeechTranscriptionTests: XCTestCase {
    func testBuildsRegionalShortAudioURL() throws {
        let configuration = AzureSpeechConfiguration(
            region: "eastus",
            endpoint: nil,
            language: "en-US"
        )

        let url = try AzureSpeechShortAudioRequest.url(for: configuration)

        XCTAssertEqual(
            url.absoluteString,
            "https://eastus.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=en-US&format=detailed"
        )
    }

    func testBuildsEndpointBasedShortAudioURL() throws {
        let configuration = AzureSpeechConfiguration(
            region: "",
            endpoint: "https://custom.example.com/",
            language: "hu-HU"
        )

        let url = try AzureSpeechShortAudioRequest.url(for: configuration)

        XCTAssertEqual(
            url.absoluteString,
            "https://custom.example.com/speech/recognition/conversation/cognitiveservices/v1?language=hu-HU&format=detailed"
        )
    }

    func testNormalizesAzurePortalCognitiveEndpointToSpeechRecognitionHost() throws {
        let configuration = AzureSpeechConfiguration(
            region: "westeurope",
            endpoint: "https://westeurope.api.cognitive.microsoft.com/",
            language: "en-US"
        )

        let url = try AzureSpeechShortAudioRequest.url(for: configuration)

        XCTAssertEqual(
            url.absoluteString,
            "https://westeurope.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1?language=en-US&format=detailed"
        )
    }

    func testSplitsLanguageCandidates() {
        let configuration = AzureSpeechConfiguration(
            region: "westeurope",
            endpoint: nil,
            language: "en-US, hu-HU"
        )

        XCTAssertEqual(configuration.languageCandidates, ["en-US", "hu-HU"])
    }

    func testLanguageCandidatesDefaultToEnglishWhenBlank() {
        let configuration = AzureSpeechConfiguration(
            region: "westeurope",
            endpoint: nil,
            language: " "
        )

        XCTAssertEqual(configuration.languageCandidates, ["en-US"])
    }

    func testParsesDisplayTextResponse() throws {
        let data = Data("""
        {
          "RecognitionStatus": "Success",
          "DisplayText": "Looks good.",
          "Offset": 6600000,
          "Duration": 32100000
        }
        """.utf8)

        let result = try AzureSpeechShortAudioResponse.parse(data)

        XCTAssertEqual(result.text, "Looks good.")
        XCTAssertEqual(result.provider, "azureSpeech")
    }

    func testParsesBestDetailedResponseWhenDisplayTextMissing() throws {
        let data = Data("""
        {
          "RecognitionStatus": "Success",
          "NBest": [
            { "Display": "Fallback text.", "Confidence": 0.91 }
          ]
        }
        """.utf8)

        let result = try AzureSpeechShortAudioResponse.parse(data)

        XCTAssertEqual(result.text, "Fallback text.")
        XCTAssertEqual(result.confidence, 0.91)
    }

    func testThrowsForUnsuccessfulRecognition() {
        let data = Data("""
        {
          "RecognitionStatus": "NoMatch",
          "DisplayText": ""
        }
        """.utf8)

        XCTAssertThrowsError(try AzureSpeechShortAudioResponse.parse(data)) { error in
            XCTAssertEqual(error as? AzureSpeechTranscriptionError, .recognitionFailed("NoMatch"))
        }
    }
}
