import XCTest
@testable import Endpoints

final class MultipartFormEncoderTests: XCTestCase {

    func testEncodesMixedValues() throws {
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
        let body = try XCTUnwrap(String(data: data, encoding: .utf8))

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

        XCTAssertTrue(body.contains("--Boundary-123--"), "missing closing boundary")

        let titlePart = try XCTUnwrap(part(named: "title"))
        XCTAssertTrue(titlePart.contains("Example"), "missing title value")

        let nestedFlagPart = try XCTUnwrap(part(named: "nested[flag]"))
        XCTAssertTrue(nestedFlagPart.contains("true"), "missing nested flag value")

        let nestedCountPart = try XCTUnwrap(part(named: "nested[count]"))
        XCTAssertTrue(nestedCountPart.contains("7"), "missing nested count value")

        let list0Part = try XCTUnwrap(part(named: "list[0]"))
        XCTAssertTrue(list0Part.contains("first"), "missing list[0] value")

        let list1Part = try XCTUnwrap(part(named: "list[1]"))
        XCTAssertTrue(list1Part.contains("second"), "missing list[1] value")

        let filePart = try XCTUnwrap(part(named: "file"))
        XCTAssertTrue(filePart.contains("filename=\"binary.dat\""), "missing file filename")
        XCTAssertTrue(filePart.contains("Content-Type: application/octet-stream"), "missing file content type")
        XCTAssertNotNil(data.range(of: Data([0x01, 0x02, 0x03])), "missing file payload")

        let metadataPart = try XCTUnwrap(part(named: "metadata"))
        XCTAssertFalse(metadataPart.contains("filename="), "metadata unexpectedly has filename")
        XCTAssertTrue(metadataPart.contains("Content-Type: application/json"), "metadata missing content type")
        XCTAssertTrue(metadataPart.contains("\"author\":\"zac\""), "metadata missing author")
        XCTAssertTrue(metadataPart.contains("\"version\":2"), "metadata missing version")

        let configPart = try XCTUnwrap(part(named: "config"))
        XCTAssertTrue(configPart.contains("filename=\"config.json\""), "config missing filename")
        XCTAssertTrue(configPart.contains("Content-Type: application/json"), "config missing content type")
        XCTAssertTrue(configPart.contains("\"mode\":\"debug\""), "config missing payload")
    }

    func testContentTypeProvidesBoundary() {
        let encoder = MultipartFormEncoder(boundary: "Boundary-XYZ")
        XCTAssertEqual(type(of: encoder).contentType, "multipart/form-data")
        XCTAssertEqual(encoder.contentType, "multipart/form-data; boundary=Boundary-XYZ")
    }
}
