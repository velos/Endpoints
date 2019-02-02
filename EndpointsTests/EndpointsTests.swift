//
//  EndpointsTests.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import XCTest
@testable import Endpoints

struct UserRequest: RequestType {
    typealias Response = Empty
    typealias Body = Empty

    let pathComponents: PathComponent
    let parameters: Parameters

    init(response: Empty = Empty(), body: Empty = Empty(), pathComponents: UserRequest.PathComponent, parameters: Parameters) {
        self.pathComponents = pathComponents
        self.parameters = parameters
    }

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

    static let test = Environment(baseUrl: URL(string: "https://positron.io")!)
}

class EndpointsTests: XCTestCase {

    func testBasicEndpoint() throws {
        let test: Endpoint<UserRequest> = Endpoint(
            method: .get,
            path: "hey" + \.userId,
            parameters: [
                .form(key: "form", value: \UserRequest.Parameters.formExample),
                .query(key: "query", value: \UserRequest.Parameters.queryExample)
            ]
        )

        let request = try test.request(
            with: UserRequest(
                pathComponents: .init(userId: "3"),
                parameters: .init(formExample: "formValue", queryExample: "queryValue")
            ), in: Environment.test
        )

        print("request: \(request)")
    }
}
