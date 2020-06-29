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

struct SimpleRequest: RequestType {
    static var endpoint: Endpoint<SimpleRequest> = Endpoint(
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

struct JSONProviderRequest: RequestType {

    static var endpoint: Endpoint<JSONProviderRequest> = Endpoint(
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


struct UserRequest: RequestType {
    static var endpoint: Endpoint<UserRequest> = Endpoint(
        method: .get,
        path: "hey" + \UserRequest.PathComponents.userId,
        parameters: [
            .form("string", path: \UserRequest.Parameters.string),
            .form("date", path: \UserRequest.Parameters.date),
            .form("double", path: \UserRequest.Parameters.double),
            .form("int", path: \UserRequest.Parameters.int),
            .form("bool_true", path: \UserRequest.Parameters.boolTrue),
            .form("bool_false", path: \UserRequest.Parameters.boolFalse),
            .form("time_zone", path: \UserRequest.Parameters.timeZone),
            .form("optional_string", path: \UserRequest.Parameters.optionalString),
            .form("optional_date", path: \UserRequest.Parameters.optionalDate),
            .formValue("hard_coded_form", value: "true"),
            .query("string", path: \UserRequest.Parameters.string),
            .query("optional_string", path: \UserRequest.Parameters.optionalString),
            .query("optional_date", path: \UserRequest.Parameters.optionalDate),
            .queryValue("hard_coded_query", value: "true")
        ],
        headers: [
            "HEADER_TYPE": .field(path: \UserRequest.Headers.headerValue),
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

    struct Headers {
        let headerValue: String
    }

    let pathComponents: PathComponents
    let parameters: Parameters
    let headers: Headers
}

struct PostRequest1: RequestType {
    static var endpoint: Endpoint<PostRequest1> = Endpoint(
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

struct PostRequest2: RequestType {
    static var endpoint: Endpoint<PostRequest2> = Endpoint(
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
        let request = try SimpleRequest(
            pathComponents: .init(name: "zac", id: "42")
        ).urlRequest(in: Environment.test)

        XCTAssertEqual(request.url?.path, "/user/zac/42/profile")

        let responseData = #"{"response1": "testing"}"#.data(using: .utf8)!
        let response = try SimpleRequest.responseDecoder.decode(SimpleRequest.Response.self, from: responseData)

        XCTAssertEqual(response.response1, "testing")
    }

    func testBasicEndpointWithCustomDecoder() throws {
        let request = try JSONProviderRequest(
            body: .init(bodyValueOne: "value"),
            pathComponents: .init(name: "zac", id: "42")
        ).urlRequest(in: Environment.test)

        XCTAssertEqual(request.url?.path, "/user/zac/42/profile")

        let bodyData = #"{"body_value_one":"value"}"#.data(using: .utf8)!
        XCTAssertEqual(request.httpBody, bodyData)

        let responseData = #"{"response_one": "testing"}"#.data(using: .utf8)!
        let response = try JSONProviderRequest.responseDecoder.decode(JSONProviderRequest.Response.self, from: responseData)

        XCTAssertEqual(response.responseOne, "testing")
    }


    func testPostEndpointWithEncoder() throws {
        let date = Date()
        let request = try PostRequest1(
            body: .init(property1: date, property2: nil)
        ).urlRequest(in: Environment.test)

        let encodedDate = ISO8601DateFormatter().string(from: date)
        let bodyData = "{\"property1\":\"\(encodedDate)\"}".data(using: .utf8)!
        XCTAssertEqual(request.httpBody, bodyData)
    }

    func testPostEndpoint() throws {
        let request = try PostRequest2(
            body: .init(property1: "test", property2: nil)
        ).urlRequest(in: Environment.test)

        XCTAssertEqual(request.url?.path, "/path")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testParameterEndpoint() throws {

        let request = try UserRequest(
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
            headers: .init(headerValue: "test")
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
