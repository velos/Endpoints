//
//  EndpointsTests.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@testable import Endpoints

@Suite
struct EndpointsTests {

    @Test
    func basicEndpoint() throws {
        let request = try SimpleEndpoint(
            pathComponents: .init(name: "zac", id: "42")
        ).urlRequest()

        #expect(request.url?.path == "/user/zac/42/profile")

        let responseData = #"{"response1": "testing"}"#.data(using: .utf8)!
        let response = try SimpleEndpoint.responseDecoder.decode(SimpleEndpoint.Response.self, from: responseData)

        #expect(response.response1 == "testing")
    }

    @Test(arguments: [
        ("a b", "a%20b"),
        ("%", "%25"),
        ("café雪", "caf%C3%A9%E9%9B%AA"),
        ("a/b", "a%2Fb"),
        ("a//b", "a%2F%2Fb"),
        ("a?b", "a%3Fb"),
        ("a#b", "a%23b"),
        (".", "%2E"),
        ("..", "%2E%2E"),
        ("a%20b", "a%2520b"),
        ("zac", "zac")
    ])
    func pathParametersAreEncodedOnce(value: String, encoded: String) throws {
        let request = try SimpleEndpoint(
            pathComponents: .init(name: value, id: "42")
        ).urlRequest()

        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: true))
        #expect(url.absoluteString == "https://api.velosmobile.com/user/\(encoded)/42/profile")
        #expect(components.percentEncodedPath == "/user/\(encoded)/42/profile")
    }

    @Test(arguments: [
        (CustomPathEndpoint.Kind.space, "my%20value"),
        (.percent, "100%25"),
        (.query, "a%3Fb"),
        (.fragment, "a%23b"),
        (.encoded, "a%2Fb"),
        (.lowercaseEncoded, "a%2fb"),
        (.invalidEscape, "%25zz"),
        (.incompleteEscape, "%252"),
        (.unicode, "caf%C3%A9%E9%9B%AA")
    ])
    fileprivate func customPathParametersAreNormalized(kind: CustomPathEndpoint.Kind, encoded: String) throws {
        let request = try CustomPathEndpoint(pathComponents: .init(kind: kind)).urlRequest()

        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: true))
        #expect(url.absoluteString == "https://api.velosmobile.com/user/\(encoded)")
        #expect(components.percentEncodedPath == "/user/\(encoded)")
    }

    @Test(arguments: [
        (Optional("a /%?#雪"), Optional(42), "/testing/testPath(Thing='a%20%2F%25%3F%23%E9%9B%AA')/42"),
        (nil, nil, "/testing/testPath(Thing='')")
    ])
    func adjacentOptionalPathParameters(value: String?, integer: Int?, expectedPath: String) throws {
        let request = try AdjacentPathEndpoint(
            pathComponents: .init(value: value, integer: integer)
        ).urlRequest()

        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: true))
        #expect(url.absoluteString == "https://api.velosmobile.com\(expectedPath)")
        #expect(components.percentEncodedPath == expectedPath)
    }

    @Test
    func literalPathEncoding() throws {
        let request = try LiteralPathEndpoint().urlRequest()

        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: true))
        #expect(url.absoluteString == "https://api.velosmobile.com/literal%20%25/caf%C3%A9/%3F%23/%2F/%25zz/%2f")
        #expect(components.percentEncodedPath == "/literal%20%25/caf%C3%A9/%3F%23/%2F/%25zz/%2f")
    }

    @Test
    func basicEndpointWithCustomDecoder() throws {
        let request = try JSONProviderEndpoint(
            body: .init(bodyValueOne: "value"),
            pathComponents: .init(name: "zac", id: "42")
        ).urlRequest()

        #expect(request.url?.path == "/user/zac/42/profile")

        let bodyData = #"{"body_value_one":"value"}"#.data(using: .utf8)!
        #expect(request.httpBody == bodyData)

        let responseData = #"{"response_one": "testing"}"#.data(using: .utf8)!
        let response = try JSONProviderEndpoint.responseDecoder.decode(JSONProviderEndpoint.Response.self, from: responseData)

        #expect(response.responseOne == "testing")
    }

    @Test
    func postEndpointWithEncoder() throws {
        let date = Date()
        let request = try PostEndpoint1(
            body: .init(property1: date, property2: nil)
        ).urlRequest()

        let encodedDate = ISO8601DateFormatter().string(from: date)
        let bodyData = "{\"property1\":\"\(encodedDate)\"}".data(using: .utf8)!
        #expect(request.httpBody == bodyData)
    }

    @Test
    func postEndpoint() throws {
        let request = try PostEndpoint2(
            body: .init(property1: "test", property2: nil)
        ).urlRequest()

        #expect(request.url?.path == "/path")
        #expect(request.httpMethod == "POST")
    }

    @Test
    func multipartBodyEncoding() throws {
        let fileData = Data("hello world".utf8)
        let endpoint = MultipartUploadEndpoint(
            body: .init(
                description: "Test description",
                file: MultipartFormFile(data: fileData, fileName: "greeting.txt", contentType: "text/plain"),
                tags: ["tag1", "tag2"],
                metadata: MultipartFormJSON(
                    MultipartUploadEndpoint.Body.Metadata(owner: "zac", priority: 1)
                )
            )
        )

        let request = try endpoint.urlRequest()

        let contentType = try #require(request.value(forHTTPHeaderField: Header.contentType.name))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))

        let boundaryComponents = contentType.components(separatedBy: "boundary=")
        #expect(boundaryComponents.count == 2)
        let boundary = boundaryComponents[1]

        let bodyData = try #require(request.httpBody)
        let bodyString = try #require(String(data: bodyData, encoding: .utf8))

        #expect(bodyString.contains("Content-Disposition: form-data; name=\"description\""))
        #expect(bodyString.contains("Test description"))
        #expect(bodyString.contains("Content-Disposition: form-data; name=\"tags[0]\""))
        #expect(bodyString.contains("Content-Disposition: form-data; name=\"tags[1]\""))
        #expect(bodyString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"greeting.txt\""))
        #expect(bodyString.contains("Content-Type: text/plain"))
        #expect(bodyString.contains("hello world"))
        #expect(bodyString.contains("Content-Disposition: form-data; name=\"metadata\""))
        #expect(!bodyString.contains("name=\"metadata\"; filename="))
        #expect(bodyString.contains("Content-Type: application/json"))
        #expect(bodyString.contains("\"owner\":\"zac\""))
        #expect(bodyString.contains("\"priority\":1"))
        #expect(bodyString.hasSuffix("--\(boundary)--\r\n"))
    }

    @Test
    func customParameterEncoding() throws {
        let request = try CustomEncodingEndpoint(
            parameterComponents: .init(needsCustomEncoding: "++++")
        ).urlRequest()

        #expect(request.url?.query == "key=%2B%2B%2B%2B")
    }

    @Test
    func parameterEndpoint() throws {
        let request = try UserEndpoint(
            pathComponents: .init(userId: "3"),
            parameterComponents: .init(
                string: "test:of:+thing%asdf",
                date: Date(),
                double: 2.3,
                int: 42,
                boolTrue: true,
                boolFalse: false,
                timeZone: TimeZone(identifier: "America/Los_Angeles")!,
                optionalString: nil,
                optionalDate: nil
            ),
            headerComponents: .init(headerValue: "test")
        ).urlRequest()

        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/hey/3")
        #expect(request.url?.query == "string=test:of:%2Bthing%25asdf&hard_coded_query=true")

        #expect(request.value(forHTTPHeaderField: "HEADER_TYPE") == "test")
        #expect(request.value(forHTTPHeaderField: "HARD_CODED_HEADER") == "test2")
        #expect(request.value(forHTTPHeaderField: "Keep-Alive") == "timeout=5, max=1000")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")

        #expect(request.httpBody != nil)
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""

        #expect(body.contains("string=test%3Aof%3A+thing%25asdf"))
        #expect(!body.contains("optional_string"))
        #expect(
            body.contains("double=2.3&int=42&bool_true=true&bool_false=false&time_zone=America/Los_Angeles&hard_coded_form=true")
        )
    }

    @Test
    func invalidParameter() {
        #expect(throws: EndpointError.self) {
            try InvalidEndpoint(
                parameterComponents: .init(nonEncodable: .value)
            ).urlRequest()
        }
    }

    @Test
    func responseSuccess() throws {
        let successResponse = HTTPURLResponse(url: URL(fileURLWithPath: ""), statusCode: 200, httpVersion: nil, headerFields: nil)
        let jsonData = try JSONEncoder().encode(SimpleEndpoint.Response(response1: "testing"))
        let result = SimpleEndpoint.definition.response(
            data: jsonData,
            response: successResponse,
            error: nil
        )

        guard case .success(let data) = result else {
            Issue.record("Unexpected failure")
            return
        }

        #expect(data == jsonData)
    }

    @Test
    func responseNetworkError() throws {
        let jsonData = try JSONEncoder().encode(SimpleEndpoint.Response(response1: "testing"))
        let result = SimpleEndpoint.definition.response(
            data: jsonData,
            response: nil,
            error: NSError(domain: URLError.errorDomain, code: URLError.Code.notConnectedToInternet.rawValue, userInfo: nil)
        )

        guard case .failure(let taskError) = result, case .internetConnectionOffline = taskError else {
            Issue.record("Unexpected failure")
            return
        }
    }

    @Test
    func responseURLLoadError() throws {
        let jsonData = try JSONEncoder().encode(SimpleEndpoint.Response(response1: "testing"))
        let result = SimpleEndpoint.definition.response(
            data: jsonData,
            response: nil,
            error: NSError(domain: URLError.errorDomain, code: URLError.Code.badServerResponse.rawValue, userInfo: nil)
        )

        guard case .failure(let taskError) = result, case .urlLoadError = taskError else {
            Issue.record("Unexpected failure")
            return
        }
    }

    @Test
    func responseErrorParsing() throws {
        let failureResponse = HTTPURLResponse(url: URL(fileURLWithPath: ""), statusCode: 404, httpVersion: nil, headerFields: nil)
        let errorResponse = SimpleEndpoint.ErrorResponse(errorDescription: "testing")
        let jsonData = try JSONEncoder().encode(errorResponse)
        let result = SimpleEndpoint.definition.response(
            data: jsonData,
            response: failureResponse,
            error: nil
        )

        guard case .failure(let error) = result else {
            Issue.record("Unexpected failure")
            return
        }

        guard case .errorResponse(let response, let decoded) = error else {
            Issue.record("Unexpected error case")
            return
        }

        #expect(response.statusCode == 404)
        #expect(decoded == errorResponse)
    }

    @Test
    @available(iOS 16.0, *)
    func environmentSelectsBaseUrl() throws {
        let endpoint = SimpleEndpoint(
            pathComponents: .init(name: "zac", id: "42")
        )

        #expect(try endpoint.urlRequest(in: .local).url?.host() == "local-api.velosmobile.com")
        #expect(try endpoint.urlRequest(in: .staging).url?.host() == "staging-api.velosmobile.com")
        #expect(try endpoint.urlRequest(in: .production).url?.host() == "api.velosmobile.com")
    }

    @Test
    @available(iOS 16.0, *)
    func environmentDefaultsToTheServersDefault() throws {
        #expect(TestServer.defaultEnvironment == .production)

        let endpoint = SimpleEndpoint(pathComponents: .init(name: "zac", id: "42"))
        #expect(try endpoint.urlRequest().url?.host() == "api.velosmobile.com")
    }

    /// The environment is a per-request value, so requests built for different
    /// environments do not interfere — including from concurrent tasks.
    @Test
    @available(iOS 16.0, *)
    func environmentsDoNotLeakAcrossConcurrentRequests() async throws {
        let hosts = await withTaskGroup(of: String?.self) { group in
            for environment in [TypicalEnvironments.local, .staging, .production, .local, .staging] {
                group.addTask {
                    let endpoint = SimpleEndpoint(pathComponents: .init(name: "zac", id: "42"))
                    return try? endpoint.urlRequest(in: environment).url?.host()
                }
            }
            return await group.reduce(into: [String?]()) { $0.append($1) }
        }

        #expect(hosts.compactMap { $0 }.sorted() == [
            "api.velosmobile.com",
            "local-api.velosmobile.com",
            "local-api.velosmobile.com",
            "staging-api.velosmobile.com",
            "staging-api.velosmobile.com"
        ])
    }
}

private struct AdjacentPathEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = Void

    static let definition: Definition<AdjacentPathEndpoint> = Definition(
        method: .get,
        path: "testing/testPath(Thing='\(path: \.value, includesSlash: false)')\(path: \.integer)"
    )

    struct PathComponents {
        let value: String?
        let integer: Int?
    }

    let pathComponents: PathComponents
}

private struct LiteralPathEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = Void

    static let definition: Definition<LiteralPathEndpoint> = Definition(
        method: .get,
        path: "literal %/café/?#/%2F/%zz/%2f"
    )
}

private struct CustomPathEndpoint: Endpoint {
    typealias Server = TestServer
    typealias Response = Void

    static let definition: Definition<CustomPathEndpoint> = Definition(
        method: .get,
        path: "user/\(path: \.kind)"
    )

    enum Kind: String, PathRepresentable {
        case space = "my value"
        case percent = "100%"
        case query = "a?b"
        case fragment = "a#b"
        case encoded = "a%2Fb"
        case lowercaseEncoded = "a%2fb"
        case invalidEscape = "%zz"
        case incompleteEscape = "%2"
        case unicode = "café雪"

        var pathSafe: String { rawValue }
    }

    struct PathComponents {
        let kind: Kind
    }

    let pathComponents: PathComponents
}
