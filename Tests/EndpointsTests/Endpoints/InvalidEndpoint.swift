//
//  InvalidEndpoint.swift
//  EndpointsTests
//
//  Created by Zac White on 7/7/21.
//  Copyright © 2021 Velos Mobile LLC. All rights reserved.
//

import Endpoints

struct InvalidEndpoint: Endpoint {
    typealias Server = TestServer

    static let definition: Definition<InvalidEndpoint> = Definition(
        method: .get,
        path: "/",
        parameters: [
            .query("path", path: \.nonEncodable)
        ]
    )

    struct ParameterComponents {
        enum MyEnum { case value }
        let nonEncodable: MyEnum
    }

    typealias Response = Void

    let parameterComponents: ParameterComponents
}
