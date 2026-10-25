import Endpoints

extension Petstore.Server {
    public static let auth = HeaderKeyAuth(key: "example-api-key", header: "api_key", prefix: nil)
}
