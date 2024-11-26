//
//  TestServer.swift
//  Endpoints
//
//  Created by Zac White on 11/1/24.
//

import Endpoints
import Foundation

struct TestServer: Server {
    enum Environments: String, CaseIterable {
        case local
        case staging
        case production
    }

    var baseUrls: [Environments: URL] {
        return [
            .local: URL(string: "https://local-api.velosmobile.com")!,
            .staging: URL(string: "https://staging-api.velosmobile.com")!,
            .production: URL(string: "https://api.velosmobile.com")!
        ]
    }

    var defaultEnvironment: Environments { .staging }

    static let test = Self()
}
