//
//  PostEndpoint1.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation
@testable import Endpoints

struct PostEndpoint1: Endpoint {
    static var definition: Definition<PostEndpoint1, TestServer> = Definition(
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
