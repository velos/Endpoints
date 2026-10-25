import Endpoints
import Foundation
import Testing

// TODO(3N-2): configure accessLevel: .public in Petstore.endpoints.swift and restore a public API import.
@testable import PetstoreAPI

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Test func authenticationWitnessAndRequest() throws {
    #expect(Petstore.Server.Auth.self == HeaderKeyAuth.self)
    #expect(Petstore.GetPetEndpoint.Auth.self == HeaderKeyAuth.self)
    #expect(Petstore.GetLogoEndpoint.Auth.self == NoAuth.self)
    let endpoint = Petstore.GetPetEndpoint(
        pathComponents: .init(petId: 42),
        parameterComponents: .init(detail: "full", limit: 10),
        headerComponents: .init(xRequestID: "example")
    )
    let request = try endpoint.urlRequest()
    #expect(
        request.url?.absoluteString
            == "https://petstore.example/api/v3/pets/42?detail=full&limit=10")
    #expect(request.value(forHTTPHeaderField: "X-Request-ID") == "example")
    #expect(Petstore.Server.auth.key == "example-api-key")
}

@Test func statusUnionAndRepeatedTags() throws {
    let request = try Petstore.SearchPetsEndpoint(parameterComponents: .init(tags: ["a", "b"]))
        .urlRequest()
    #expect(
        request.url?.absoluteString == "https://petstore.example/api/v3/pets/search?tags=a&tags=b")
    let requestURL = try #require(request.url)
    let emptyResponse = try #require(
        HTTPURLResponse(
            url: requestURL, statusCode: 204, httpVersion: nil, headerFields: nil))
    let empty = try Petstore.SearchPetsEndpoint.responseDecoder.decode(
        Petstore.SearchPetsEndpoint.Response.self, from: Data(), response: emptyResponse)
    #expect(empty == .noContent)
    let foundResponse = try #require(
        HTTPURLResponse(
            url: requestURL, statusCode: 200, httpVersion: nil, headerFields: nil))
    let found = try Petstore.SearchPetsEndpoint.responseDecoder.decode(
        Petstore.SearchPetsEndpoint.Response.self,
        from: Data(#"[{"name":"Mochi","owner":null,"tags":["cat"]}]"#.utf8), response: foundResponse
    )
    guard case .ok(let pets) = found else {
        Issue.record("Expected matching pets")
        return
    }
    #expect(pets.map(\.name) == ["Mochi"])
}
