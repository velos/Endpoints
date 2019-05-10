//
//  EndpointsTests.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import XCTest
@testable import Endpoints

struct SimpleRequest: RequestType {
//    typealias Response = Empty
    typealias Body = Empty
    typealias Parameters = Empty

    struct PathComponent {
        let name: String
        let id: String
    }
}

struct UserRequest: RequestType {
    typealias Response = Empty
    typealias Body = Empty

    struct PathComponent {
        let userId: String
    }

    struct Parameters {
        let formExample: String
        let queryExample: String
    }
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
            pathComponents: .init(name: "zac", id: "5")
        )

        print("request: \(request)")
    }

    func testParameterEndpoint() throws {
        let test: Endpoint<UserRequest> = Endpoint(
            method: .get,
            path: "hey" + \.userId,
            parameters: [
                .form(key: "form", value: \UserRequest.Parameters.formExample),
                .query(key: "pageNumber", value: \UserRequest.Parameters.queryExample)
            ]
        )

        let request = try test.request(
            in: Environment.test,
            pathComponents: .init(userId: "3"),
            parameters: .init(formExample: "form", queryExample: "query")
        )

        print("request: \(request)")
    }
}
