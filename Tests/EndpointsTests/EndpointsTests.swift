//
//  EndpointsTests.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation
import Testing
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

    func testMultipartBodyEncoding() throws {
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

        let request = try endpoint.urlRequest(in: Environment.test)

        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: Header.contentType.name))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))

        let boundaryComponents = contentType.components(separatedBy: "boundary=")
        XCTAssertEqual(boundaryComponents.count, 2)
        let boundary = boundaryComponents[1]

        let bodyData = try XCTUnwrap(request.httpBody)
        let bodyString = try XCTUnwrap(String(data: bodyData, encoding: .utf8))

        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"description\""))
        XCTAssertTrue(bodyString.contains("Test description"))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"tags[0]\""))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"tags[1]\""))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"greeting.txt\""))
        XCTAssertTrue(bodyString.contains("Content-Type: text/plain"))
        XCTAssertTrue(bodyString.contains("hello world"))
        XCTAssertTrue(bodyString.contains("Content-Disposition: form-data; name=\"metadata\""))
        XCTAssertFalse(bodyString.contains("name=\"metadata\"; filename="))
        XCTAssertTrue(bodyString.contains("Content-Type: application/json"))
        XCTAssertTrue(bodyString.contains("\"owner\":\"zac\""))
        XCTAssertTrue(bodyString.contains("\"priority\":1"))
        XCTAssertTrue(bodyString.hasSuffix("--\(boundary)--\r\n"))
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
    func environmentsChange() throws {
        let existing = TestServer.environment

        let endpoint = SimpleEndpoint(
            pathComponents: .init(name: "zac", id: "42")
        )

        TestServer.environment = .local
        #expect(try endpoint.urlRequest().url?.host() == "local-api.velosmobile.com")

        TestServer.environment = .staging
        #expect(try endpoint.urlRequest().url?.host() == "staging-api.velosmobile.com")

        TestServer.environment = .production
        #expect(try endpoint.urlRequest().url?.host() == "api.velosmobile.com")

        TestServer.environment = existing
    }
}
