import Foundation
import Testing

@testable import EndpointsGeneratorCore

@Suite struct CoreTests {
    @Test func namingContract() throws {
        let cases: [(String, String, String)] = [
            ("HTTPStatus", "HTTPStatus", "httpStatus"), ("URL", "URL", "url"),
            ("pet-id", "PetId", "petId"), ("first_name", "First_name", "first_name"),
            ("42 pets", "_42Pets", "_42Pets"), ("aB", "AB", "aB"),
            ("fooébar", "FooBar", "fooBar"), ("class", "Class", "`class`"),
            ("myHTTPStatus", "MyHTTPStatus", "myHTTPStatus"),
        ]
        for (input, type, member) in cases {
            #expect(try Naming.name(input, style: .type) == type)
            #expect(try Naming.name(input, style: .member) == member)
        }
        #expect(throws: NameError.self) { try Naming.name("東京", style: .type) }
        #expect(throws: NameError.self) { try Naming.name("_", style: .type) }
        for name in ["Type", "Protocol", "Self", "Any", "init"] {
            #expect(throws: NameError.self) { try Naming.name(name, style: .type, rename: name) }
        }
        #expect(try Naming.name("ignored", style: .type, rename: "CalendarDate") == "CalendarDate")
        #expect(throws: NameError.self) {
            try Naming.name("ignored", style: .member, rename: "not-an-identifier")
        }
    }

    @Test func allocationRejectsReservedAndCollidingNames() throws {
        var allocator = NameAllocator(reserved: Naming.namespaceReserved)
        for name in ["Date", "Server", "JSONDecoder", "RFC3339", "Header", "EncodedPath"] {
            #expect(throws: NameError.self) {
                try allocator.claim(name, original: name, hint: renameHint(.schemas, name))
            }
        }
        try allocator.claim(
            "GetPetEndpoint", original: "get-pet", hint: renameHint(.operations, "get-pet"))
        do {
            try allocator.claim(
                "GetPetEndpoint", original: "getPet", hint: renameHint(.operations, "getPet"))
            Issue.record("Expected a collision")
        } catch let error as NameError {
            #expect(error.description.contains("get-pet"))
            #expect(error.description.contains("getPet"))
            #expect(error.description.contains(#"renames.operations["getPet"]"#))
        }
    }

    @Test func renameHintsQuoteWireIdentities() throws {
        let original = "GET /pets/{petId} \"\\\n\u{1}"
        for category in [RenameCategory.schemas, .operations, .properties] {
            let hint = renameHint(category, original)
            let prefix = "renames." + category.rawValue
            #expect(hint.hasPrefix(prefix + "["))
            let json = String(hint.dropFirst(prefix.count))
            let keys = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String]
            #expect(keys == [original])
        }
    }

    @Test func configurationIsClosedAndTyped() {
        let valid = #"""
            {
                "version": 1,
                "namespace": "Pets",
                "accessLevel": "public",
                "server": {
                    "environments": {"production": "https://example.com"},
                    "defaultEnvironment": "production"
                },
                "operations": {"include": ["GET /pets/*"], "exclude": ["delete*"]},
                "renames": {"schemas": {"Date": "CalendarDate"}},
                "enums": "closed",
                "strict": false
            }
            """#
        let (config, errors) = Configuration.load(Data(valid.utf8), path: "Config.json")
        #expect(errors.isEmpty)
        #expect(
            config.namespace == "Pets" && config.accessLevel == .public && !config.strict
                && config.closedEnums)
        #expect(
            config.environments.count == 1
                && config.schemaRenames.first?.replacement == "CalendarDate")
        let invalid = [
            #"{}"#, #"{"version":2}"#, #"{"version":"1"}"#, #"{"version":true}"#,
            #"{"version":1,"strict":"false"}"#, #"{"version":1,"accessLevel":"private"}"#,
            #"{"version":1,"enums":"sometimes"}"#, #"{"version":1,"namespace":"Date"}"#,
            #"{"version":1,"server":{"type":"MyServer","environments":{}}}"#,
            #"{"version":1,"server":{"unknown":true}}"#,
            #"{"version":1,"operations":{"include":false}}"#,
            #"{"version":1,"renames":{"schemas":{"Date":"not-valid"}}}"#,
            #"{"version":1,"operations":{"wat":[]}}"#,
        ]
        for json in invalid {
            let (_, errors) = Configuration.load(Data(json.utf8), path: "Config.json")
            #expect(!errors.isEmpty, "Accepted invalid config: \(json)")
        }
        let (_, unknown) = Configuration.load(
            Data(#"{"version":1,"z":0,"a":0}"#.utf8), path: "Config.json")
        #expect(unknown.map(\.pointer) == ["/z", "/a"])  // source position precedes pointer in diagnostic ordering
        #expect(matchesGlob("GET /pets/*", "GET /pets/42"))
        #expect(!matchesGlob("delete*", "getPet"))
    }

    @Test func sha256StandardVectors() {
        let vectors = [
            ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
            ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
            (
                "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
                "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
            ),
        ]
        for (input, expected) in vectors { #expect(SHA256.hex(Array(input.utf8)) == expected) }
        #expect(
            SHA256.hex([UInt8](repeating: 97, count: 1_000_000))
                == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    @Test func textAndEscapingInvariants() {
        var writer = CodeWriter()
        writer.line()
        writer.line("enum API {  \r\n")
        writer.indent()
        writer.line("let x = 1\t ")
        writer.line()
        writer.line()
        writer.line("// hi")
        writer.outdent()
        writer.line("}")
        writer.line()
        writer.line()
        #expect(writer.finish() == "enum API {\n\n    let x = 1\n\n    // hi\n}\n")
        #expect(swiftLiteral("\u{feff}") == #""\u{feff}""#)
        #expect(swiftLiteral("a\"\\\n\t\u{0001}$(x)") == #""a\"\\\n\t\u{1}$(x)""#)
    }

    @Test func serverURLSpellingAndValidation() throws {
        for (input, expected) in [
            ("https://EXAMPLE.com/api%2fv3", "https://EXAMPLE.com/api%2fv3/"),
            ("https://h", "https://h"), ("https://h/", "https://h/"),
            ("https://user:password@h/v1", "https://user:password@h/v1/"),
            ("https://h:443/a/../b", "https://h:443/a/../b/"),
            ("https://[::1]/v1", "https://[::1]/v1/"),
        ] { #expect(try ServerURLs.normalize(input) == expected) }
        for input in [
            "/relative", "https://h/a?q=1", "https://h/#f", "https://", "ftp://h/a",
            "https://h/a b", "https://h/%GG",
        ] {
            #expect(throws: NameError.self) { try ServerURLs.normalize(input) }
        }
    }
}
