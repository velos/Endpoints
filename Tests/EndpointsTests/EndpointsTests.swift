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
        ).urlRequest(in: Environment.test)

        XCTAssertEqual(request.url?.path, "/user/zac/42/profile")

        let responseData = #"{"response1": "testing"}"#.data(using: .utf8)!
        let response = try SimpleEndpoint.responseDecoder.decode(SimpleEndpoint.Response.self, from: responseData)

        XCTAssertEqual(response.response1, "testing")
    }

    func testBasicEndpointWithCustomDecoder() throws {
        let request = try JSONProviderEndpoint(
            body: .init(bodyValueOne: "value"),
            pathComponents: .init(name: "zac", id: "42")
        ).urlRequest(in: Environment.test)

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
        ).urlRequest(in: Environment.test)

        let encodedDate = ISO8601DateFormatter().string(from: date)
        let bodyData = "{\"property1\":\"\(encodedDate)\"}".data(using: .utf8)!
        XCTAssertEqual(request.httpBody, bodyData)
    }

    func testPostEndpoint() throws {
        let request = try PostEndpoint2(
            body: .init(property1: "test", property2: nil)
        ).urlRequest(in: Environment.test)

        XCTAssertEqual(request.url?.path, "/path")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testParameterEndpoint() throws {

        let request = try UserEndpoint(
            pathComponents: .init(userId: "3"),
            parameterComponents: .init(
                string: "test:of:thing%asdf",
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
        ).urlRequest(in: Environment.test)

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/hey/3")
        XCTAssertEqual(request.url?.query, "string=test:of:thing%25asdf&hard_coded_query=true")

        XCTAssertEqual(request.value(forHTTPHeaderField: "HEADER_TYPE"), "test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "HARD_CODED_HEADER"), "test2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Keep-Alive"), "timeout=5, max=1000")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")

        XCTAssertNotNil(request.httpBody)
        XCTAssertTrue(
            String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("string=test%3Aof%3Athing%25asdf") ?? false
        )
        XCTAssertTrue(
            String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("double=2.3&int=42&bool_true=true&bool_false=false&time_zone=America/Los_Angeles&hard_coded_form=true") ?? false
        )
    }
}
