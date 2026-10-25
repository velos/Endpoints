import EndpointsGeneratorConfig
import Foundation
import Testing

@testable import EndpointsGeneratorCore

@Suite struct NamingReviewTests {
    @Test func unsupportedCookiesNeverUseQueryNames() {
        for strict in [true, false] {
            for includeQuery in [true, false] {
                let spec = """
                    openapi: 3.1.0
                    info: {title: Cookies, version: 1.0.0}
                    servers: [{url: 'https://example.com'}]
                    paths:
                      /x:
                        get:
                          parameters:
                            - {name: session, in: cookie, schema: {type: string, enum: [A, B]}}
                    \(includeQuery ? "        - {name: session, in: query, schema: {type: string}}" : "")
                          responses: {'204': {description: Empty}}
                    """
                let result = Generator.generate(
                    spec: Data(spec.utf8), configuration: .init(strict: strict),
                    stem: "Cookies", specPath: "Cookies.yaml")
                #expect(result.hasErrors == strict)
                #expect(
                    result.diagnostics.map(\.message) == [
                        "Unsupported: cookie or querystring parameters"
                    ])
                #expect(result.diagnostics.first?.pointer == "/paths/~1x/get/parameters/0")
                #expect(result.diagnostics.first?.severity == (strict ? .error : .warning))
                if !strict {
                    let text = result.files.map { String(decoding: $0.bytes, as: UTF8.self) }
                        .joined()
                    #expect(!text.contains("static let a ="))
                    #expect(text.contains(".query(\"session\",") == includeQuery)
                }
            }
        }
    }

    @Test func nestedCollisionUsesSwiftIdentitiesAndTheFailingPointer() {
        let result = MappingTests().schemas(
            """
            Value:
              type: object
              properties:
                tags: {type: array, items: {type: object, properties: {a: {type: string}}}}
                tagsItem: {type: object, properties: {b: {type: string}}}
            """)
        #expect(result.hasErrors)
        #expect(
            result.diagnostics.map(\.message) == [
                #"Name collision 'TagsItem' between '.type(.inline(.items(of: .inline(.property("tags", in: "Value")))))' (renames: [.type(.inline(.items(of: .inline(.property("tags", in: "Value"))))): "NewName"]) and '.type(.inline(.property("tagsItem", in: "Value")))' (renames: [.type(.inline(.property("tagsItem", in: "Value"))): "NewName"])"#
            ])
        #expect(
            result.diagnostics.first?.pointer == "/components/schemas/Value/properties/tagsItem")
    }

    @Test func initRemainsReservedForMembers() {
        let result = MappingTests().schemas(
            "Value: {type: object, properties: {init: {type: string}}}")
        #expect(result.hasErrors)
        #expect(
            result.diagnostics.map(\.message) == [
                #"Reserved name 'init' for 'init'; use renames: [.property("init", in: "Value"): "NewName"]"#
            ])
    }

    @Test func keywordDiagnosticsSuggestRenamesOnlyForStrategies() {
        let strategy = MappingTests().schemas("Type: {type: string}")
        #expect(
            strategy.diagnostics.map(\.message) == [
                #"Type name 'Type' is a Swift keyword; use renames: [.type("Type"): "NewName"]"#
            ])
        let renamed = MappingTests().schemas(
            "Ok: {type: string}", configuration: .init(renames: [.type("Ok"): "class"]))
        #expect(
            renamed.diagnostics.map(\.message) == [
                "Invalid rename value: Type name 'class' is a Swift keyword"
            ])
        #expect(renamed.diagnostics.first?.pointer == "/renames/0/name")
        let transported = MappingTests().schemas(
            "Ok: {type: string}",
            config: Data(#"{"version":1,"renames":[{"type":"Ok","name":"class"}]}"#.utf8))
        #expect(
            transported.diagnostics.map(\.message) == [
                "Invalid rename value: Type name 'class' is a Swift keyword"
            ])
        #expect(transported.diagnostics.first?.pointer == "/renames/0/name")
    }
    @Test func nilStrategiesDescribeTheStrategyUnlessInputIsTokenless() {
        for (wire, reason) in [
            ("pet_id", "The naming strategy returned no name for 'pet_id'"),
            ("---", "Name '---' has no ASCII identifier"),
        ] {
            let spec = """
                openapi: 3.1.0
                info: {title: Strategy, version: 1.0.0}
                servers: [{url: 'https://example.com'}]
                paths: {}
                components:
                  schemas:
                    Value: {type: object, properties: {'\(wire)': {type: string}}}
                """
            let result = Generator.generate(
                spec: Data(spec.utf8),
                configuration: .init(propertyNamingStrategy: .custom { _ in nil }),
                stem: "Strategy", specPath: "Strategy.yaml")
            #expect(result.hasErrors)
            #expect(
                result.diagnostics.map(\.message) == [
                    reason
                        + "; use renames: [.property(\(swiftLiteral(wire)), in: \"Value\"): \"NewName\"]"
                ])
            #expect(
                result.diagnostics.first?.pointer == "/components/schemas/Value/properties/\(wire)")
        }
    }

    @Test func onlyRequiredJSONBodiesParticipateInNaming() {
        for media in [
            "application/json", "application/vnd.test+json", "multipart/form-data",
            "application/x-www-form-urlencoded",
        ] {
            for required in [true, false] {
                let spec = """
                    openapi: 3.1.0
                    info: {title: Bodies, version: 1.0.0}
                    servers: [{url: 'https://example.com'}]
                    paths:
                      /send:
                        post:
                          operationId: send
                          requestBody:
                            required: \(required)
                            content: {'\(media)': {schema: {type: object, properties: {value: {type: string}}}}}
                          responses: {'204': {description: Empty}}
                    """
                let result = Generator.generate(
                    spec: Data(spec.utf8),
                    configuration: .init(
                        strict: false,
                        renames: [
                            .type(.inline(.body("send"))): "Input"
                        ]), stem: "Bodies", specPath: "Bodies.yaml")
                let isUsed = required && (media == "application/json" || media.hasSuffix("+json"))
                #expect(!result.hasErrors)
                let unused = result.diagnostics.filter { $0.message.hasPrefix("Unused rename") }
                #expect(
                    unused.map(\.message)
                        == (isUsed ? [] : [#"Unused rename target .type(.inline(.body("send")))"#]))
                #expect(result.diagnostics.allSatisfy { $0.severity == .warning })
                #expect(
                    result.files.map { String(decoding: $0.bytes, as: UTF8.self) }.joined()
                        .contains("struct Input") == isUsed)
            }
        }
    }

    @Test func configurationAdviceUsesCompleteSwiftSpellings() {
        let spec = Data(
            """
            openapi: 3.1.0
            info: {title: Config, version: 1.0.0}
            servers: [{url: 'https://example.com'}]
            paths: {}
            """.utf8)
        let reserved = Generator.generate(
            spec: spec, configuration: .init(), stem: "Date", specPath: "Date.yaml")
        #expect(
            reserved.diagnostics.map(\.message) == [
                #"Reserved namespace 'Date'; choose another with namespace: "…""#
            ])
        let collision = Generator.generate(
            spec: spec, configuration: .init(server: .type("X")), stem: "X", specPath: "X.yaml")
        #expect(
            collision.diagnostics.map(\.message) == [
                #"Namespace 'X' collides with the configured server type; choose another namespace: or module-qualify server: .type("Module.X")"#
            ])
    }

    @Test func serverNamingFailureDoesNotClaimTheURLIsMissing() {
        let spec = """
            openapi: 3.1.0
            info: {title: Server, version: 1.0.0}
            servers: [{url: 'https://example.com', description: 東京}]
            paths: {}
            """
        let result = Generator.generate(
            spec: Data(spec.utf8), configuration: .init(), stem: "ServerNames",
            specPath: "ServerNames.yaml")
        #expect(result.hasErrors)
        #expect(
            result.diagnostics.map(\.message) == [
                #"Name '東京' has no ASCII identifier; use renames: [.environment("東京"): "NewName"]"#
            ])
    }

}
