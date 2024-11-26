//
//  JSONProviderEndpoint.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation
@testable import Endpoints

struct JSONProviderEndpoint: Endpoint {

    static var definition: Definition<JSONProviderEndpoint, TestServer> = Definition(
        server: .test,
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
