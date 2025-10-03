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
        }

        let encoder = MultipartFormEncoder(boundary: "Boundary-123")

        let payload = Payload(
            title: "Example",
            nested: .init(flag: true, count: 7),
            list: ["first", "second"],
            file: MultipartFormFile(
                data: Data([0x01, 0x02, 0x03]),
                fileName: "binary.dat",
                contentType: "application/octet-stream"
            )
        )

        let data = try encoder.encode(payload)

        var expected = Data()
        func append(_ string: String) {
            expected.append(contentsOf: string.utf8)
        }
        func append(_ bytes: [UInt8]) {
            expected.append(contentsOf: bytes)
        }

        append("--Boundary-123\r\n")
        append("Content-Disposition: form-data; name=\"title\"\r\n\r\n")
        append("Example\r\n")

        append("--Boundary-123\r\n")
        append("Content-Disposition: form-data; name=\"nested[flag]\"\r\n\r\n")
        append("true\r\n")

        append("--Boundary-123\r\n")
        append("Content-Disposition: form-data; name=\"nested[count]\"\r\n\r\n")
        append("7\r\n")

        append("--Boundary-123\r\n")
        append("Content-Disposition: form-data; name=\"list[0]\"\r\n\r\n")
        append("first\r\n")

        append("--Boundary-123\r\n")
        append("Content-Disposition: form-data; name=\"list[1]\"\r\n\r\n")
        append("second\r\n")

        append("--Boundary-123\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"binary.dat\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        append([0x01, 0x02, 0x03])
        append("\r\n")

        append("--Boundary-123--\r\n")

        XCTAssertEqual(data, expected)
    }

    func testContentTypeProvidesBoundary() {
        let encoder = MultipartFormEncoder(boundary: "Boundary-XYZ")
        XCTAssertEqual(type(of: encoder).contentType, "multipart/form-data")
        XCTAssertEqual(encoder.contentType, "multipart/form-data; boundary=Boundary-XYZ")
    }
}
