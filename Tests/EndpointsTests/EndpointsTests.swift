//
//  EndpointsTests.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

#if !os(watchOS)
import XCTest
@testable import Endpoints

struct SimpleEndpoint: Endpoint {
    static var definition: Definition<SimpleEndpoint> = Definition(
        method: .get,
        path: "user/\(path: \.name)/\(path: \.id)/profile"
    )

    struct Response: Decodable {
        let response1: String
    }

    struct PathComponents {
        let name: String
        let id: String
    }

    let pathComponents: PathComponents
}

struct JSONProviderEndpoint: Endpoint {

    static var definition: Definition<JSONProviderEndpoint> = Definition(
        method: .get,
        path: "user/\(path: \.name)/\(path: \.id)/profile"
    )

    struct Response: Decodable {
        let responseOne: String
    }

    struct Body: Encodable {
        let bodyValueOne: String
    }

    struct PathComponents {
        let name: String
        let id: String
    }

    let body: Body
    let pathComponents: PathComponents

    static let responseDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static let bodyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}

struct UserEndpoint: Endpoint {
    static var definition: Definition<UserEndpoint> = Definition(
        method: .get,
        path: "hey" + \UserEndpoint.PathComponents.userId,
        parameters: [
            .form("string", path: \UserEndpoint.Parameters.string),
            .form("date", path: \UserEndpoint.Parameters.date),
            .form("double", path: \UserEndpoint.Parameters.double),
            .form("int", path: \UserEndpoint.Parameters.int),
            .form("bool_true", path: \UserEndpoint.Parameters.boolTrue),
            .form("bool_false", path: \UserEndpoint.Parameters.boolFalse),
            .form("time_zone", path: \UserEndpoint.Parameters.timeZone),
            .form("optional_string", path: \UserEndpoint.Parameters.optionalString),
            .form("optional_date", path: \UserEndpoint.Parameters.optionalDate),
            .formValue("hard_coded_form", value: "true"),
            .query("string", path: \UserEndpoint.Parameters.string),
            .query("optional_string", path: \UserEndpoint.Parameters.optionalString),
            .query("optional_date", path: \UserEndpoint.Parameters.optionalDate),
            .queryValue("hard_coded_query", value: "true")
        ],
        headers: [
            "HEADER_TYPE": .field(path: \UserEndpoint.HeaderValues.headerValue),
            "HARD_CODED_HEADER": .fieldValue(value: "test2"),
            .keepAlive: .fieldValue(value: "timeout=5, max=1000")
        ]
    )

    typealias Response = Void
    
    struct PathComponents {
        let userId: String
    }

    struct Parameters {
        let string: String
        let date: Date
        let double: Double
        let int: Int
        let boolTrue: Bool
        let boolFalse: Bool
        let timeZone: TimeZone

        let optionalString: String?
        let optionalDate: String?
    }

    struct HeaderValues {
        let headerValue: String
    }

    let pathComponents: PathComponents
    let parameters: Parameters
    let headerValues: HeaderValues
}

struct PostEndpoint1: Endpoint {
    static var definition: Definition<PostEndpoint1> = Definition(
        method: .post,
        path: "path"
    )

    typealias Response = Void

    struct Body: Encodable {
        let property1: Date
        let property2: Int?
    }

    static let bodyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    let body: Body
}

struct PostEndpoint2: Endpoint {
    static var definition: Definition<PostEndpoint2> = Definition(
        method: .post,
        path: "path"
    )

    typealias Response = Void

    struct Body: Encodable {
        let property1: String
        let property2: Int?
    }

    let body: Body
}

struct Environment: EnvironmentType {
    let baseUrl: URL

    static let test = Environment(baseUrl: URL(string: "https://velosmobile.com")!)
}

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
            parameters: .init(
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
            headerValues: .init(headerValue: "test")
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

    static var allTests = [
        ("testBasicEndpoint", testBasicEndpoint),
        ("testBasicEndpointWithCustomDecoder", testBasicEndpointWithCustomDecoder),
        ("testPostEndpointWithEncoder", testPostEndpointWithEncoder),
        ("testPostEndpoint", testPostEndpoint),
        ("testParameterEndpoint", testParameterEndpoint)
    ]
}
#endif
