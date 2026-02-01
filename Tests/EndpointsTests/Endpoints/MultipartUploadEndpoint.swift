import Foundation
@testable import Endpoints

struct MultipartUploadEndpoint: Endpoint {
    static let definition: Definition<MultipartUploadEndpoint, TestServer> = Definition(
        method: .post,
        path: "upload"
    )

    typealias Response = Void

    struct Body: Encodable {
        let description: String
        let file: MultipartFormFile
        let tags: [String]
        let metadata: MultipartFormJSON<Metadata>

        struct Metadata: Encodable {
            let owner: String
            let priority: Int
        }
    }

    static var bodyEncoder: MultipartFormEncoder {
        MultipartFormEncoder()
    }

    let body: Body
}
