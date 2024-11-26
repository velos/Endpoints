//
//  UserEndpoint.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation
@testable import Endpoints

struct UserEndpoint: Endpoint {
    static var definition: Definition<UserEndpoint, TestServer> = Definition(
        server: .test,
        method: .get,
        path: "hey" + \UserEndpoint.PathComponents.userId,
        parameters: [
            .form("string", path: \UserEndpoint.ParameterComponents.string),
            .form("date", path: \UserEndpoint.ParameterComponents.date),
            .form("double", path: \UserEndpoint.ParameterComponents.double),
            .form("int", path: \UserEndpoint.ParameterComponents.int),
            .form("bool_true", path: \UserEndpoint.ParameterComponents.boolTrue),
            .form("bool_false", path: \UserEndpoint.ParameterComponents.boolFalse),
            .form("time_zone", path: \UserEndpoint.ParameterComponents.timeZone),
            .form("optional_string", path: \UserEndpoint.ParameterComponents.optionalString),
            .form("optional_date", path: \UserEndpoint.ParameterComponents.optionalDate),
            .formValue("hard_coded_form", value: "true"),
            .query("string", path: \UserEndpoint.ParameterComponents.string),
            .query("optional_string", path: \UserEndpoint.ParameterComponents.optionalString),
            .query("optional_date", path: \UserEndpoint.ParameterComponents.optionalDate),
            .queryValue("hard_coded_query", value: "true")
        ],
        headers: [
            "HEADER_TYPE": .field(path: \UserEndpoint.HeaderComponents.headerValue),
            "HARD_CODED_HEADER": .fieldValue(value: "test2"),
            .keepAlive: .fieldValue(value: "timeout=5, max=1000")
        ]
    )

    static var queryEncodingStrategy: QueryEncodingStrategy {
        .custom {
            var characterSet = CharacterSet.urlQueryAllowed
            characterSet.remove(charactersIn: "+")
            return ($0.name, $0.value?.addingPercentEncoding(withAllowedCharacters: characterSet))
        }
    }

    typealias Response = Void

    struct PathComponents {
        let userId: String
    }

    struct ParameterComponents {
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

    struct HeaderComponents {
        let headerValue: String
    }

    let pathComponents: PathComponents
    let parameterComponents: ParameterComponents
    let headerComponents: HeaderComponents
}
