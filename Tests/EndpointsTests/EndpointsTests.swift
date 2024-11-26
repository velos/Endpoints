//
//  EndpointsTests.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import XCTest
@testable import Endpoints

class EndpointsTests: XCTestCase {

    func testBasicEndpoint() throws {
        let request = try SimpleEndpoint(
            pathComponents: .init(name: "zac", id: "42")
        ).urlRequest()

        XCTAssertEqual(request.url?.path, "/user/zac/42/profile")

        let responseData = #"{"response1": "testing"}"#.data(using: .utf8)!
        let response = try SimpleEndpoint.responseDecoder.decode(SimpleEndpoint.Response.self, from: responseData)

        XCTAssertEqual(response.response1, "testing")
    }

    func testBasicEndpointWithCustomDecoder() throws {
        let request = try JSONProviderEndpoint(
            body: .init(bodyValueOne: "value"),
            pathComponents: .init(name: "zac", id: "42")
        ).urlRequest()

        XCTAssertEqual(request.url?.path, "/user/zac/42/profile")

        let bodyData = #"{"body_value_one":"value"}"#.data(using: .utf8)!
        XCTAssertEqual(request.httpBody, bodyData)

        let responseData = #"{"response_one": "testing"}"#.data(using: .utf8)!
        let response = try JSONProviderEndpoint.responseDecoder.decode(JSONProviderEndpoint.Response.self, from: responseData)

        XCTAssertEqual(response.responseOne, "testing")
    }

    func testPostEndpointWithEncoder() throws {
        let date = Date()
        let request = try PostEndpoint1(
            body: .init(property1: date, property2: nil)
        ).urlRequest()

        let encodedDate = ISO8601DateFormatter().string(from: date)
        let bodyData = "{\"property1\":\"\(encodedDate)\"}".data(using: .utf8)!
        XCTAssertEqual(request.httpBody, bodyData)
    }

    func testPostEndpoint() throws {
        let request = try PostEndpoint2(
            body: .init(property1: "test", property2: nil)
        ).urlRequest()

        XCTAssertEqual(request.url?.path, "/path")
        XCTAssertEqual(request.httpMethod, "POST")
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

    func testCustomParameterEncoding() throws {
        let request = try CustomEncodingEndpoint(
            parameterComponents: .init(needsCustomEncoding: "++++")
        ).urlRequest()

        XCTAssertEqual(request.url?.query, "key=%2B%2B%2B%2B")
    }

    func testParameterEndpoint() throws {

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

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/hey/3")
        XCTAssertEqual(request.url?.query, "string=test:of:%2Bthing%25asdf&hard_coded_query=true")

        XCTAssertEqual(request.value(forHTTPHeaderField: "HEADER_TYPE"), "test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "HARD_CODED_HEADER"), "test2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Keep-Alive"), "timeout=5, max=1000")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")

        XCTAssertNotNil(request.httpBody)
        XCTAssertTrue(
            String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("string=test%3Aof%3A+thing%25asdf") ?? false
        )
        XCTAssertFalse(
            String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("optional_string") ?? true
        )
        XCTAssertTrue(
            String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("double=2.3&int=42&bool_true=true&bool_false=false&time_zone=America/Los_Angeles&hard_coded_form=true") ?? false
        )
    }

    func testInvalidParameter() {
        XCTAssertThrowsError(
            try InvalidEndpoint(
                parameterComponents: .init(nonEncodable: .value)
            ).urlRequest()
        ) { error in
            XCTAssertTrue(error is EndpointError, "error is \(type(of: error)) and not an EndpointError")
        }
    }

    func testResponseSuccess() throws {

        let successResponse = HTTPURLResponse(url: URL(fileURLWithPath: ""), statusCode: 200, httpVersion: nil, headerFields: nil)
        let jsonData = try JSONEncoder().encode(SimpleEndpoint.Response(response1: "testing"))
        let result = SimpleEndpoint.definition.response(
            data: jsonData,
            response: successResponse,
            error: nil
        )

        guard case .success(let data) = result else {
            XCTFail("Unexpected failure")
            return
        }

        XCTAssertEqual(data, jsonData)
    }

    func testResponseNetworkError() throws {

        let jsonData = try JSONEncoder().encode(SimpleEndpoint.Response(response1: "testing"))
        let result = SimpleEndpoint.definition.response(
            data: jsonData,
            response: nil,
            error: NSError(domain: URLError.errorDomain, code: URLError.Code.notConnectedToInternet.rawValue, userInfo: nil)
        )

        guard case .failure(let taskError) = result, case .internetConnectionOffline = taskError else {
            XCTFail("Unexpected failure")
            return
        }
    }

    func testResponseURLLoadError() throws {

        let jsonData = try JSONEncoder().encode(SimpleEndpoint.Response(response1: "testing"))
        let result = SimpleEndpoint.definition.response(
            data: jsonData,
            response: nil,
            error: NSError(domain: URLError.errorDomain, code: URLError.Code.badServerResponse.rawValue, userInfo: nil)
        )

        guard case .failure(let taskError) = result, case .urlLoadError = taskError else {
            XCTFail("Unexpected failure")
            return
        }
    }

    func testResponseErrorParsing() throws {

        let failureResponse = HTTPURLResponse(url: URL(fileURLWithPath: ""), statusCode: 404, httpVersion: nil, headerFields: nil)
        let errorResponse = SimpleEndpoint.ErrorResponse(errorDescription: "testing")
        let jsonData = try JSONEncoder().encode(errorResponse)
        let result = SimpleEndpoint.definition.response(
            data: jsonData,
            response: failureResponse,
            error: nil
        )

        guard case .failure(let error) = result else {
            XCTFail("Unexpected failure")
            return
        }

        guard case .errorResponse(let response, let decoded) = error else {
            XCTFail("Unexpected error case")
            return
        }

        XCTAssertEqual(response.statusCode, 404)
        XCTAssertEqual(decoded, errorResponse)
    }

    @available(iOS 16.0, *)
    func testEnvironmentsChange() throws {
        let existing = TestServer.environment

        let endpoint = SimpleEndpoint(
            pathComponents: .init(name: "zac", id: "42")
        )

        TestServer.environment = .local
        XCTAssertEqual(try endpoint.urlRequest().url?.host(), "local-api.velosmobile.com")

        TestServer.environment = .staging
        XCTAssertEqual(try endpoint.urlRequest().url?.host(), "staging-api.velosmobile.com")

        TestServer.environment = .production
        XCTAssertEqual(try endpoint.urlRequest().url?.host(), "api.velosmobile.com")

        TestServer.environment = existing
    }
}
