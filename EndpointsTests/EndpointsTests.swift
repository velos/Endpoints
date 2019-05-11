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
    typealias Response = Void

    struct PathComponents {
        let name: String
        let id: String
    }

    let pathComponents: PathComponents
}

struct Movie: Decodable {

}

struct UserRequest: RequestType {
    typealias Response = Void
    
    struct PathComponents {
        let userId: String
    }

    struct Parameters {
        let formExample: String
        let queryExample: String
        let optionalExample: String?
    }

    struct Headers {
        let headerValue: String
    }

    let pathComponents: PathComponents
    let parameters: Parameters
    let headers: Headers
}

struct Environment: EnvironmentType {
    let baseUrl: URL

    static let test = Environment(baseUrl: URL(string: "https://velosmobile.com")!)
}

struct SimilarRequest: RequestType {
    typealias Response = [Movie]

    struct PathComponents {
        let movieId: Int
    }

    struct Parameters {
        let apiKey: String
    }

    let pathComponents: PathComponents
    let parameters: Parameters
}

class EndpointsTests: XCTestCase {

    func testMovieEndpoint() throws {
        let similar: Endpoint<SimilarRequest> = Endpoint(
            method: .get,
            path: "movie/\(path: \.movieId)/similar",
            parameters: [
                .query(key: "api_key", value: \SimilarRequest.Parameters.apiKey)
            ]
        )

        let request = try similar.request(
            in: Environment.test,
            for: SimilarRequest(
                pathComponents: .init(movieId: 3),
                parameters: .init(apiKey: "asdf")
            )
        )

        print("request: \(request)")
    }

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

        print("request: \(request)")
    }

    func testParameterEndpoint() throws {
        let test: Endpoint<UserRequest> = Endpoint(
            method: .get,
            path: "hey" + \UserRequest.PathComponents.userId,
            parameters: [
                .form(key: "form", value: \UserRequest.Parameters.formExample),
                .query(key: "pageNumber", value: \UserRequest.Parameters.queryExample),
                .query(key: "optional", value: \UserRequest.Parameters.optionalExample)
            ],
            headers: ["HEADER_TYPE": \UserRequest.Headers.headerValue]
        )

        let request = try test.request(
            in: Environment.test,
            for: UserRequest(
                pathComponents: .init(userId: "3"),
                parameters: .init(formExample: "form", queryExample: "query", optionalExample: nil),
                headers: .init(headerValue: "test")
            )
        )

        print("request: \(request)")
    }
}
