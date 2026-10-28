import Foundation
import Endpoints

public struct StatusEndpoint: Endpoint {
    public typealias Response = String
    public static let definition: Definition<StatusEndpoint> = Definition(
        server: GenericServer(baseUrl: URL(string: "https://status.example.com/")!),
        method: .get,
        path: "status"
    )
    public init() {}
}
