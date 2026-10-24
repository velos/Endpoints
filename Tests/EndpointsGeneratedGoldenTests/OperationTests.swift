import Endpoints
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite struct OperationTests {
    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://example.com/api/records")!, statusCode: status,
            httpVersion: nil, headerFields: ["X-Trace": "trace"])!
    }

    private var recordJSON: Data {
        Data(#"{"id":9223372036854775807,"timestamp":"2024-01-05T15:30:00.123+05:30"}"#.utf8)
    }

    @Test func typedParametersRepeatedKeysAndOperationOverride() throws {
        let uuid = try #require(UUID(uuidString: "12345678-1234-1234-1234-123456789ABC"))
        let request = try Operations.LookupEndpoint(
            pathComponents: .init(recordId: Int64.max, token: uuid, mode: .fast),
            parameterComponents: .init(
                inherited: true, limit: Int64.max, tags: ["a", "b"], modes: [.fast, .slow],
                token: uuid, state: .active, small: Int32.min, counters: [1, 2],
                dates: ["2024-01-05T10:00:00Z"]),
            headerComponents: .init(
                xCount: Int64.max, xSmall: 32, xScore: 1.5, xActive: true, xIndex: 7)
        ).urlRequest()
        #expect(
            request.url?.path
                == "/api/records/9223372036854775807/12345678-1234-1234-1234-123456789ABC/fast")
        let requestURL = try #require(request.url)
        let query = try #require(
            URLComponents(url: requestURL, resolvingAgainstBaseURL: true)?.queryItems)
        #expect(
            query.map(\.name) == [
                "inherited", "limit", "tags", "tags", "modes", "modes", "token", "state", "small",
                "counters", "counters", "dates",
            ])
        #expect(
            query.map(\.value) == [
                "true", "9223372036854775807", "a", "b", "fast", "slow", uuid.uuidString, "active",
                "-2147483648", "1", "2", "2024-01-05T10:00:00Z",
            ])
        #expect(request.url?.query?.contains("tags=a&tags=b") == true)
        #expect(request.value(forHTTPHeaderField: "X-Count") == "9223372036854775807")
        #expect(request.value(forHTTPHeaderField: "X-Small") == "32")
        #expect(request.value(forHTTPHeaderField: "X-Score") == "1.5")
        #expect(request.value(forHTTPHeaderField: "X-Active") == "true")
        #expect(request.value(forHTTPHeaderField: "X-Index") == "7")
        let enums = try Operations.EnumPathEndpoint(
            pathComponents: .init(state: .open, code: .valueMinus1),
            parameterComponents: .init(code: .value1, alias: .slow, modes: [.on, .off])
        ).urlRequest()
        #expect(
            enums.url?.absoluteString
                == "https://example.com/api/enum/open/-1?code=1&alias=slow&modes=on&modes=off")
        let embedded = try Operations.EmbeddedEnumEndpoint(
            pathComponents: .init(state: .readyNow, code: .value1)
        ).urlRequest()
        #expect(embedded.url?.absoluteString == "https://example.com/api/modes/ready-now-1.json")
        let head = try Operations.MetadataEndpoint().urlRequest()
        #expect(head.httpMethod == "HEAD")
        #expect(Operations.MetadataEndpoint.Response.self == Void.self)
    }

    @Test func exactSuccessBeforeRangeAndEmptyUnionCase() throws {
        for status in [200, 201, 204, 299] {
            let decoded = try Operations.LookupEndpoint.responseDecoder.decode(
                Operations.LookupEndpoint.Response.self,
                from: status == 204 ? Data() : recordJSON, response: response(status))
            switch decoded {
            case .ok(let record):
                #expect(status == 200 && record.id == Int64.max)
                #expect(record.timestamp.timeIntervalSince1970 == 1_704_448_800.123)
            case .success(let record):
                #expect((status == 201 || status == 299) && record.id == Int64.max)
            case .noContent: #expect(status == 204)
            }
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Operations.LookupEndpoint.Response.self, from: recordJSON)
        }
        #expect(throws: DecodingError.self) {
            try Operations.LookupEndpoint.responseDecoder.decode(
                Operations.LookupEndpoint.Response.self, from: recordJSON, response: response(302))
        }
        #expect(throws: DecodingError.self) {
            try Operations.LookupEndpoint.responseDecoder.decode(
                Operations.LookupEndpoint.Response.self, from: Data("broken".utf8),
                response: response(200))
        }
        let inline = try Operations.InlineResultEndpoint.responseDecoder.decode(
            Operations.InlineResultEndpoint.Response.self, from: Data(#"{"value":42}"#.utf8),
            response: response(201))
        #expect(inline == .created(.init(value: 42)))
        let accepted = try Operations.InlineResultEndpoint.responseDecoder.decode(
            Operations.InlineResultEndpoint.Response.self, from: Data(), response: response(202))
        #expect(accepted == .accepted)
        let unknown = try Operations.UnknownStatusEndpoint.responseDecoder.decode(
            Operations.UnknownStatusEndpoint.Response.self, from: Data(), response: response(299))
        #expect(unknown == .status299)
        let dateValue = try Operations.ScalarDateEndpoint.responseDecoder.decode(
            Operations.ScalarDateEndpoint.Response.self,
            from: Data(#""2024-01-05T15:30:00.123+05:30""#.utf8), response: response(200))
        guard case .ok(let date) = dateValue else {
            Issue.record("Expected a scalar Date response")
            return
        }
        let seconds = date.timeIntervalSince1970
        #expect(seconds == 1_704_448_800.123)
        let fallback = try Operations.FallbackEndpoint.responseDecoder.decode(
            Operations.Record.self, from: recordJSON, response: response(203))
        #expect(fallback.id == Int64.max)
    }

    @Test func typedErrorsByStatusRangesAndDefault() throws {
        for status in [400, 401, 404, 500, 503, 302, 700] {
            let data = Data(
                (status == 404 ? #"{"resource":"pet"}"# : #"{"message":"failed"}"#).utf8)
            let decoded = try Operations.LookupEndpoint.errorDecoder.decode(
                Operations.LookupEndpoint.ErrorResponse.self, from: data, response: response(status)
            )
            switch decoded {
            case .badRequest(let problem): #expect(status == 400 && problem.message == "failed")
            case .notFound(let problem): #expect(status == 404 && problem.resource == "pet")
            case .clientError(let problem): #expect(status == 401 && problem.message == "failed")
            case .internalServerError(let problem):
                #expect(status == 500 && problem.message == "failed")
            case .serverError(let problem): #expect(status == 503 && problem.message == "failed")
            case .defaultResponse(let problem):
                #expect((status == 302 || status == 700) && problem.message == "failed")
            }
            let result = Operations.LookupEndpoint.definition.response(
                data: data, response: response(status), error: nil)
            guard case .failure(.errorResponse(let httpResponse, let error)) = result else {
                Issue.record("Expected typed error from the runtime for status \(status)")
                continue
            }
            #expect(httpResponse.statusCode == status && error == decoded)
        }
    }

    @Test func bodylessSuccessIgnoresNonJSONBody() throws {
        let decoded = try Operations.InlineResultEndpoint.responseDecoder.decode(
            Operations.InlineResultEndpoint.Response.self,
            from: Data("Accepted".utf8), response: response(202))
        #expect(decoded == .accepted)
    }

    @Test func bodylessErrorIgnoresHTMLBody() throws {
        let decoded = try Operations.DownloadEndpoint.errorDecoder.decode(
            Operations.DownloadEndpoint.ErrorResponse.self,
            from: Data("<html>Not Found</html>".utf8), response: response(404))
        #expect(decoded == .notFound)
    }

    @Test func rawMediaSelectionAndBodylessTypedError() throws {
        let bytes = Data([0, 255, 10, 2])
        let binary = try Operations.DownloadEndpoint.responseDecoder.decode(
            Operations.DownloadEndpoint.Response.self, from: bytes, response: response(206))
        #expect(binary == .partialContent(bytes))
        let json = try Operations.DownloadEndpoint.responseDecoder.decode(
            Operations.DownloadEndpoint.Response.self, from: recordJSON, response: response(200))
        if case .ok(let record) = json {
            #expect(record.id == Int64.max)
        } else {
            Issue.record("Expected application/json to win media selection")
        }
        for status in [401, 503, 700] {
            let rawError = try Operations.DownloadEndpoint.errorDecoder.decode(
                Operations.DownloadEndpoint.ErrorResponse.self, from: bytes,
                response: response(status))
            #expect(rawError == .defaultResponse(bytes))
        }
        let empty = try Operations.DownloadEndpoint.errorDecoder.decode(
            Operations.DownloadEndpoint.ErrorResponse.self, from: Data(), response: response(404))
        #expect(empty == .notFound)
        let problem = try Operations.DownloadEndpoint.errorDecoder.decode(
            Operations.DownloadEndpoint.ErrorResponse.self,
            from: Data(#"{"message":"bad"}"#.utf8), response: response(400))
        #expect(problem == .badRequest(.init(message: "bad")))
    }

    @Test func unmatchedTypedErrorsBecomeParseErrorsAndSingleRawErrorsStayRaw() throws {
        let problem = Data(#"{"message":"failed"}"#.utf8)
        let result = Operations.StrictErrorsEndpoint.definition.response(
            data: problem, response: response(500), error: nil)
        guard
            case .failure(.errorResponseParseError(let httpResponse, let data, let error)) = result
        else {
            Issue.record("Expected a parse error for an unmatched error status")
            return
        }
        #expect(httpResponse.statusCode == 500 && data == problem && error is DecodingError)
        let raw = Data("not JSON\n".utf8)
        let decoded = try Operations.RawErrorEndpoint.errorDecoder.decode(
            Operations.RawErrorEndpoint.ErrorResponse.self, from: raw, response: response(500))
        #expect(decoded == raw)
    }

    @Test func unmatchedHTMLStatusReportsTheStatusCode() {
        let html = Data("<html>Bad Gateway</html>".utf8)
        let result = Operations.StrictErrorsEndpoint.definition.response(
            data: html, response: response(502), error: nil)
        guard
            case .failure(.errorResponseParseError(let httpResponse, let data, let error)) = result,
            case DecodingError.dataCorrupted(let context) = error
        else {
            Issue.record("Expected a status-dispatch decoding error")
            return
        }
        #expect(httpResponse.statusCode == 502)
        #expect(data == html)
        #expect(context.debugDescription == "Unexpected status code 502.")
    }

    @Test func responseHelperDiscards204BodyBeforeUnionDecoding() throws {
        let httpResponse = response(204)
        let data = try Petstore.SearchPetsEndpoint.definition.response(
            data: Data("junk".utf8), response: httpResponse, error: nil
        ).get()
        #expect(data.isEmpty)
        let decoded = try Petstore.SearchPetsEndpoint.responseDecoder.decode(
            Petstore.SearchPetsEndpoint.Response.self, from: data, response: httpResponse)
        #expect(decoded == .noContent)
    }

    @Test func rawSelectionPreservesExactRangeAndDefaultPrecedence() throws {
        let decoder = Operations.SelectionEndpoint.errorDecoder
        let html = Data("<html>Missing</html>".utf8)
        let missing = try decoder.decode(
            Operations.SelectionEndpoint.ErrorResponse.self, from: html, response: response(404))
        #expect(missing == .notFound)
        let json = Data(#"{"message":"failed"}"#.utf8)
        let method = try decoder.decode(
            Operations.SelectionEndpoint.ErrorResponse.self, from: json, response: response(405))
        #expect(method == .methodNotAllowed(.init(message: "failed")))
        let client = try decoder.decode(
            Operations.SelectionEndpoint.ErrorResponse.self, from: json, response: response(450))
        #expect(client == .clientError(.init(message: "failed")))
        let server = try decoder.decode(
            Operations.SelectionEndpoint.ErrorResponse.self, from: html, response: response(501))
        #expect(server == .serverError(html))
        let fallback = try decoder.decode(
            Operations.SelectionEndpoint.ErrorResponse.self, from: html, response: response(700))
        #expect(fallback == .defaultResponse(html))
    }

    @Test func optionalHeadersOmitNilAndDescribePresentValues() throws {
        // Optional header components bug; owned by claude/endpoints-runtime-fixes.
        try withKnownIssue(
            "Optional header components throw invalidHeader; claude/endpoints-runtime-fixes"
        ) {
            let omitted = try Operations.OptionalHeadersEndpoint().urlRequest()
            #expect(omitted.value(forHTTPHeaderField: "X-Name") == nil)
            let present = try Operations.OptionalHeadersEndpoint(
                headerComponents: .init(
                    xName: "name", xCount: 2, xScore: 1.5, xActive: true, xSmall: 3, xLarge: 4)
            ).urlRequest()
            #expect(present.value(forHTTPHeaderField: "X-Name") == "name")
            #expect(present.value(forHTTPHeaderField: "X-Count") == "2")
            #expect(present.value(forHTTPHeaderField: "X-Score") == "1.5")
            #expect(present.value(forHTTPHeaderField: "X-Active") == "true")
            #expect(present.value(forHTTPHeaderField: "X-Small") == "3")
            #expect(present.value(forHTTPHeaderField: "X-Large") == "4")
        } matching: { issue in
            guard let error = issue.error as? EndpointError,
                case .invalidHeader = error
            else { return false }
            return true
        }
    }

    @Test func pathSpecialCharactersEncodeOnce() throws {
        // Path double-encoding bug; owned by claude/endpoints-runtime-fixes.
        let request = try Operations.SpecialPathEndpoint(pathComponents: .init(name: "a b%#?"))
            .urlRequest()
        withKnownIssue("Path values are double encoded; claude/endpoints-runtime-fixes") {
            #expect(request.url?.absoluteString == "https://example.com/api/special/a%20b%25%23%3F")
        }
    }

    @Test func emptyBodyErrorUsesDefaultEmptyCodable() {
        // EmptyCodable empty-body error bug; owned by claude/endpoints-runtime-fixes.
        let result = Operations.EmptyErrorEndpoint.definition.response(
            data: Data(), response: response(400), error: nil)
        let isTypedError: Bool
        if case .failure(.errorResponse) = result {
            isTypedError = true
        } else {
            isTypedError = false
        }
        withKnownIssue("EmptyCodable rejects empty error bodies; claude/endpoints-runtime-fixes") {
            #expect(isTypedError)
        } matching: { _ in
            guard case .failure(.errorResponseParseError(_, let data, let error)) = result else {
                return false
            }
            return data.isEmpty && error is DecodingError
        }
    }
}
