import Endpoints
import Foundation
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite struct GeneratedNamingTests {
    @Test func customizedNamesKeepCodingKeysAndEnumRawValues() throws {
        let json = Data(
            #"{"owner_name":"Mochi","status":"IN_PROGRESS","number_code":-1,"user_id":"u","image_url":"https://h","HTTP2Status":"ok","UTF8String":"hello","annotated":"ready-now","tags":[{"tag_id":"t"}],"child":{"child_name":"c"}}"#
                .utf8)
        let pet = try JSONDecoder().decode(NamingConfigured.PetRecord.self, from: json)
        #expect(pet.owner == "Mochi" && pet.status == .working)
        #expect(pet.numberCode == .valueMinus1 && pet.annotated == .ready)
        #expect(pet.http2Status == "ok" && pet.utf8String == "hello")
        let encoded = try JSONEncoder().encode(pet)
        #expect(
            try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
                == JSONSerialization.jsonObject(with: json) as? NSDictionary)
        #expect(
            NamingConfigured.PetRecord.OrderStatus.knownValues.map(\.rawValue).map { Data($0.utf8) }
                == ["IN_PROGRESS", "on-hold", "2fa_required", ""].map { Data($0.utf8) })
    }
    @Test func customizedLocatedParametersKeepRequestNames() throws {
        let request = try NamingConfigured.GetPetsByPetIDEndpoint(
            pathComponents: .init(petID: "pet-42"),
            parameterComponents: .init(queryIdentifier: "q"),
            headerComponents: .init(headerIdentifier: "h", xRequestID: "req")
        ).urlRequest()
        #expect(request.url?.absoluteString == "https://example.com/api/pets/pet-42?id=q")
        #expect(request.value(forHTTPHeaderField: "id") == "h")
        #expect(request.value(forHTTPHeaderField: "X-Request-ID") == "req")
    }
}
