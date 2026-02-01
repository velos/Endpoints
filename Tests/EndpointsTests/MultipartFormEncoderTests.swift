import Foundation
import Testing
@testable import Endpoints

@Suite
struct MultipartFormEncoderTests {

    @Test
    func multipartEncodesMixedValues() throws {
        struct Nested: Encodable {
            let flag: Bool
            let count: Int
        }

        struct Payload: Encodable {
            let title: String
            let nested: Nested
            let list: [String]
            let file: MultipartFormFile
            let metadata: MultipartFormJSON<Metadata>
            let config: MultipartFormJSON<[String: String]>

            struct Metadata: Encodable {
                let author: String
                let version: Int
            }
        }

        let encoder = MultipartFormEncoder(boundary: "Boundary-123")

        let sortedEncoder = JSONEncoder()
        sortedEncoder.outputFormatting = [.sortedKeys]

        let payload = Payload(
            title: "Example",
            nested: .init(flag: true, count: 7),
            list: ["first", "second"],
            file: MultipartFormFile(
                data: Data([0x01, 0x02, 0x03]),
                fileName: "binary.dat",
                contentType: "application/octet-stream"
            ),
            metadata: MultipartFormJSON(
                Payload.Metadata(author: "zac", version: 2)
            ),
            config: MultipartFormJSON(
                ["mode": "debug"],
                encoder: sortedEncoder,
                fileName: "config.json"
            )
        )

        let data = try encoder.encode(payload)
        let body = try #require(String(data: data, encoding: .utf8))

        func part(named name: String) -> String? {
            let marker = "Content-Disposition: form-data; name=\"\(name)\""
            guard let headerRange = body.range(of: marker) else { return nil }
            let partStart = headerRange.lowerBound
            let searchRange = body[headerRange.upperBound...]
            if let nextBoundary = searchRange.range(of: "\r\n--Boundary-123") {
                return String(body[partStart..<nextBoundary.lowerBound])
            }
            return String(body[partStart...])
        }

        #expect(body.contains("--Boundary-123--"), "missing closing boundary")

        let titlePart = try #require(part(named: "title"))
        #expect(titlePart.contains("Example"), "missing title value")

        let nestedFlagPart = try #require(part(named: "nested[flag]"))
        #expect(nestedFlagPart.contains("true"), "missing nested flag value")

        let nestedCountPart = try #require(part(named: "nested[count]"))
        #expect(nestedCountPart.contains("7"), "missing nested count value")

        let list0Part = try #require(part(named: "list[0]"))
        #expect(list0Part.contains("first"), "missing list[0] value")

        let list1Part = try #require(part(named: "list[1]"))
        #expect(list1Part.contains("second"), "missing list[1] value")

        let filePart = try #require(part(named: "file"))
        #expect(filePart.contains("filename=\"binary.dat\""), "missing file filename")
        #expect(filePart.contains("Content-Type: application/octet-stream"), "missing file content type")
        #expect(data.range(of: Data([0x01, 0x02, 0x03])) != nil, "missing file payload")

        let metadataPart = try #require(part(named: "metadata"))
        #expect(!metadataPart.contains("filename="), "metadata unexpectedly has filename")
        #expect(metadataPart.contains("Content-Type: application/json"), "metadata missing content type")
        #expect(metadataPart.contains("\"author\":\"zac\""), "metadata missing author")
        #expect(metadataPart.contains("\"version\":2"), "metadata missing version")

        let configPart = try #require(part(named: "config"))
        #expect(configPart.contains("filename=\"config.json\""), "config missing filename")
        #expect(configPart.contains("Content-Type: application/json"), "config missing content type")
        #expect(configPart.contains("\"mode\":\"debug\""), "config missing payload")
    }

    @Test
    func multipartContentTypeProvidesBoundary() {
        let encoder = MultipartFormEncoder(boundary: "Boundary-XYZ")
        #expect(type(of: encoder).contentType == "multipart/form-data")
        #expect(encoder.contentType == "multipart/form-data; boundary=Boundary-XYZ")
    }
}
