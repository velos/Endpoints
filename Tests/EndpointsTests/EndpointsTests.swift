//
//  EndpointsTests.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

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

    struct Body: Encodable, JSONEncoderProvider {
        static let jsonEncoder: JSONEncoder = {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            return encoder
        }()

        let property1: Date
        let property2: Int?
    }

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
            path: "user" + "/" + \.name + "/" + \.id
        )

        let request = try test.request(
            in: Environment.test,
            for: SimpleRequest(
                pathComponents: .init(name: "zac", id: "42")
            )
        )

        let responseData = #"{"response1": "testing"}"#.data(using: .utf8)!
        let response = try SimpleRequest.decode(data: responseData)

        XCTAssertEqual(response.response1, "testing")

        print("request: \(request)")
    }

    func testPostEndpointWithEncoder() throws {
        let test: Endpoint<PostRequest1> = Endpoint(
            method: .post,
            path: "path"
        )

        let request = try test.request(
            in: Environment.test,
            for: PostRequest1(
                body: .init(property1: Date(), property2: nil)
            )
        )

        print("request: \(request)")
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

        print("request: \(request)")
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
                    string: "test",
                    date: Date(),
                    double: 2.3,
                    int: 42,
                    boolTrue: true,
                    boolFalse: false,
                    timeZone: .current,
                    optionalString: nil,
                    optionalDate: nil
                ),
                headers: .init(headerValue: "test")
            )
        )

        print("request: \(request)")
    }

    static var allTests = [
        ("testBasicEndpoint", testBasicEndpoint),
        ("testPostEndpointWithEncoder", testPostEndpointWithEncoder),
        ("testPostEndpoint", testPostEndpoint),
        ("testParameterEndpoint", testParameterEndpoint)
    ]
}