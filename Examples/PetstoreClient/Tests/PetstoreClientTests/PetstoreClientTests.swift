import Foundation
import Testing
import Endpoints
import PetstoreAPI

@Test func publicAuthenticationWitnessAndRequest() throws {
    #expect(Petstore.Server.Auth.self == HeaderKeyAuth.self)
    #expect(Petstore.GetPetEndpoint.Auth.self == HeaderKeyAuth.self)
    #expect(Petstore.GetLogoEndpoint.Auth.self == NoAuth.self)
    let endpoint = Petstore.GetPetEndpoint(
        pathComponents: .init(petId: 42),
        parameterComponents: .init(detail: "full", limit: 10),
        headerComponents: .init(xRequestID: "example")
    )
    let request = try endpoint.urlRequest()
    #expect(request.url?.absoluteString == "https://petstore.example/api/v3/pets/42?detail=full&limit=10")
    #expect(request.value(forHTTPHeaderField: "X-Request-ID") == "example")
    #expect(Petstore.Server.auth.key == "example-api-key")
}
