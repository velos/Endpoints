import EndpointsGeneratorConfig
import Testing

@Suite struct NamingTests {
    struct Row: Sendable {
        let wire: String
        let target: NameTarget
        let expected: String?
        let acronyms: String?
        let verbatim: String?
        init(
            _ wire: String, type: Bool = false, enumCase: Bool = false, target: NameTarget? = nil,
            _ expected: String?, _ acronyms: String?, _ verbatim: String?
        ) {
            self.wire = wire
            self.target =
                target
                ?? (type
                    ? .type("Pet")
                    : enumCase ? .enumCase(wire, in: "Status") : .property(wire, in: "Pet"))
            self.expected = expected
            self.acronyms = acronyms
            self.verbatim = verbatim
        }
    }
    static let rows: [Row] = [
        Row("Petstore", type: true, "Petstore", "Petstore", "Petstore"),
        Row("pet_record", type: true, "PetRecord", "PetRecord", "pet_record"),
        Row("HTTPStatus", type: true, "HTTPStatus", "HTTPStatus", "HTTPStatus"),
        Row("HTTPStatus", "httpStatus", "httpStatus", "HTTPStatus"),
        Row("HTTP2Status", type: true, "HTTP2Status", "HTTP2Status", "HTTP2Status"),
        Row("HTTP2Status", "http2Status", "http2Status", "HTTP2Status"),
        Row("UTF8String", "utf8String", "utf8String", "UTF8String"),
        Row("2FA", enumCase: true, "_2fa", "_2fa", "_2FA"),
        Row("OAuth2Token", "oAuth2Token", "oAuth2Token", "OAuth2Token"),
        Row("OAuth2Token", type: true, "OAuth2Token", "OAuth2Token", "OAuth2Token"),
        Row("v2Beta", "v2Beta", "v2Beta", "v2Beta"),
        Row("v2Beta", type: true, "V2Beta", "V2Beta", "v2Beta"),
        Row("42 pets", "_42Pets", "_42Pets", "_42_pets"),
        Row("myHTTPStatus", "myHTTPStatus", "myHTTPStatus", "myHTTPStatus"),
        Row("myHTTPStatus", type: true, "MyHTTPStatus", "MyHTTPStatus", "myHTTPStatus"),
        Row("aB", "aB", "aB", "aB"),
        Row("aB", type: true, "AB", "AB", "aB"),
        Row("_", type: true, nil, nil, nil),
        Row("Self", type: true, nil, nil, nil),
        Row("Any", type: true, nil, nil, nil),
        Row("Protocol", type: true, nil, nil, nil),
        Row("HTTP_2_STATUS", "http2Status", "http2Status", "HTTP_2_STATUS"),
        Row("iOS_version", "iOSVersion", "iOSVersion", "iOS_version"),
        Row("iOS_version", type: true, "IOSVersion", "IOSVersion", "iOS_version"),
        Row("owner_name", "ownerName", "ownerName", "owner_name"),
        Row("user_id", "userId", "userID", "user_id"),
        Row("userID", "userID", "userID", "userID"),
        Row("userID", type: true, "UserID", "UserID", "userID"),
        Row("user_IDs", "userIDs", "userIDs", "user_IDs"),
        Row("image_url", "imageUrl", "imageURL", "image_url"),
        Row("url_string", "urlString", "urlString", "url_string"),
        Row("fooBar_bazQux", "fooBarBazQux", "fooBarBazQux", "fooBar_bazQux"),
        Row("__private", "`private`", "`private`", "__private"),
        Row("public", "`public`", "`public`", "`public`"),
        Row("public", enumCase: true, "`public`", "`public`", "`public`"),
        Row("public", type: true, "Public", "Public", nil),
        Row("class", "`class`", "`class`", "`class`"),
        Row(
            "X-Request-ID", target: .parameter("X-Request-ID", in: .header, of: "getPet"),
            "xRequestID", "xRequestID", "X_Request_ID"),
        Row(
            "page_size", target: .parameter("page_size", in: .query, of: "getPet"), "pageSize",
            "pageSize", "page_size"),
        Row(
            "pet_id", target: .parameter("pet_id", in: .path, of: "getPet"), "petId", "petID",
            "pet_id"),
        Row("IN_PROGRESS", enumCase: true, "inProgress", "inProgress", "IN_PROGRESS"),
        Row("on-hold", enumCase: true, "onHold", "onHold", "on_hold"),
        Row("2fa_required", enumCase: true, "_2faRequired", "_2faRequired", "_2fa_required"),
        Row("Sold", enumCase: true, "sold", "sold", "Sold"),
        Row("", enumCase: true, "empty", "empty", "empty"),
        Row("a.b", enumCase: true, "aB", "aB", "a_b"),
        Row("a..b", enumCase: true, "aB", "aB", "a__b"),
        Row("FOO BAR", enumCase: true, "fooBar", "fooBar", "FOO_BAR"),
        Row("URLString", enumCase: true, "urlString", "urlString", "URLString"),
        Row("v2", enumCase: true, "v2", "v2", "v2"),
        Row("---", enumCase: true, "empty", "empty", "___"),
        Row("東京", enumCase: true, "empty", "empty", nil),
        Row("東京", type: true, nil, nil, nil),
        Row(
            "Production US", target: .environment("Production US"), "productionUS", "productionUS",
            "Production_US"),
        Row("Type", type: true, nil, nil, nil),
        // Precision beyond the table: acronym entries never match an interior substring.
        Row("IDs", "iDs", "iDs", "IDs"),
        Row("URLs", "urLs", "urLs", "URLs"),
        Row("fooébar", "fooBar", "fooBar", "foo_bar"),
    ]
    @Test(arguments: rows) func referenceTable(_ row: Row) throws {
        for (acronyms, expected) in [([], row.expected), (["ID", "URL", "HTTP"], row.acronyms)] {
            let context = NameContext(target: row.target, wireName: row.wire, acronyms: acronyms)
            let strategy: NamingStrategy = row.target.isType ? .upperCamelCase : .camelCase
            let candidate = strategy.name(for: context)
            let actual = candidate.flatMap { try? Naming.validated($0, isType: row.target.isType) }
            #expect(actual == expected, "\(row.wire), \(acronyms)")
        }
        let value = NameContext(target: row.target, wireName: row.wire).verbatim
        #expect(
            value.flatMap { try? Naming.validated($0, isType: row.target.isType) } == row.verbatim)
    }
    @Test func frozenKeywordSet() {
        // The reference contract includes language and contextual keywords, plus Type/Protocol.
        let expected: Set<String> = [
            "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
            "import", "init", "inout", "internal", "let", "open", "operator", "private",
            "precedencegroup", "protocol", "public", "rethrows", "static", "struct", "subscript",
            "typealias", "var", "break", "case", "continue", "default", "defer", "do", "else",
            "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch", "where",
            "while",
            "as", "Any", "catch", "false", "is", "nil", "super", "self", "Self", "throw", "throws",
            "true", "try", "async", "await", "actor", "nonisolated", "isolated", "some", "any",
            "borrowing", "consuming", "consume", "copy", "each", "sending", "package", "macro",
            "distributed", "reasync", "yield", "mutating", "nonmutating", "convenience", "dynamic",
            "didSet", "willSet", "get", "set", "indirect", "lazy", "optional", "override",
            "required",
            "final", "weak", "unowned", "Type", "Protocol",
        ]
        #expect(Naming.keywords == expected)
    }

    @Test func customStrategiesAndConfigurationInitializers() {
        let config = EndpointsConfiguration(
            namespace: "PetStore", accessLevel: .public,
            enumCaseNamingStrategy: .verbatim,
            operationNamingStrategy: .custom { $0.removingPrefix("legacy_").upperCamelCased },
            acronyms: ["ID", "URL"], renames: [.property("owner_name", in: "Pet"): "owner"])
        #expect(
            config.operationNamingStrategy.name(
                for: NameContext(target: .operation("legacy_get_pet"), wireName: "legacy_get_pet"))
                == "GetPet")
        let numericString = NameContext(target: .enumCase("5", in: "Code"), wireName: "5")
        #expect(numericString.camelCased == "_5")
        #expect(numericString.upperCamelCased == "_5")
        #expect(numericString.verbatim == "_5")
        let custom = NamingStrategy.custom { $0.removingPrefix("Api").upperCamelCased }
        #expect(
            custom.name(for: NameContext(target: .type("ApiUser"), wireName: "ApiUser")) == "User")
        let configured = EndpointsConfiguration {
            $0.namespace = "X"
            $0.server = .environments([.production: "https://h"], default: .production)
        }
        #expect(configured.namespace == "X")
        let ctx = NameContext(target: .type("Api"), wireName: "Api")
        #expect(ctx.removingPrefix("Api").wireName == "Api")
        #expect(ctx.removingSuffix("Api").wireName == "Api")
        #expect(ctx.replacing("UserRecord").removingSuffix("Record").upperCamelCased == "User")
        let named = NameContext(
            target: .type("wire"), wireName: "wire", specName: "ApiApiUserRecord", acronyms: ["ID"])
        let stripped = named.removingPrefix("Api")
        #expect(stripped.wireName == "ApiUserRecord" && stripped.specName == nil)
        #expect(stripped.target == named.target && stripped.acronyms == ["ID"])
        #expect(named.removingPrefix("api").specName == "ApiApiUserRecord")
        #expect(named.removingSuffix("record").specName == "ApiApiUserRecord")
        #expect(named.removingSuffix("Record").wireName == "ApiApiUser")
        #expect(named.removingSuffix("Record").specName == nil)
        #expect(named.replacing("user_id").specName == nil)
        #expect(named.replacing("user_id").camelCased == "userID")
        #expect(named.lowercasedASCII("Iİ東京") == "iİ東京")
        #expect(named.uppercasedASCII("iİ東京") == "Iİ東京")
    }
    @Test func configurationDefaultsCoverAllSettingsAndStrategies() {
        let configs = [EndpointsConfiguration(), EndpointsConfiguration { _ in }]
        for config in configs {
            #expect(config.namespace == nil)
            #expect(config.accessLevel == .internal)
            if case .fromSpec = config.server {} else { Issue.record("Expected servers from spec") }
            #expect(config.operations.include == ["*"])
            #expect(config.operations.exclude.isEmpty)
            #expect(config.enums == .extensible)
            #expect(config.strict)
            #expect(config.acronyms.isEmpty)
            #expect(config.renames.isEmpty)
            let strategies: [(NamingStrategy, NameTarget, String?)] = [
                (config.typeNamingStrategy, .type("pet_record"), "PetRecord"),
                (config.propertyNamingStrategy, .property("pet_record", in: "Pet"), "petRecord"),
                (
                    config.parameterNamingStrategy,
                    .parameter("pet_record", in: .query, of: "getPet"), "petRecord"
                ),
                (config.enumCaseNamingStrategy, .enumCase("pet_record", in: "Status"), "petRecord"),
                (config.operationNamingStrategy, .operation("pet_record"), "PetRecord"),
                (config.environmentNamingStrategy, .environment("pet_record"), "petRecord"),
            ]
            for (strategy, target, expected) in strategies {
                #expect(
                    strategy.name(for: NameContext(target: target, wireName: "pet_record"))
                        == expected)
                let empty = NameContext(target: target, wireName: "---")
                #expect(strategy.name(for: empty) == (target.isEnumCase ? "empty" : nil))
            }
        }
    }

    @Test func operationFallbackConstructionAndSuffix() throws {
        for (id, expected, acronym, verbatim) in [
            ("get_pet_by_id", "GetPetByIdEndpoint", "GetPetByIDEndpoint", "get_pet_by_idEndpoint"),
            (
                Naming.fallbackOperationName(method: .get, path: "/pets/{pet_id}"),
                "GetPetsByPetIdEndpoint", "GetPetsByPetIDEndpoint", "get__pets__By_pet_id_Endpoint"
            ),
            (
                Naming.fallbackOperationName(method: .get, path: "/pets/{pet_id}/photos.json"),
                "GetPetsByPetIdPhotosJsonEndpoint", "GetPetsByPetIDPhotosJsonEndpoint",
                "get__pets__By_pet_id__photos_jsonEndpoint"
            ),
        ] {
            let target = NameTarget.operation("op")
            #expect(
                NameContext(target: target, wireName: id).upperCamelCased.map { $0 + "Endpoint" }
                    == expected)
            #expect(
                NameContext(target: target, wireName: id, acronyms: ["ID", "URL", "HTTP"])
                    .upperCamelCased.map { $0 + "Endpoint" } == acronym)
            #expect(
                NameContext(target: target, wireName: id).verbatim.map { $0 + "Endpoint" }
                    == verbatim)
        }
        #expect(
            Naming.tokens("HTTP2Status UTF8String v2") == [
                "HTTP2", "Status", "UTF8", "String", "v2",
            ])
    }
    @Test func structuredIdentityUsesWireBytes() {
        let a = NameTarget.property("Caf\u{e9}", in: "Pet")
        let b = NameTarget.property("Cafe\u{301}", in: "Pet")
        #expect(a != b)
        #expect([a: "one", b: "two"].count == 2)
        #expect(TypeID.component("Order.status") != .inline(.property("status", in: "Order")))
        #expect(
            NameTarget.parameter("id", in: .path, of: "getPet")
                != .parameter("id", in: .query, of: "getPet"))
    }
}
