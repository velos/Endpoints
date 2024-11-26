//
//  Environment.swift
//  EndpointsTests
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation
@testable import Endpoints

struct MyServer: Server {
    enum Environments: String, CaseIterable {
        case local
        case staging
        case production
    }
    
    var baseUrls: [Environments: URL] {
        return [
            .local: URL(string: "https://api.velos.com")!,
            .staging: URL(string: "https://api.velos.com")!,
            .production: URL(string: "https://api.velos.com")!
        ]
    }
    
    static var defaultEnvironment: Environments { .production }
}
