//
//  PostEndpoint2.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation
@testable import Endpoints

struct PostEndpoint2: Endpoint {
    static var definition: Definition<PostEndpoint2> = Definition(
        method: .post,
        path: "path"
    )

    typealias Response = Void

    struct Body: Encodable {
        let property1: String
        let property2: Int?
    }

    let body: Body
}
