//
//  EnvironmentType.swift
//  Endpoints
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TypicalEnvironments: String, CaseIterable {
    case local
    case development
    case staging
    case production
}

public protocol ServerDefinition: Sendable {
    associatedtype Environments: Hashable = TypicalEnvironments

    init()
    var baseUrls: [Environments: URL] { get }
    var requestProcessor: (URLRequest) -> URLRequest { get }

    static var defaultEnvironment: Environments { get }
}

public extension ServerDefinition {
    var requestProcessor: (URLRequest) -> URLRequest { return { $0 } }
}

struct ApiServer: ServerDefinition {
    var baseUrls: [Environments: URL] {
        return [
            .local: URL(string: "https://local-api.velos.com")!,
            .staging: URL(string: "https://staging-api.velos.com")!,
            .production: URL(string: "https://api.velos.com")!
        ]
    }

    static var defaultEnvironment: Environments {
        #if DEBUG
        .staging
        #else
        .production
        #endif
    }

    static let api = Self()
}

//@Server(MyEnvironments.self)
//struct ApiServer {
//    var baseUrls: [MyEnvironments: URL] {
//        return [
//            .blueSteel: URL(string: "https://bluesteel-api.velosmobile.com")!,
//            .redStone: URL(string: "https://redstone-api.velosmobile.com")!,
//            .production: URL(string: "https://api.velosmobile.com")!
//        ]
//    }
//}

//@Server
//struct ApiServer {
//    var baseUrls: [Environments: URL] {
//        return [
//            .local: URL(string: "https://local-api.velosmobile.com")!,
//            .staging: URL(string: "https://staging-api.velosmobile.com")!,
//            .production: URL(string: "https://api.velosmobile.com")!
//        ]
//    }
//}

/*
extension ServerEnvironments {
    static var localApi = ServerEnvironment(URL(string: "https://local-api.velosmobile.com")!)
    static var stagingApi = ServerEnvironment(URL(string: "https://staging-api.velosmobile.com")!)
    static var prodApi = ServerEnvironment(URL(string: "https://api.velosmobile.com")!)
}

extension ServerEnvironments {
    static var localAnalytics = ServerEnvironment(URL(string: "https://local-analytics.velosmobile.com")!)
    static var stagingAnalytics = ServerEnvironment(URL(string: "https://staging-analytics.velosmobile.com")!)
    static var prodAnalytics = ServerEnvironment(URL(string: "https://analytics.velosmobile.com")!)
}

extension Servers {
    static var api = Server(localApi, stagingApi, prodApi)
    static var analytics = Server(localAnalytics, stagingAnalytics, prodAnalytics)
}

Servers.setDefault(.api)
Servers.setEnvironment(.local)

@Endpoint(.get, path: "user/\(path: \.name)/\(path: \.id)/profile", server: .analytics)
struct TestEndpoint {
    struct PathComponents: Codable {
        let name: String
        let id: String
    }
    struct Response {
        let id: String
    }
}

import EndpointsTesting

Endpoints.respondTo(TestEndpoint.self, after: .seconds(1), with: { path in
   if path.contains("123") {
       return TestEndpoint.Response(id: "123")
   }
   throw TestErrors.unknownPath
})

Endpoints.respondTo(PostEndpoint.self, with: { path, body in
   if body.id == "123" {
       return .init(id: "123")
   }
   throw TestErrors.unknownBody
})

 */

//@Endpoint(.get, path: "user/\(path: \.name)/\(path: \.id)/profile")
//struct TestEndpoint {
//    struct PathComponents: Codable {
//        let name: String
//        let id: String
//    }
//}

struct TestEndpoint: Endpoint {
    typealias Response = Void
    static let definition: Definition<TestEndpoint, ApiServer> = .init(server: ApiServer.api, method: .get, path: "/")
}

//public protocol EnvironmentType {
//    /// The baseUrl of the Environment
//    var baseUrl: URL { get }
//    /// Processes the built URLRequest right before sending in order to attach any Environment related authentication or data to the outbound request
//    var requestProcessor: (URLRequest) -> URLRequest { get }
//}
//
//public extension EnvironmentType {
//    var requestProcessor: (URLRequest) -> URLRequest { return { $0 } }
//}
