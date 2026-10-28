import Testing
import RuntimeOnlyClient

@Test func buildsRuntimeRequest() throws {
    let request = try StatusEndpoint().urlRequest()
    #expect(request.url?.absoluteString == "https://status.example.com/status")
}
