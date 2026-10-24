import Endpoints
import Foundation
import Testing

@Suite struct GeneratedRequestTests {
    @Test func queryHeadersPathAndBodyBytes() throws {
        let endpoint = Petstore.GetPetEndpoint(
            pathComponents: .init(petId: 42),
            parameterComponents: .init(detail: "full & fresh", limit: 3, score: 1.5, active: true),
            headerComponents: .init(xRequestID: "req-123")
        )
        let request = try endpoint.urlRequest()
        #expect(request.httpMethod == "GET")
        #expect(
            request.url?.absoluteString
                == "https://petstore.example/api/v3/pets/42?detail=full%20%26%20fresh&limit=3&score=1.5&active=true"
        )
        #expect(request.value(forHTTPHeaderField: "X-Request-ID") == "req-123")
        #expect(request.httpBody == nil)
        let minimal = try Petstore.GetPetEndpoint(
            pathComponents: .init(petId: 7), parameterComponents: .init(detail: "short"),
            headerComponents: .init(xRequestID: "m")
        ).urlRequest(in: .staging)
        #expect(minimal.url?.absoluteString == "https://staging.example/api/v3/pets/7?detail=short")
        let pet = Petstore.Pet(name: "Mochi", owner: nil, tags: ["cat"])
        let created = try Petstore.CreatePetEndpoint(body: pet).urlRequest()
        #expect(created.httpMethod == "POST")
        #expect(
            try JSONSerialization.jsonObject(with: #require(created.httpBody)) as? NSDictionary == [
                "name": "Mochi", "owner": NSNull(), "tags": ["cat"],
            ] as NSDictionary)
        #expect(created.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let renamed = try Petstore.RenamePetEndpoint(body: .init(name: "Miso")).urlRequest()
        #expect(renamed.httpMethod == "PATCH")
        #expect(renamed.httpBody == Data(#"{"name":"Miso"}"#.utf8))
        #expect(renamed.value(forHTTPHeaderField: "Content-Type") == "application/merge-patch+json")
        let deleted = try Petstore.DeletePetEndpoint(pathComponents: .init(petId: 9)).urlRequest()
        #expect(deleted.httpMethod == "DELETE" && deleted.httpBody == nil)
        #expect(Petstore.GetLogoEndpoint.Response.self == Data.self)
        #expect(Petstore.DeletePetEndpoint.Response.self == Void.self)
    }

    @Test func requiredNullableAndOffsetDateWireContract() throws {
        let json = Data(
            #"{"zeta":"z","alpha":2,"owner_id":null,"id":9223372036854775806,"timestamp":"2024-01-05T15:30:00.123+05:30","metadata":{"count":2147483647,"enabled":true}}"#
                .utf8)
        let record = try Boundaries.GetRecordEndpoint.responseDecoder.decode(
            Boundaries.Record.self, from: json)
        #expect(record.ownerId == nil && record.id == 9_223_372_036_854_775_806)
        #expect(record.metadata?.count == Int32.max)
        #expect(record.timestamp.timeIntervalSince1970 == 1_704_448_800.123)
        let request = try Boundaries.UpdateRecordEndpoint(
            pathComponents: .init(recordId: "abc-42"), headerComponents: .init(xRequestID: "b"),
            body: record
        ).urlRequest()
        #expect(request.url?.absoluteString == "https://EXAMPLE.com/api/v3/records/abc-42")
        #expect(request.httpMethod == "PUT")
        #expect(
            request.httpBody
                == Data(
                    #"{"alpha":2,"id":9223372036854775806,"metadata":{"count":2147483647,"enabled":true},"owner_id":null,"timestamp":"2024-01-05T10:00:00.123Z","zeta":"z"}"#
                        .utf8))
        let missing = Data(
            #"{"zeta":"z","alpha":2,"id":1,"timestamp":"2024-01-05T10:00:00Z"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try Boundaries.GetRecordEndpoint.responseDecoder.decode(
                Boundaries.Record.self, from: missing)
        }
        let error = try Boundaries.GetRecordEndpoint.errorDecoder.decode(
            Boundaries.GetRecordEndpoint.ErrorResponse.self,
            from: Data(#"{"message":"not found"}"#.utf8))
        #expect(error.message == "not found")
        #expect(Boundaries.GetRecordEndpoint.Auth.self == NoAuth.self)
    }

    @Test func extensibleEnumsNestedObjectsAndNonIdentifierKeys() throws {
        let json = Data(
            #"{"name":"Mochi","owner":null,"tags":[],"status":"future-state","class":"mammal","profile":{"website":"https://h/p","uuid":"12345678-1234-1234-1234-123456789ABC","avatar":"aGk="},"history":[{"description":"arrived"}]}"#
                .utf8)
        let pet = try JSONDecoder().decode(Petstore.Pet.self, from: json)
        #expect(pet.status?.rawValue == "future-state")
        #expect(Petstore.Pet.Status.knownValues == [.available, .pending, .sold])
        #expect(pet.profile?.avatar == Data("hi".utf8))
        #expect(pet.profile?.website?.absoluteString == "https://h/p")
        #expect(pet.profile?.uuid == UUID(uuidString: "12345678-1234-1234-1234-123456789abc"))
        #expect(pet.history?.first?.description == "arrived")
        #expect(pet.class == "mammal")
        let encoded = try Petstore.JSONCoding.makeEncoder().encode(pet)
        #expect(
            try JSONSerialization.jsonObject(with: encoded) as? NSDictionary
                == JSONSerialization.jsonObject(with: json) as? NSDictionary)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                Petstore.Pet.self, from: Data(#"{"name":"Mochi","tags":[]}"#.utf8))
        }
    }
}

@Suite struct RFC3339Tests {
    @Test func offsetsFractionsAndGregorianBoundaries() throws {
        let cases: [(String, String, Double)] = [
            ("0000-01-01T00:00:00Z", "0000-01-01T00:00:00.000Z", -62_167_219_200),
            ("9999-12-31T23:59:59Z", "9999-12-31T23:59:59.000Z", 253_402_300_799),
            ("1990-12-31T23:59:60Z", "1991-01-01T00:00:00.000Z", 662_688_000),
            ("1990-12-31T15:59:60-08:00", "1991-01-01T00:00:00.000Z", 662_688_000),
            ("1970-01-01T00:00:00Z", "1970-01-01T00:00:00.000Z", 0),
            ("1970-01-01T01:30:00+01:30", "1970-01-01T00:00:00.000Z", 0),
            ("1969-12-31T23:59:59.999Z", "1969-12-31T23:59:59.999Z", -0.001),
            ("2000-02-29T23:30:00-00:30", "2000-03-01T00:00:00.000Z", 951_868_800),
            ("2024-01-05t15:30:00.123456+05:30", "2024-01-05T10:00:00.123Z", 1704448800.123456),
            ("2024-01-05T03:00:00-07:00", "2024-01-05T10:00:00.000Z", 1_704_448_800),
        ]
        for (input, formatted, seconds) in cases {
            guard let date = Boundaries.RFC3339.parse(input) else {
                Issue.record("Expected to parse date-time: \(input)")
                continue
            }
            let actualSeconds = date.timeIntervalSince1970
            let actualFormatted = Boundaries.RFC3339.format(date)
            #expect(abs(actualSeconds - seconds) < 0.000001)
            #expect(actualFormatted == formatted)
        }
        for input in [
            "1990-12-31T12:00:60Z", "1990-12-30T23:59:60Z", "", "2023-02-29T00:00:00Z",
            "1900-02-29T00:00:00Z", "2024-13-01T00:00:00Z", "2024-01-00T00:00:00Z",
            "2024-01-01T24:00:00Z", "2024-01-01T00:60:00Z", "2024-01-01 00:00:00Z",
            "2024-01-01T00:00:00", "2024-01-01T00:00:00.Z", "2024-01-01T00:00:00+24:00",
            "2024-01-01T00:00:00Zjunk",
        ] {
            let accepted = Boundaries.RFC3339.parse(input) != nil
            #expect(!accepted, "Unexpectedly accepted date-time: \(input)")
        }
        let invalidSeconds: [Double] = [
            .infinity, -.infinity, .nan, .greatestFiniteMagnitude,
            -62_167_219_201, 253_402_300_800,
        ]
        for seconds in invalidSeconds {
            let record = Boundaries.Record(
                zeta: "z", alpha: 1, ownerId: nil, id: 1,
                timestamp: Date(timeIntervalSince1970: seconds))
            // Never pass the record, its Date, or an unchecked error to Testing's
            // diagnostics: Foundation 6.1 on Linux traps when describing NaN/Inf dates.
            do {
                _ = try Boundaries.JSONCoding.makeEncoder().encode(record)
                Issue.record("Expected the encoder to reject invalid date seconds")
            } catch let error as EncodingError {
                guard case .invalidValue(let invalidValue, _) = error else {
                    Issue.record("Expected EncodingError.invalidValue for invalid date seconds")
                    continue
                }
                let payloadIsDouble = invalidValue is Double
                #expect(payloadIsDouble)
                guard let actualSeconds = invalidValue as? Double else { continue }
                #expect(actualSeconds.isNaN == seconds.isNaN)
                if !seconds.isNaN { #expect(actualSeconds == seconds) }
                let description = String(describing: error)
                #expect(!description.isEmpty)
            } catch {
                Issue.record("Expected EncodingError.invalidValue for invalid date seconds")
            }
        }
        let roundedNegative = Boundaries.RFC3339.format(Date(timeIntervalSince1970: -0.0006))
        #expect(roundedNegative == "1969-12-31T23:59:59.999Z")
        #expect(throws: DecodingError.self) {
            try Boundaries.JSONCoding.makeDecoder().decode(
                Boundaries.Record.self,
                from: Data(
                    #"{"zeta":"z","alpha":1,"owner_id":null,"id":1,"timestamp":"not-a-date"}"#.utf8)
            )
        }
    }
}

@Suite struct SchemaEdgeTests {
    @Test func closedEnumsNestedPresenceAndComponentArrays() throws {
        let data = Data(
            #"{"mode":null,"nickname":null,"child":{"nullable":null},"values":["a",null]}"#.utf8)
        let value = try JSONDecoder().decode(SchemaEdges.Container.self, from: data)
        #expect(
            value.mode == nil && value.nickname == nil && value.readOnly == nil
                && value.writeOnly == nil && value.refReadOnly == nil)
        #expect(value.child.nullable == nil && value.values == ["a", nil])
        #expect(
            try SchemaEdges.JSONCoding.makeEncoder().encode(value)
                == Data(
                    #"{"child":{"nullable":null},"mode":null,"nickname":null,"values":["a",null]}"#
                        .utf8))
        #expect(SchemaEdges.Mode.allCases == [.red, .blue])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SchemaEdges.Mode.self, from: Data(#""future""#.utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                SchemaEdges.Container.self,
                from: Data(#"{"mode":null,"nickname":null,"child":{},"values":[]}"#.utf8))
        }
        let shapes = try JSONDecoder().decode(
            SchemaEdges.Shapes.self, from: Data(#"[{"value":1.5},{"value":2}]"#.utf8))
        #expect(shapes.map(\.value) == [1.5, 2])
        let legacy = SchemaEdges.LegacyRecord(oldName: "from initializer")
        let legacyJSON = try SchemaEdges.JSONCoding.makeEncoder().encode(legacy)
        #expect(legacyJSON == Data(#"{"old-name":"from initializer"}"#.utf8))
        let decodedLegacy = try JSONDecoder().decode(
            SchemaEdges.LegacyRecord.self, from: legacyJSON)
        #expect(decodedLegacy == legacy)
        let endpointLegacy = try SchemaEdges.GetLegacyEndpoint.responseDecoder.decode(
            SchemaEdges.GetLegacyEndpoint.Response.self, from: legacyJSON)
        #expect(endpointLegacy == legacy)
        let linkedJSON = Data(
            #"{"legacy":{"old-name":"from initializer"},"mode":null,"nickname":null,"child":{"nullable":null},"values":[]}"#
                .utf8)
        let linked = try JSONDecoder().decode(SchemaEdges.Container.self, from: linkedJSON)
        #expect(linked.legacy == legacy)
        let withOptional = SchemaEdges.LegacyRecord(oldName: "old", oldCount: 42)
        let optionalJSON = try SchemaEdges.JSONCoding.makeEncoder().encode(withOptional)
        #expect(optionalJSON == Data(#"{"old-count":42,"old-name":"old"}"#.utf8))

        #expect(SchemaEdges.Environment.allCases == [.zebra, .alpha])
        #expect(SchemaEdges.Server.defaultEnvironment == .zebra)
        let request = try SchemaEdges.GetFilesByFileIdJsonEndpoint(
            pathComponents: .init(fileId: 42),
            parameterComponents: .init(legacyFilter: "old"),
            headerComponents: .init(xLegacy: "legacy")
        ).urlRequest()
        #expect(
            request.url?.absoluteString == "https://example.com/files/42.json?legacy-filter=old")
        #expect(request.value(forHTTPHeaderField: "X-Legacy") == "legacy")
    }
}

@Suite struct DateScopeTests {
    @Test func eachPayloadUsesItsOwnDateStrategy() throws {
        let json = Data(#"{"times":["2024-01-05T15:30:00.123+05:30"]}"#.utf8)
        let response = try DateScopes.DateResponseEndpoint.responseDecoder.decode(
            DateScopes.Record.self, from: json)
        let error = try DateScopes.DateErrorEndpoint.errorDecoder.decode(
            DateScopes.Record.self, from: json)
        let responseSeconds = response.times.map(\.timeIntervalSince1970)
        let errorSeconds = error.times.map(\.timeIntervalSince1970)
        #expect(responseSeconds == errorSeconds)
        #expect(responseSeconds.first == 1_704_448_800.123)
        let request = try DateScopes.DateBodyEndpoint(body: response).urlRequest()
        #expect(request.httpBody == Data(#"{"times":["2024-01-05T10:00:00.123Z"]}"#.utf8))
        let plain = try DateScopes.PlainEndpoint(body: .init(value: "ok")).urlRequest()
        #expect(plain.httpBody == Data(#"{"value":"ok"}"#.utf8))
    }
}
