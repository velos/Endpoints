import Endpoints
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private struct ResponseMetadata: Decodable, Equatable, Sendable {
    let status: Int?
    let marker: String?
    let configured: String?

    init(from decoder: any Decoder) throws {
        status = decoder.userInfo[.httpStatusCode] as? Int
        marker =
            (decoder.userInfo[.httpHeaders] as? [String: String])?.first {
                $0.key.lowercased() == "x-marker"
            }?.value
        configured = decoder.userInfo[Self.configurationKey] as? String
    }

    static let configurationKey = CodingUserInfoKey(rawValue: "test.configuration")!
}

private struct LegacyDecoder: DecoderType {
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

private struct MetadataEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = ResponseMetadata
    typealias ErrorResponse = ResponseMetadata
    static let definition = Definition<Self>(method: .get, path: "hooks/metadata")
    static var responseDecoder: HTTPResponseJSONDecoder { .init() }
    static var errorDecoder: HTTPResponseJSONDecoder { .init() }
}

private enum ParameterChoice: String, ParameterRepresentable, PathRepresentable {
    case ready
}

private struct DualParameter: ParameterRepresentable, MultiValueParameterRepresentable, Sendable {
    var omit = false
    var parameterValue: String? { omit ? nil : "scalar" }
    var parameterValues: [String] { ["multi", "ignored"] }
}

private struct RepeatedEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = Void
    struct ParameterComponents: Sendable {
        let values: [String?]?
        let dual: DualParameter
        init(values: [String?]?, omitScalar: Bool = false) {
            self.values = values
            self.dual = DualParameter(omit: omitScalar)
        }
    }
    static let definition = Definition<Self>(
        method: .post, path: "hooks/repeated",
        parameters: [
            .query("tag", path: \.values), .form("tag", path: \.values),
            .query("dual", path: \.dual), .form("dual", path: \.dual),
            .queryValue("fixed", value: "unchanged"), .formValue("fixed", value: "unchanged"),
        ])
    let parameterComponents: ParameterComponents
}

/// Covers decoder metadata, repeated parameters, and scalar representation contracts.
@Suite struct RuntimeHooksTests {
    static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://api.velosmobile.com/hooks/metadata")!,
            statusCode: status, httpVersion: nil, headerFields: ["X-Marker": "received"])!
    }

    @Test func legacyDecodersIgnoreTheHTTPResponseByDefault() throws {
        let decoder: any DecoderType = LegacyDecoder()
        let value = try decoder.decode(
            Int.self, from: Data("42".utf8), response: Self.response(200))
        #expect(value == 42)
    }

    @Test func configurationRunsOnAFreshDecoderForEveryCall() throws {
        let decoder = HTTPResponseJSONDecoder { decoder in
            #expect(decoder.userInfo[ResponseMetadata.configurationKey] == nil)
            decoder.userInfo[ResponseMetadata.configurationKey] = "configured"
        }
        for _ in 0..<2 {
            let value = try decoder.decode(ResponseMetadata.self, from: Data("{}".utf8))
            #expect(value.configured == "configured")
        }
    }

    @Test func responseMetadataOverridesConfiguredUserInfo() throws {
        let decoder = HTTPResponseJSONDecoder { decoder in
            decoder.userInfo[.httpStatusCode] = -1
            decoder.userInfo[.httpHeaders] = ["X-Marker": "configured"]
        }
        let value = try decoder.decode(
            ResponseMetadata.self, from: Data("{}".utf8), response: Self.response(200))
        #expect(value.status == 200)
        #expect(value.marker == "received")
    }

    @Test func decodingWithoutAResponseDoesNotAddMetadataOrSelectRawData() throws {
        let decoder = HTTPResponseJSONDecoder(isRawDataStatus: { _ in
            Issue.record("Raw status selection requires an HTTP response")
            return true
        })
        let value = try decoder.decode(ResponseMetadata.self, from: Data("{}".utf8))
        #expect(value.status == nil)
        #expect(value.marker == nil)
    }

    @Test func emptyJSONBodyWithoutResponseDecodesAsNull() throws {
        let value = try HTTPResponseJSONDecoder().decode(String?.self, from: Data())
        #expect(value == nil)
    }

    @Test func emptyJSONBodyWithResponseDecodesAsNull() throws {
        let value = try HTTPResponseJSONDecoder().decode(
            String?.self, from: Data(), response: Self.response(204))
        #expect(value == nil)
    }

    @Test func invalidJSONThrowsADecodingError() {
        #expect(throws: DecodingError.self) {
            try HTTPResponseJSONDecoder().decode(Int.self, from: Data("invalid JSON".utf8))
        }
    }

    @Test(arguments: [false, true]) func rawStatusesForceBase64AfterConfiguration(custom: Bool)
        throws
    {
        let decoder = HTTPResponseJSONDecoder(isRawDataStatus: { $0 == 206 }) { decoder in
            if custom {
                decoder.dataDecodingStrategy = .custom { _ in Data("configured".utf8) }
            } else {
                decoder.dataDecodingStrategy = .deferredToData
            }
        }
        let bytes = Data([0, 255, 1])
        let raw = try decoder.decode(Data.self, from: bytes, response: Self.response(206))
        #expect(raw == bytes)
        let empty = try decoder.decode(Data.self, from: Data(), response: Self.response(206))
        #expect(empty.isEmpty)
        let json = try decoder.decode(
            Data.self, from: Data("[4,5]".utf8), response: Self.response(200))
        #expect(json == (custom ? Data("configured".utf8) : Data([4, 5])))
    }

    @Test func publicResponseHelperReturnsTheSuccessfulBody() throws {
        let data = Data("{}".utf8)
        let success = try MetadataEndpoint.definition.response(
            data: data, response: Self.response(200), error: nil
        ).get()
        #expect(success == data)
    }

    @Test func errorDecoderReceivesResponseMetadata() {
        let result = MetadataEndpoint.definition.response(
            data: Data(), response: Self.response(409), error: nil)
        guard case .failure(.errorResponse(let response, let value)) = result else {
            Issue.record("Expected response-aware typed error")
            return
        }
        #expect(response.statusCode == 409)
        #expect(value.status == 409)
        #expect(value.marker == "received")
    }

    @Test(arguments: [nil, [], [nil], ["a", "b"], [nil, "a", nil, "b", nil]] as [[String?]?])
    func repeatedQueryAndFormSemantics(values: [String?]?) throws {
        let request = try RepeatedEndpoint(parameterComponents: .init(values: values)).urlRequest()
        let expected =
            (values?.compactMap { $0 }.map { "tag=" + $0 } ?? [])
            + ["dual=scalar", "fixed=unchanged"]
        let wire = expected.joined(separator: "&")
        #expect(request.url?.query == wire)
        #expect(request.httpBody == Data(wire.utf8))
        #expect(
            request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded"
        )
    }

    @Test func nilScalarDoesNotFallThroughToMultiValueRepresentation() throws {
        let request = try RepeatedEndpoint(
            parameterComponents: .init(values: nil, omitScalar: true)
        ).urlRequest()
        #expect(request.url?.query == "fixed=unchanged")
        #expect(request.httpBody == Data("fixed=unchanged".utf8))
    }

    @Test func int32UsesDecimalStrings() {
        #expect(Int32.min.parameterValue == "-2147483648")
        #expect(Int32.max.pathSafe == "2147483647")
    }

    @Test func int64UsesDecimalStrings() {
        #expect(Int64.min.pathSafe == "-9223372036854775808")
        #expect(Int64.max.parameterValue == "9223372036854775807")
    }

    @Test func uuidUsesItsUUIDString() throws {
        let uuid = try #require(UUID(uuidString: "12345678-1234-1234-1234-123456789ABC"))
        #expect(uuid.parameterValue == "12345678-1234-1234-1234-123456789ABC")
        #expect(uuid.pathSafe == "12345678-1234-1234-1234-123456789ABC")
    }

    @Test func rawRepresentableDefaultsUseTheRawValue() {
        #expect(ParameterChoice.ready.parameterValue == "ready")
        #expect(ParameterChoice.ready.pathSafe == "ready")
    }
}

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
/// Exercises metadata delivery through real async, callback, and Combine request paths.
@Suite("Response-aware transports", .serialized) struct ResponseAwareTransportTests {
    private func session(status: Int) -> URLSession {
        TestURLProtocol.register(path: "/hooks/metadata") { _ in
            (RuntimeHooksTests.response(status), Data())
        }
        return TestURLProtocol.makeSession()
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test func asyncSuccessReceivesResponseMetadata() async throws {
        let session = session(status: 204)
        defer {
            session.invalidateAndCancel()
            TestURLProtocol.unregister(path: "/hooks/metadata")
        }
        let value = try await session.response(with: MetadataEndpoint())
        #expect(value.status == 204)
        #expect(value.marker == "received")
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test func asyncTypedErrorReceivesResponseMetadata() async {
        let session = session(status: 409)
        defer {
            session.invalidateAndCancel()
            TestURLProtocol.unregister(path: "/hooks/metadata")
        }
        do {
            _ = try await session.response(with: MetadataEndpoint())
            Issue.record("Expected a typed error for status 409")
        } catch {
            guard case .errorResponse(let response, let value) = error else {
                Issue.record("Unexpected async error: \(error)")
                return
            }
            #expect(response.statusCode == 409)
            #expect(value.status == 409)
            #expect(value.marker == "received")
        }
    }

    private func callbackResult(
        from session: URLSession
    ) async throws -> Result<ResponseMetadata, MetadataEndpoint.TaskError> {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let task = try session.endpointTask(with: MetadataEndpoint()) { result in
                    continuation.resume(returning: result)
                }
                task.resume()
            } catch { continuation.resume(throwing: error) }
        }
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test func callbackSuccessReceivesResponseMetadata() async throws {
        let session = session(status: 204)
        defer {
            session.invalidateAndCancel()
            TestURLProtocol.unregister(path: "/hooks/metadata")
        }
        let result = try await callbackResult(from: session)
        guard case .success(let value) = result else {
            Issue.record("Expected callback success")
            return
        }
        #expect(value.status == 204)
        #expect(value.marker == "received")
    }

    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test func callbackTypedErrorReceivesResponseMetadata() async throws {
        let session = session(status: 409)
        defer {
            session.invalidateAndCancel()
            TestURLProtocol.unregister(path: "/hooks/metadata")
        }
        let result = try await callbackResult(from: session)
        guard case .failure(.errorResponse(let response, let value)) = result else {
            Issue.record("Expected callback typed error")
            return
        }
        #expect(response.statusCode == 409)
        #expect(value.status == 409)
        #expect(value.marker == "received")
    }

}
#endif

#if canImport(Combine) && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
import Combine

extension ResponseAwareTransportTests {
    @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 12, *)
    @Test func combinePassesResponseMetadata() async throws {
        TestURLProtocol.register(path: "/hooks/metadata") { _ in
            (RuntimeHooksTests.response(204), Data())
        }
        defer { TestURLProtocol.unregister(path: "/hooks/metadata") }
        let session = TestURLProtocol.makeSession()
        defer { session.invalidateAndCancel() }
        var statuses: [Int?] = []
        for try await value in session.endpointPublisher(with: MetadataEndpoint()).values {
            statuses.append(value.status)
            #expect(value.marker == "received")
        }
        #expect(statuses == [204])
    }
}
#endif
