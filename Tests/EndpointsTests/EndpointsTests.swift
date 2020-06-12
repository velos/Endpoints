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

struct SimpleRequest: RequestDataType {

    struct Response: Decodable {
        let response1: String
    }

    struct PathComponents {
        let name: String
        let id: String
    }

    let pathComponents: PathComponents
}

struct JSONProviderRequest: RequestDataType {

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


struct UserRequest: RequestDataType {
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

struct PostRequest1: RequestDataType {
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

struct PostRequest2: RequestDataType {
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
        let test: Endpoint<SimpleRequest> = Endpoint(
            method: .get,
            path: "user/\(path: \.name)/\(path: \.id)/profile"
        )

        let request = try test.request(
            in: Environment.test,
            for: SimpleRequest(
                pathComponents: .init(name: "zac", id: "42")
            )
        )

        XCTAssertEqual(request.url?.path, "/user/zac/42/profile")

        let responseData = #"{"response1": "testing"}"#.data(using: .utf8)!
        let response = try SimpleRequest.responseDecoder.decode(SimpleRequest.Response.self, from: responseData)

        XCTAssertEqual(response.response1, "testing")
    }

    func testBasicEndpointWithCustomDecoder() throws {
        let test: Endpoint<JSONProviderRequest> = Endpoint(
            method: .get,
            path: "user/\(path: \.name)/\(path: \.id)/profile"
        )

        let request = try test.request(
            in: Environment.test,
            for: JSONProviderRequest(
                body: .init(bodyValueOne: "value"),
                pathComponents: .init(name: "zac", id: "42")
            )
        )

        XCTAssertEqual(request.url?.path, "/user/zac/42/profile")

        let bodyData = #"{"body_value_one":"value"}"#.data(using: .utf8)!
        XCTAssertEqual(request.httpBody, bodyData)

        let responseData = #"{"response_one": "testing"}"#.data(using: .utf8)!
        let response = try JSONProviderRequest.responseDecoder.decode(JSONProviderRequest.Response.self, from: responseData)

        XCTAssertEqual(response.responseOne, "testing")
    }


    func testPostEndpointWithEncoder() throws {
        let test: Endpoint<PostRequest1> = Endpoint(
            method: .post,
            path: "path"
        )

        let date = Date()

        let request = try test.request(
            in: Environment.test,
            for: PostRequest1(
                body: .init(property1: date, property2: nil)
            )
        )

        let encodedDate = ISO8601DateFormatter().string(from: date)
        let bodyData = "{\"property1\":\"\(encodedDate)\"}".data(using: .utf8)!
        XCTAssertEqual(request.httpBody, bodyData)
    }

    func testPostEndpoint() throws {
        let test: Endpoint<PostRequest2> = Endpoint(
            method: .post,
            path: "path"
        )

        let request = try test.request(
            in: Environment.test,
            for: PostRequest2(
                body: .init(property1: "test", property2: nil)
            )
        )

        XCTAssertEqual(request.url?.path, "/path")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testParameterEndpoint() throws {
        let test: Endpoint<UserRequest> = Endpoint(
            method: .get,
            path: "hey" + \UserRequest.PathComponents.userId,
            parameters: [
                .form(key: "string", value: \UserRequest.Parameters.string),
                .form(key: "date", value: \UserRequest.Parameters.date),
                .form(key: "double", value: \UserRequest.Parameters.double),
                .form(key: "int", value: \UserRequest.Parameters.int),
                .form(key: "bool_true", value: \UserRequest.Parameters.boolTrue),
                .form(key: "bool_false", value: \UserRequest.Parameters.boolFalse),
                .form(key: "time_zone", value: \UserRequest.Parameters.timeZone),
                .form(key: "optional_string", value: \UserRequest.Parameters.optionalString),
                .form(key: "optional_date", value: \UserRequest.Parameters.optionalDate),
                .query(key: "string", value: \UserRequest.Parameters.string),
                .query(key: "optional_string", value: \UserRequest.Parameters.optionalString),
                .query(key: "optional_date", value: \UserRequest.Parameters.optionalDate)
            ],
            headers: ["HEADER_TYPE": \UserRequest.Headers.headerValue]
        )

        let request = try test.request(
            in: Environment.test,
            for: UserRequest(
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
            )
        )

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/hey/3")
        XCTAssertEqual(request.url?.query, "string=test:of:thing%25asdf")
        XCTAssertEqual(request.allHTTPHeaderFields, [
            "HEADER_TYPE": "test",
            "Content-Type": "application/x-www-form-urlencoded"
        ])

        XCTAssertNotNil(request.httpBody)
        XCTAssertTrue(
            String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("string=test%3Aof%3Athing%25asdf") ?? false
        )
        XCTAssertTrue(
            String(data: request.httpBody ?? Data(), encoding: .utf8)?.contains("double=2.3&int=42&bool_true=true&bool_false=false&time_zone=America/Los_Angeles") ?? false
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
