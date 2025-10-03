import Foundation
@testable import Endpoints

struct MultipartUploadEndpoint: Endpoint {
    static let definition: Definition<MultipartUploadEndpoint> = Definition(
        method: .post,
        path: "upload"
    )

    typealias Response = Void

    struct Body: Encodable {
        let description: String
        let file: MultipartFormFile
        let tags: [String]
    }

    static var bodyEncoder: MultipartFormEncoder {
        MultipartFormEncoder()
    }

    let body: Body
}
