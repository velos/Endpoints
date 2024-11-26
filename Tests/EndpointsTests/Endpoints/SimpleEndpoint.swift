//
//  SimpleEndpoint.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation
@testable import Endpoints

struct SimpleEndpoint: Endpoint {
    static var definition: Definition<SimpleEndpoint, TestServer> = Definition(
        method: .get,
        path: "user/\(path: \.name)/\(path: \.id)/profile"
    )

    struct Response: Codable {
        let response1: String
    }

    struct ErrorResponse: Codable, Equatable {
        let errorDescription: String
    }

    struct PathComponents {
        let name: String
        let id: String
    }

    let pathComponents: PathComponents
}
