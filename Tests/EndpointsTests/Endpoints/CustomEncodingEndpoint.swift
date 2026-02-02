//
//  CustomEncodingEndpoint.swift
//  EndpointsTests
//
//  Created by Zac White on 9/26/24.
//  Copyright © 2024 Velos Mobile LLC. All rights reserved.
//

import Endpoints
import Foundation

struct CustomEncodingEndpoint: Endpoint {
    typealias Server = TestServer

    static let definition: Definition<CustomEncodingEndpoint> = Definition(
        method: .get,
        path: "/",
        parameters: [
            .query("key", path: \.needsCustomEncoding)
        ]
    )

    struct ParameterComponents {
        let needsCustomEncoding: String
    }

    typealias Response = Void

    let parameterComponents: ParameterComponents

    static var queryEncodingStrategy: QueryEncodingStrategy {
        .custom {
            var characterSet = CharacterSet.urlQueryAllowed
            characterSet.remove(charactersIn: "+")
            return ($0.name, $0.value?.addingPercentEncoding(withAllowedCharacters: characterSet))
        }
    }
}
