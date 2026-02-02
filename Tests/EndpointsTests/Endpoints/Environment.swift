//
//  Environment.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation
@testable import Endpoints

struct MyServer: ServerDefinition {
    var baseUrls: [Environments: URL] {
        return [
            .local: URL(string: "https://api.velos.me")!,
            .staging: URL(string: "https://api.velos.me")!,
            .production: URL(string: "https://api.velos.me")!
        ]
    }

    static var defaultEnvironment: Environments { .production }
}
