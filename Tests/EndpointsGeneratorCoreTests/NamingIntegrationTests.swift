import EndpointsGeneratorConfig
import Foundation
import Testing

@testable import EndpointsGeneratorCore

@Suite struct NamingIntegrationTests {
    func generate(_ schemas: String, _ json: String) -> GenerationResult {
        MappingTests().schemas(schemas, config: Data(json.utf8))
    }

    func generate(_ schemas: String, _ configuration: EndpointsConfiguration = .init())
        -> GenerationResult
    {
        MappingTests().schemas(schemas, configuration: configuration)
    }

    @Test func deferredFailuresAndIndependentInlineNames() {
        let result = generate(
            """
            東京:
              type: object
              properties:
                '---': {type: object, properties: {user_id: {type: string}}}
            """,
            EndpointsConfiguration(renames: [
                .type("東京"): "Tokyo", .property("---", in: "東京"): "child",
                .type(.inline(.property("---", in: "東京"))): "ChildRecord",
            ])
        )
        #expect(!result.hasErrors, "\(result.diagnostics.map(\.formatted))")
        let text = result.files.map { String(decoding: $0.bytes, as: UTF8.self) }.joined()
        #expect(text.contains("struct Tokyo"))
        #expect(text.contains("var child: Mapping.Tokyo.ChildRecord?"))
        #expect(text.contains("struct ChildRecord"))
        #expect(text.contains(#"case child = "---""#))
        #expect(text.contains(#"case userId = "user_id""#))
    }

    @Test func structuredOwnersCannotAliasDottedNames() {
        let result = generate(
            """
            Order.status: {type: string, enum: [IN_PROGRESS]}
            Order: {type: object, properties: {status: {type: string, enum: [IN_PROGRESS]}}}
            """,
            EndpointsConfiguration(renames: [
                .enumCase("IN_PROGRESS", in: "Order.status"): "componentValue",
                .enumCase("IN_PROGRESS", in: .inline(.property("status", in: "Order"))):
                    "propertyValue",
            ])
        )
        #expect(!result.hasErrors, "\(result.diagnostics.map(\.formatted))")
        let text = String(decoding: result.files[1].bytes, as: UTF8.self)
        #expect(text.contains("static let componentValue"))
        #expect(text.contains("static let propertyValue"))
    }

    @Test func collisionsCoverTheReferenceTable() {
        for (properties, strategy, collision) in [
            (
                "foo_bar: {type: string}, foo-bar: {type: string}, fooBar: {type: string}",
                NamingStrategy.camelCase, "fooBar"
            ),
            ("foo_bar: {type: string}, foo-bar: {type: string}", .verbatim, "foo_bar"),
            ("_id: {type: string}, id: {type: string}", .camelCase, "id"),
        ] {
            let result = generate(
                "Value: {type: object, properties: {\(properties)}}",
                EndpointsConfiguration(propertyNamingStrategy: strategy))
            #expect(result.hasErrors)
            #expect(
                result.diagnostics.contains {
                    $0.message.contains("Name collision '\(collision)'")
                        && $0.message.contains("renames: [.")
                })
        }
        let preserved = generate(
            "Value: {type: object, properties: {_id: {type: string}, id: {type: string}}}",
            EndpointsConfiguration(propertyNamingStrategy: .verbatim))
        #expect(!preserved.hasErrors)
        for strategy in [NamingStrategy.camelCase, .verbatim] {
            let result = generate(
                "Value: {type: string, enum: ['', empty]}",
                EndpointsConfiguration(enumCaseNamingStrategy: strategy))
            #expect(
                result.hasErrors
                    && result.diagnostics.contains { $0.message.contains("Name collision 'empty'") }
            )
        }
    }

    @Test func renameErrorsWarningsAndPrivateTransportDiagnostics() throws {
        let badConfigs: [(String, String)] = [
            (#"{"version":1,"renames":false}"#, "/renames"),
            (
                #"{"version":1,"renames":[{"type":"Pet","name":"Animal"},{"type":"Pet","name":"Creature"}]}"#,
                "/renames/1"
            ),
            (#"{"version":1,"renames":[{"type":"Missing","name":"Type"}]}"#, "/renames/0/name"),
            (
                #"{"version":1,"renames":[{"property":"id","in":"Pet","name":"rawValue"}]}"#,
                "/renames/0/name"
            ),
            (
                #"{"version":1,"renames":[{"property":"id","in":"Pet","name":"x","typo":true}]}"#,
                "/renames/0/typo"
            ),
            (
                #"{"version":1,"renames":[{"parameter":"id","location":"cookie","operation":"getPet","name":"x"}]}"#,
                "/renames/0"
            ),
            (#"{"version":1,"typeNamingStrategy":"custom"}"#, "/typeNamingStrategy"),
            (#"{"version":1,"acronyms":["ID","Id"]}"#, "/acronyms/1"),
            (#"{"version":1,"acronyms":["A_B"]}"#, "/acronyms/0"),
        ]
        for (json, pointer) in badConfigs {
            let result = generate("Pet: {type: string}", json)
            #expect(
                result.hasErrors && result.diagnostics.contains { $0.pointer == pointer },
                "\(json): \(result.diagnostics)")
        }
        let invalidTyped: [(EndpointsConfiguration, String)] = [
            (.init(namespace: "Date"), "/namespace"),
            (.init(server: .type("Server")), "/server/type"),
            (.init(acronyms: ["ID", "Id"]), "/acronyms/1"),
            (.init(renames: [.property("id", in: "Pet"): "rawValue"]), "/renames/0/name"),
        ]
        for (configuration, pointer) in invalidTyped {
            let result = generate("Pet: {type: string}", configuration)
            #expect(result.hasErrors && result.diagnostics.contains { $0.pointer == pointer })
        }
        let unused = generate(
            "Pet: {type: string}",
            EndpointsConfiguration(strict: false, renames: [.type("Missing"): "Animal"]))
        #expect(!unused.hasErrors && unused.files.count == 4)
        #expect(unused.diagnostics.count == 1 && unused.diagnostics[0].severity == .warning)
        #expect(unused.diagnostics[0].pointer == "/renames/0")
        let spec = try Data(contentsOf: fixture("Petstore"))
        let ambiguous = Generator.generate(
            spec: spec,
            configuration: EndpointsConfiguration(renames: [
                .operation("getPet"): "A",
                .operation(.route(method: .get, path: "/pets/{petId}")): "B",
            ]), stem: "Pets", specPath: "Pets.yaml")
        #expect(
            ambiguous.hasErrors
                && ambiguous.diagnostics.contains { $0.message.contains("Ambiguous rename") })
        let excluded = Generator.generate(
            spec: spec,
            configuration: EndpointsConfiguration(
                operations: .init(exclude: ["*"]), renames: [.operation("getPet"): "GetPet"]),
            stem: "Pets", specPath: "Pets.yaml")
        #expect(
            !excluded.hasErrors
                && excluded.diagnostics.contains {
                    $0.severity == .warning && $0.message.contains("Unused rename")
                })
    }

    @Test func specExtensionsValidateAndRenamesWin() {
        let result = generate(
            """
            original_type:
              type: object
              x-swift-name: better_type
              properties:
                wire_key: {type: string, x-swift-name: better_key}
                state: {type: integer, enum: [-1, 2], x-enum-varnames: [BAD, GOOD]}
            """,
            EndpointsConfiguration(
                propertyNamingStrategy: .custom {
                    $0.replacing("custom_" + $0.wireName).camelCased
                },
                renames: [.property("wire_key", in: "original_type"): "renamed"])
        )
        #expect(!result.hasErrors, "\(result.diagnostics)")
        let text = String(decoding: result.files[1].bytes, as: UTF8.self)
        #expect(text.contains("struct BetterType"))
        #expect(text.contains("var customState:"))
        #expect(text.contains(#"case renamed = "wire_key""#))
        #expect(text.contains("static let bad = State(rawValue: -1)"))
        #expect(text.contains("static let good = State(rawValue: 2)"))
        for (schema, pointer) in [
            ("Value: {type: string, x-swift-name: 42}", "/components/schemas/Value/x-swift-name"),
            (
                "Value: {type: string, enum: [a, b], x-enum-varnames: [ONE]}",
                "/components/schemas/Value/x-enum-varnames"
            ),
            (
                "Value: {type: string, enum: [a], x-enum-varnames: ['not-valid']}",
                "/components/schemas/Value/x-enum-varnames/0"
            ),
        ] {
            let invalid = generate(schema)
            #expect(invalid.hasErrors && invalid.diagnostics.contains { $0.pointer == pointer })
        }
    }

    @Test func parameterNameFailuresRetainTheirInventoryPointer() {
        let spec = """
            openapi: 3.1.0
            info: {title: Located names, version: 1.0.0}
            servers: [{url: 'https://example.com'}]
            paths:
              /test:
                get:
                  parameters:
                    - {name: '---', in: query, schema: {type: string}}
                  responses: {'204': {description: Empty}}
            """
        let result = Generator.generate(
            spec: Data(spec.utf8), stem: "Located", specPath: "Located.yaml")
        #expect(result.hasErrors)
        #expect(
            result.diagnostics.contains {
                $0.pointer == "/paths/~1test/get/parameters/0" && $0.line == 8
                    && $0.message.contains("no ASCII identifier")
            })
    }

    @Test func routeAliasesReachParametersAndInlinePayloads() {
        let spec = """
            openapi: 3.1.0
            info: {title: Aliases, version: 1.0.0}
            servers: [{url: 'https://example.com'}]
            paths:
              /test:
                post:
                  operationId: create
                  parameters: [{name: id, in: query, schema: {type: string, enum: [IN_PROGRESS]}}]
                  requestBody:
                    required: true
                    content: {application/json: {schema: {type: object, properties: {wire_key: {type: string}}}}}
                  responses:
                    '200': {description: OK, content: {application/json: {schema: {type: object, properties: {value: {type: string}}}}}}
            """
        let route = OperationID.route(method: .post, path: "/test")
        let config = EndpointsConfiguration(renames: [
            .operation("create"): "Date",
            .parameter("id", in: .query, of: route): "identifier",
            .type(.inline(.parameter("id", in: .query, of: route))): "QueryState",
            .type(.inline(.body(route))): "Input",
            .type(.inline(.response(route, status: "200"))): "Output",
        ])
        let result = Generator.generate(
            spec: Data(spec.utf8), configuration: config, stem: "Aliases", specPath: "Aliases.yaml")
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics)")
        let text = result.files.map { String(decoding: $0.bytes, as: UTF8.self) }.joined()
        for name in [
            "struct DateEndpoint", "struct Input", "struct Output", "struct QueryState",
            "var identifier:",
        ] {
            #expect(text.contains(name), "Missing \(name)")
        }
    }

    @Test func inventoryResolutionIsIndependentOfRequestOrder() throws {
        let (loaded, _) = Loader.load(
            try Data(contentsOf: fixture("NamingConfigured")), path: "NamingConfigured.yaml")
        let document = try #require(loaded)
        let (config, errors) = Configuration.load(
            try Data(contentsOf: fixture("NamingConfigured", ".configuration.json")),
            path: "Config.json")
        #expect(errors.isEmpty)
        var inventory = NameInventory(
            document: document.document, source: document.source, config: config)
        inventory.collect()
        #expect(inventory.diagnostics.isEmpty)
        let resolver = DeclarativeNameResolver()
        let source = Source(path: "Config.json", root: nil)
        let normal = resolver.resolve(inventory.requests, config: config, source: source)
        let shuffled = resolver.resolve(
            inventory.requests.reversed(), config: config, source: source)
        #expect(normal.values == shuffled.values)
        #expect(normal.diagnostics.isEmpty && shuffled.diagnostics.isEmpty)
        #expect(
            inventory.requests.contains {
                $0.target
                    == .type(.inline(.items(of: .inline(.property("tags", in: "pet_record")))))
            })
        #expect(
            inventory.requests.contains {
                $0.target
                    == .parameter(
                        "id", in: .query, of: .route(method: .get, path: "/pets/{pet_id}"))
            })
        #expect(
            inventory.requests.contains {
                $0.target
                    == .parameter(
                        "id", in: .header, of: .route(method: .get, path: "/pets/{pet_id}"))
            })
    }

    @Test func wireValuesSurviveEveryNamingStrategy() throws {
        let (loaded, _) = Loader.load(
            try Data(contentsOf: fixture("NamingConfigured")), path: "NamingConfigured.yaml")
        let document = try #require(loaded)
        let (base, _) = Configuration.load(
            try Data(contentsOf: fixture("NamingConfigured", ".configuration.json")),
            path: "Config.json")
        var snapshots: [[Data]] = []
        for strategy in [NamingStrategy.camelCase, .upperCamelCase, .verbatim] {
            var config = base
            config.settings.typeNamingStrategy = .upperCamelCase
            config.settings.propertyNamingStrategy = strategy
            config.settings.parameterNamingStrategy = strategy
            config.settings.enumCaseNamingStrategy = strategy
            var inventory = NameInventory(
                document: document.document, source: document.source, config: config)
            inventory.collect()
            let resolutions = DeclarativeNameResolver().resolve(
                inventory.requests, config: config, source: Source(path: "Config.json", root: nil))
            var lowering = Lowering(
                document: document.document, source: document.source,
                configSource: Source(path: "Config.json", root: nil), config: config,
                namespace: "NamingConfigured", resolutions: resolutions)
            let module = lowering.lower()
            #expect(lowering.diagnostics.isEmpty)
            var wires: [String] = []
            func visit(_ declaration: TypeDecl) {
                wires += declaration.properties.map(\.wire)
                wires += declaration.values.map(\.raw)
                for child in declaration.nested { visit(child) }
            }
            for schema in module.schemas { visit(schema) }
            for endpoint in module.endpoints {
                wires +=
                    endpoint.pathParams.map(\.wire) + endpoint.queryParams.map(\.wire)
                    + endpoint.headerParams.map(\.wire)
                wires += endpoint.fixedHeaders.map(\.name)
                for child in endpoint.nested { visit(child) }
            }
            snapshots.append(wires.sorted(by: utf8Less).map { Data($0.utf8) })
        }
        #expect(snapshots[0] == snapshots[1] && snapshots[1] == snapshots[2])
    }
}
