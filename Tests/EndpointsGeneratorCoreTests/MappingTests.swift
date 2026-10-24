import Foundation
import Testing

@testable import EndpointsGeneratorCore

@Suite struct MappingTests {
    func schemas(_ contents: String, strict: Bool = true) -> GenerationResult {
        let indentedContents = contents.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "    " + $0 }.joined(separator: "\n")
        let spec = """
            openapi: 3.1.0
            info: {title: Mapping, version: 1.0.0}
            servers: [{url: 'https://example.com/v1'}]
            paths: {}
            components:
              schemas:
            \(indentedContents)
            """
        return Generator.generate(
            spec: Data(spec.utf8), config: Data("{\"version\":1,\"strict\":\(strict)}".utf8),
            stem: "Mapping", specPath: "Mapping.openapi.yaml")
    }

    @Test func unsupportedSchemasRespectStrictMode() {
        for definition in [
            "Value: {allOf: [{type: string}, {type: string}]}",
            "Value: {oneOf: [{type: string}, {type: integer}]}",
            "Value: {anyOf: [{type: string}, {type: boolean}]}",
            "Value: {type: object, additionalProperties: {type: string}}",
            "Value: {type: boolean, enum: [true, false]}",
            "Value: {type: integer, format: int32, enum: [2147483648]}",
            "Value: {type: array}",
            """
            Value: {oneOf: [{type: 'null'}, {$ref: '#/components/schemas/Other'}]}
            Other: {oneOf: [{type: 'null'}, {$ref: '#/components/schemas/Value'}]}
            """,
            "Value: {type: object, properties: {next: {$ref: '#/components/schemas/Value'}}}",
        ] {
            let strict = schemas(definition)
            #expect(strict.hasErrors, "Accepted: \(definition)")
            #expect(strict.diagnostics.contains { $0.message.hasPrefix("Unsupported:") })
            let lenient = schemas(definition, strict: false)
            #expect(
                !lenient.hasErrors && lenient.files.count == 4,
                "\(lenient.diagnostics.map(\.formatted))")
            #expect(
                lenient.diagnostics.contains {
                    $0.severity == .warning && $0.message.hasPrefix("Unsupported:")
                })
        }
    }

    @Test func externalReferencesAndReservedNamesAreAlwaysErrors() throws {
        for strict in [true, false] {
            let external = schemas(
                "Value: {$ref: 'https://example.com/remote.json#/Value'}", strict: strict)
            #expect(external.hasErrors && external.files.isEmpty)
            #expect(external.diagnostics.first?.pointer == "/components/schemas/Value/$ref")
            #expect(external.diagnostics.first?.line == 7)
            let reserved = schemas("Date: {type: string}", strict: strict)
            #expect(reserved.hasErrors)
        }
        let result = try generation(
            "Reserved",
            config: Data(#"{"version":1,"renames":{"schemas":{"Date":"CalendarDate"}}}"#.utf8))
        #expect(!result.hasErrors)
        #expect(
            String(decoding: result.files[1].bytes, as: UTF8.self).contains("struct CalendarDate"))
        let collision = try generation(
            "Reserved",
            config: Data(
                #"{"version":1,"server":{"type":"CustomServer"},"renames":{"schemas":{"Date":"CustomServer"}}}"#
                    .utf8))
        #expect(
            collision.hasErrors
                && collision.diagnostics.contains {
                    $0.message.contains("Reserved name 'CustomServer'")
                })
    }

    @Test func unsupportedOperationBoundaries() {
        let definitions = [
            "parameters: [{name: ids, in: query, style: spaceDelimited, schema: {type: array, items: {type: string}}}]",
            "parameters: [{name: token, in: header, schema: {type: string, enum: [ok, bad]}}]",
            "parameters: [{name: ids, in: query, explode: false, schema: {type: array, items: {type: string}}}]",
            "parameters: [{name: id, in: path, required: true, schema: {type: boolean}}]",
            "parameters: [{name: id, in: query, schema: {type: object, properties: {x: {type: string}}}}]",
            "requestBody: {required: true, content: {multipart/form-data: {schema: {type: object}}}}",
            "requestBody: {required: true, content: {application/x-www-form-urlencoded: {schema: {type: object}}}}",
            "requestBody: {required: true, content: {application/octet-stream: {schema: {type: string}}}}",
            "servers: [{url: 'https://other.example'}]",
        ]
        for detail in definitions {
            for strict in [true, false] {
                let spec = """
                    openapi: 3.1.0
                    info: {title: Operations, version: 1.0.0}
                    servers: [{url: 'https://example.com'}]
                    paths:
                      /test:
                        post:
                          \(detail)
                          responses:
                            '204': {description: Empty}
                    """
                let result = Generator.generate(
                    spec: Data(spec.utf8),
                    config: Data("{\"version\":1,\"strict\":\(strict)}".utf8), stem: "Operations",
                    specPath: "Operations.openapi.yaml")
                #expect(
                    result.hasErrors == strict, "\(detail): \(result.diagnostics.map(\.formatted))")
                #expect(result.diagnostics.contains { $0.message.hasPrefix("Unsupported:") })
                if !strict {
                    let support = result.files.first { $0.name.hasSuffix(".Support.swift") }!
                    #expect(
                        !String(decoding: support.bytes, as: UTF8.self).contains("RFC3339"),
                        "A skipped construct must not emit unused date support")
                }
            }
        }
        for responses in [
            "'200': {description: OK, content: {application/json: {}}}"
        ] {
            let spec = """
                openapi: 3.1.0
                info: {title: Outcomes, version: 1.0.0}
                servers: [{url: 'https://example.com'}]
                paths:
                  /test:
                    get:
                      responses:
                        \(responses)
                """
            let result = Generator.generate(
                spec: Data(spec.utf8), stem: "Outcomes", specPath: "Outcomes.openapi.yaml")
            #expect(
                result.hasErrors
                    && result.diagnostics.contains { $0.message.hasPrefix("Unsupported:") })

        }
    }

    @Test func errorOnlyOperationProducesAnUnsupportedDiagnostic() {
        let spec = """
            openapi: 3.1.0
            info: {title: Outcomes, version: 1.0.0}
            servers: [{url: 'https://example.com'}]
            paths:
              /test:
                get:
                  responses:
                    '400': {description: Bad request}
            """
        let result = Generator.generate(
            spec: Data(spec.utf8), stem: "Outcomes", specPath: "Outcomes.openapi.yaml")
        #expect(result.hasErrors)
        #expect(
            result.diagnostics.contains {
                $0.message == "Unsupported: at least one success or default response is required"
                    && $0.pointer == "/paths/~1test/get/responses"
            })
    }

    @Test func droppedStatusesProduceSourceMarkedNotes() {
        let spec = """
            openapi: 3.1.0
            info: {title: StatusNotes, version: 1.0.0}
            servers: [{url: 'https://example.com'}]
            paths:
              /test:
                get:
                  responses:
                    1XX: {description: Informational}
                    '302': {description: Redirect}
                    3XX: {description: Redirection}
                    '204': {description: Empty}
            """
        let result = Generator.generate(
            spec: Data(spec.utf8), stem: "StatusNotes", specPath: "StatusNotes.openapi.yaml")
        #expect(!result.hasErrors)
        #expect(result.diagnostics.count == 3)
        #expect(
            result.diagnostics.allSatisfy { $0.severity == .note && $0.message.contains("ignored") }
        )
        #expect(
            result.diagnostics.map(\.pointer) == [
                "/paths/~1test/get/responses/1XX", "/paths/~1test/get/responses/302",
                "/paths/~1test/get/responses/3XX",
            ])
        #expect(result.diagnostics.map(\.line) == [8, 9, 10])
    }

    @Test func serversAndConfigOverride() throws {
        let base = """
            openapi: 3.1.0
            info: {title: Servers, version: 1.0.0}
            paths: {}
            servers:
              - url: https://{region}.example.com/v1
                description: First Server
                variables:
                  region: {default: us, enum: [us, eu]}
            """
        let data = Data(base.utf8)
        let result = Generator.generate(
            spec: data, stem: "Servers", specPath: "Servers.openapi.yaml")
        #expect(!result.hasErrors && result.diagnostics.first?.severity == .note)
        let text = String(decoding: result.files[0].bytes, as: UTF8.self)
        #expect(text.contains("https://us.example.com/v1/") && text.contains("case firstServer"))
        let keyword = Generator.generate(
            spec: Data(base.replacingOccurrences(of: "First Server", with: "default").utf8),
            stem: "Servers", specPath: "Servers.openapi.yaml")
        #expect(!keyword.hasErrors)
        #expect(String(decoding: keyword.files[0].bytes, as: UTF8.self).contains("{ .`default` }"))
        let configs = [
            (#"{"version":1,"server":{"type":"CustomServer"}}"#, "typealias Server = CustomServer"),
            (
                #"{"version":1,"server":{"environments":{"production":"https://example.com/a"}}}"#,
                "typealias Environments = TypicalEnvironments"
            ),
        ]
        for (config, needle) in configs {
            let value = Generator.generate(
                spec: data, config: Data(config.utf8), stem: "Servers",
                specPath: "Servers.openapi.yaml")
            #expect(
                !value.hasErrors
                    && String(decoding: value.files[0].bytes, as: UTF8.self).contains(needle))
        }
        let invalid = Generator.generate(
            spec: data,
            config: Data(
                #"{"version":1,"strict":false,"server":{"environments":{"staging":"https://h"}}}"#
                    .utf8), stem: "Servers", specPath: "Servers.openapi.yaml")
        #expect(
            invalid.hasErrors
                && invalid.diagnostics.contains { $0.message.contains("defaultEnvironment") })
        for url in ["/relative", "https://h/?q=1", "https://h/#f"] {
            let spec = base.replacingOccurrences(
                of: "https://{region}.example.com/v1", with: "'" + url + "'")
            let value = Generator.generate(
                spec: Data(spec.utf8), config: Data(#"{"version":1,"strict":false}"#.utf8),
                stem: "Servers", specPath: "Servers.openapi.yaml")
            #expect(value.hasErrors)
        }
    }

    @Test func loadingVersionsAndSourceMarks() {
        let cases = [
            ("swagger: '2.0'", "OpenAPI 2.0"),
            ("openapi: 3.5.0", "Expected OpenAPI version"),
            ("openapi: 3.1.0\ninfo: {title: MissingVersion}", "decoding failed"),
            ("openapi: [", "Invalid YAML"),
        ]
        for (spec, needle) in cases {
            let result = Generator.generate(
                spec: Data(spec.utf8), stem: "Bad", specPath: "Bad.openapi.yaml")
            #expect(result.hasErrors && result.diagnostics.contains { $0.message.contains(needle) })
            if needle == "Invalid YAML" {
                #expect(
                    result.diagnostics.contains {
                        $0.message.hasPrefix("Invalid YAML or JSON specification: \"")
                            && $0.message.contains("while parsing")
                    })
            }
        }
        let json =
            #"{"openapi":"3.1.0","info":{"title":"JSON","version":"1"},"servers":[{"url":"https://h"}],"paths":{}}"#
        for version in ["3.1.0", "3.2.0"] {
            let result = Generator.generate(
                spec: Data(json.replacingOccurrences(of: "3.1.0", with: version).utf8),
                stem: "JSONAPI", specPath: "JSONAPI.openapi.json")
            #expect(!result.hasErrors && result.files.count == 4)
        }
    }
}
