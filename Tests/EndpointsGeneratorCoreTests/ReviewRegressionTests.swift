import Foundation
import Testing

@testable import EndpointsGeneratorCore

@Suite struct ReviewRegressionTests {
    @Test func namespaceCannotBeShadowedByGeneratedTypes() {
        let cases = [
            ("Mapping: {type: string}", #"renames.schemas["Mapping"]"#),
            (
                "Container: {type: object, properties: {mapping: {type: object, properties: {id: {type: string}}}}}",
                #"renames.properties["Container.mapping"]"#
            ),
        ]
        for (schema, hint) in cases {
            let result = MappingTests().schemas(schema)
            #expect(result.hasErrors)
            #expect(
                result.diagnostics.contains {
                    $0.message.contains("Reserved name 'Mapping'") && $0.message.contains(hint)
                })
        }
        let spec = """
            openapi: 3.1.0
            info: {title: Mapping, version: 1.0.0}
            servers: [{url: 'https://example.com'}]
            paths:
              /test:
                post:
                  requestBody:
                    required: true
                    content:
                      application/json:
                        schema: {type: object, properties: {mapping: {type: object, properties: {id: {type: string}}}}}
                  responses: {'204': {description: Empty}}
            """
        let result = Generator.generate(
            spec: Data(spec.utf8), stem: "Mapping", specPath: "Mapping.openapi.yaml")
        #expect(
            result.hasErrors
                && result.diagnostics.contains { $0.message.contains("Reserved name 'Mapping'") })
    }

    @Test func bearerDocumentationUsesTheDocumentRequirement() {
        let spec = """
            openapi: 3.1.0
            info: {title: Bearer, version: 1.0.0}
            servers: [{url: 'https://example.com'}]
            paths: {}
            security: [{token: []}]
            components:
              securitySchemes:
                apiKey: {type: apiKey, in: header, name: X-API-Key}
                token: {type: http, scheme: bearer}
            """
        let result = Generator.generate(
            spec: Data(spec.utf8), config: Data(#"{"version":1,"accessLevel":"public"}"#.utf8),
            stem: "Bearer", specPath: "Bearer.openapi.yaml")
        #expect(!result.hasErrors)
        let server = String(decoding: result.files[0].bytes, as: UTF8.self)
        #expect(
            server.contains(
                "///     extension Bearer.Server {\n    ///         public static let auth = HeaderKeyAuth(key: token)\n    ///     }"
            ))
        #expect(server.contains("- `token`: http bearer (`HeaderKeyAuth` or `JWTAuth`)"))
        #expect(server.contains("- `apiKey`: apiKey in header `X-API-Key` (`HeaderKeyAuth`)"))
        #expect(!server.contains("///\n    ///\n"))
    }

    @Test func decodingAndValidationRetainSourceContext() {
        let malformed = """
            openapi: 3.1.0
            info:
              title: Malformed
              version: {}
            paths: {}
            """
        let decoded = Generator.generate(
            spec: Data(malformed.utf8), stem: "Malformed", specPath: "Malformed.openapi.yaml")
        let failure = decoded.diagnostics.first { $0.message.contains("decoding failed") }
        #expect(failure?.pointer == "/info/version")
        #expect(failure?.line == 4 && failure?.column == 3)
        #expect(failure?.message.contains("\"") == true)

        let invalid = """
            openapi: 3.1.0
            info: {title: Invalid, version: 1.0.0}
            servers: [{url: 'https://example.com'}]
            paths:
              /test:
                get:
                  responses:
                    '200':
                      description: OK
                      content:
                        application/json:
                          schema: {$ref: '#/components/schemas/Missing'}
            """
        let validated = Generator.generate(
            spec: Data(invalid.utf8), stem: "Invalid", specPath: "Invalid.openapi.yaml")
        #expect(
            validated.diagnostics.contains {
                $0.pointer.contains("/responses/200") && $0.line == 12 && $0.column == 15
                    && $0.message.contains("\"Failed to satisfy: JSONSchema reference")
            })
    }

    @Test func referenceDiagnosticsPointToComponentContentAndEmptyObjectsWork() {
        let spec = """
            openapi: 3.1.0
            info: {title: References, version: 1.0.0}
            servers: [{url: 'https://example.com'}]
            paths:
              /test:
                post:
                  requestBody: {$ref: '#/components/requestBodies/Input'}
                  responses:
                    '200': {$ref: '#/components/responses/Output'}
            components:
              requestBodies:
                Input:
                  required: true
                  content:
                    application/json:
                      schema: {type: object, properties: {}}
              responses:
                Output:
                  description: OK
                  content:
                    application/json:
                      schema: {type: object, additionalProperties: {type: string}}
            """
        let result = Generator.generate(
            spec: Data(spec.utf8), stem: "References", specPath: "References.openapi.yaml")
        #expect(result.diagnostics.count == 1)
        #expect(
            result.diagnostics.first?.pointer
                == "/components/responses/Output/content/application~1json/schema/additionalProperties"
        )
        #expect(result.diagnostics.first?.line == 22)
        let supported = spec.replacingOccurrences(
            of: "additionalProperties: {type: string}", with: "properties: {}")
        let empty = Generator.generate(
            spec: Data(supported.utf8), stem: "References", specPath: "References.openapi.yaml")
        #expect(!empty.hasErrors && empty.files.count == 4)
    }

    @Test func sharedDAGGenerationIsLinear() throws {
        let start = ContinuousClock.now
        let result = try generation("SharedDAG")
        let elapsed = start.duration(to: .now)
        #expect(!result.hasErrors && result.files.count == 4)
        #expect(elapsed < .seconds(1), "20 levels with three shared references took \(elapsed)")
    }

    @Test func fallbackOperationIdentityIsUsableForRenames() throws {
        let collision = try generation("NoOperationId")
        #expect(collision.hasErrors)
        #expect(
            collision.diagnostics.contains {
                $0.message.contains("GET /pets/{petId}")
                    && $0.message.contains("GET /pets/by-pet-id")
            })
        let renamed = try generation(
            "NoOperationId",
            config: Data(
                #"{"version":1,"renames":{"operations":{"GET /pets/by-pet-id":"FindPets"}}}"#.utf8))
        #expect(!renamed.hasErrors)
        #expect(
            String(decoding: renamed.files[2].bytes, as: UTF8.self).contains(
                "struct FindPetsEndpoint"))
    }

    @Test func dateOverridesAreScopedToEachPayload() throws {
        let result = try generation("DateScopes")
        #expect(!result.hasErrors)
        let endpoints = String(decoding: result.files[2].bytes, as: UTF8.self)
        // Exactly one payload of each kind involves Date. The Plain endpoint
        // shares the module but must inherit all three ordinary runtime coders.
        for name in ["bodyEncoder", "responseDecoder", "errorDecoder"] {
            #expect(endpoints.components(separatedBy: "static var " + name).count == 2)
        }
        let plain = endpoints.components(separatedBy: "struct PlainEndpoint")[1]
        #expect(!plain.contains("static var bodyEncoder"))
        #expect(!plain.contains("static var responseDecoder"))
        #expect(!plain.contains("static var errorDecoder"))
    }

    @Test func dependentRemovalUsesTheDeclarationPointer() {
        let result = MappingTests().schemas(
            """
            Bad: {type: object, additionalProperties: {type: string}}
            Dependent: {type: array, items: {$ref: '#/components/schemas/Bad'}}
            """, strict: false)
        #expect(!result.hasErrors)
        let removed = result.diagnostics.first {
            $0.message.contains("depends on a skipped schema")
        }
        #expect(removed?.pointer == "/components/schemas/Dependent")
        #expect(removed?.line == 8 && removed?.column == 5)
    }

    @Test func deprecatedBackingNamesCannotCollideWithWireProperties() {
        let result = MappingTests().schemas(
            """
            Value:
              type: object
              properties:
                oldName: {type: string, deprecated: true}
                _oldName: {type: string}
            """)
        #expect(result.hasErrors)
        #expect(
            result.diagnostics.contains {
                $0.message.contains("Name collision '_oldName'")
                    && $0.message.contains(#"renames.properties["Value._oldName"]"#)
            })
    }

    @Test func initializerLineLengthIncludesIndentation() {
        for length in [76, 77] {
            let name = String(repeating: "a", count: length)
            let result = MappingTests().schemas(
                "Value: {type: object, required: [\(name)], properties: {\(name): {type: string}}}")
            #expect(!result.hasErrors)
            let source = String(decoding: result.files[1].bytes, as: UTF8.self)
            if length == 76 {
                let signature = source.components(separatedBy: "\n").first { $0.contains("init(") }
                #expect(signature?.utf8.count == 100)
            } else {
                #expect(source.contains("        init(\n            \(name): String\n        ) {"))
            }
        }
    }

    @Test func wireNameMatchingUsesBytes() {
        // These visually identical strings are canonically equivalent, but distinct wire keys.
        let composed = "Caf\u{e9}"
        let decomposed = "Cafe\u{301}"
        let schema =
            "\(composed): {type: string}\nAlias: {$ref: '#/components/schemas/\(decomposed)'}"
        let result = MappingTests().schemas(schema)
        #expect(result.hasErrors)
        #expect(
            result.diagnostics.contains {
                $0.message.contains("reference") || $0.message.contains("Reference")
            })

        let spec = """
            openapi: 3.1.0
            info: {title: Wire keys, version: 1.0.0}
            servers: [{url: 'https://example.com'}]
            paths:
              /test:
                parameters: [{name: \(composed), in: query, schema: {type: string}}]
                get:
                  parameters: [{name: \(decomposed), in: query, schema: {type: string}}]
                  responses: {'204': {description: Empty}}
            components:
              schemas:
                \(composed): {type: string}
            """
        let config = "{\"version\":1,\"renames\":{\"schemas\":{\"\(decomposed)\":\"Unexpected\"}}}"
        let matched = Generator.generate(
            spec: Data(spec.utf8), config: Data(config.utf8), stem: "Wire",
            specPath: "Wire.openapi.yaml")
        #expect(!matched.hasErrors, "\(matched.diagnostics.map(\.formatted))")
        let schemas = String(
            decoding: matched.files.first { $0.name.hasSuffix(".Schemas.swift") }?.bytes ?? Data(),
            as: UTF8.self)
        #expect(schemas.contains("typealias Caf = String"))
        let endpoints = String(
            decoding: matched.files.first { $0.name.hasSuffix(".Endpoints.swift") }?.bytes
                ?? Data(), as: UTF8.self)
        #expect(endpoints.contains(".query(\"\(composed)\", path: \\.caf)"))
        #expect(endpoints.contains(".query(\"\(decomposed)\", path: \\.cafe)"))
    }
}
