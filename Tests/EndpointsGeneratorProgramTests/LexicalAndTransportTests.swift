#if OpenAPIGenerator
import EndpointsGeneratorConfig
import Foundation
import Testing
@testable import EndpointsGeneratorCore
@testable import endpoints_generate

@Suite struct LexicalAndTransportTests {
    let header = "// endpoints-configuration-version: 1\nimport EndpointsGeneratorConfig\n"
    let entry = "\nlet petsConfiguration = EndpointsConfiguration()\n"
    func issues(_ body: String) -> [ConfigIssue] {
        ConfigLexicalCheck.check(Data((header + body + entry).utf8), stem: "Pets")
    }
    @Test func lexerSeparatesLiteralTextFromExecutableChannels() {
        let banned =
            "import Foundation #if #file #sourceLocation @_cdecl UnsafePointer ObjectIdentifier Int.random MemoryLayout CommandLine shuffle shuffled readLine ContinuousClock Task async await @unchecked _stdlib_isOSVersionAtLeast Unmanaged OpaquePointer withCString withUTF8 withContiguousStorageIfAvailable withVaList Mirror Hasher hashValue hash(into: class actor === !=="
        let literals = [
            "// " + banned + "\n",
            "/* " + banned + " /* nested */ */",
            "let ignored = \"" + banned + "\"",
            "let ignored = \"\"\"\n" + banned + "\n\"\"\"",
            "let ignored = #\"" + banned + "\"#",
            "let ignored = ##\"\"\"\n" + banned + "\n\"\"\"##",
            "let ignored = ###\"" + banned + "\"###",
            #"let ignored = "outer \("import Foundation #file") end""#,
        ]
        for source in literals { #expect(issues(source).isEmpty, "\(source): \(issues(source))") }
        for source in [
            "import Foundation", "import struct Foundation.Data",
            "import EndpointsGeneratorConfig.Other", "#if os(Linux)\n#endif", "#file",
            "#available(macOS 13, *)", "@_cdecl(\"f\") func f() {}",
            "@ /* comment */ _silgen_name(\"getpid\") func processID() -> Int32",
            "@\n_cdecl(\"f\") func f() {}", "let x = UnsafePointer<Int>.self",
            "let x = ObjectIdentifier.self", "let x = Int.random(in: 1...2)",
            "let x = MemoryLayout<Int>.size", "let x = CommandLine.arguments", "let x = readLine()",
            "let x = [1, 2].shuffled()", "var x = [1, 2]; x.shuffle()",
            "let x = ContinuousClock.now", "Task.detached {}", "let x = Unmanaged.self",
            "let x = OpaquePointer.self",
            "let x = \"text\".withCString { String(UInt(bitPattern: $0)) }",
            "var x = \"text\"; x.withUTF8 { _ in }",
            "let x = [1].withContiguousStorageIfAvailable { _ in }", "withVaList([]) { _ in }",
            "let x = Mirror(reflecting: 1)", "let x = _stdlib_isOSVersionAtLeast",
            "func f() async {}",
            "let x = await f()", "final class Box: @unchecked Sendable {}",
            #"let x = "\(#filePath)""#,
        ] {
            #expect(!issues(source).isEmpty, "Missed executable channel: \(source)")
            #expect(issues(source).first?.line == 3)
        }
        #expect(issues("// café\n  #line").first?.line == 4)
        #expect(issues("  #line").first?.column == 3)
    }
    @Test func regexKeyPathsAndIdentityChannelsAreRejected() {
        for source in [#"_ = /"/"#, #"_ = /x\//"#, #"_ = /[/*]/"#] {
            #expect(issues(source).first == ConfigIssue(
                line: 3, column: 5,
                message: "regex literals are not allowed in configuration files; put spaces around '/' for division"))
        }
        #expect(issues("let value = total/2").first?.message
            == "regex literals are not allowed in configuration files; put spaces around '/' for division")
        #expect(issues(#"let key = \Box.computed"#).first == ConfigIssue(
            line: 3, column: 11,
            message: "key-path expressions are not allowed in configuration files"))
        for name in [
            "ObjectIdentifier", "Unmanaged", "MemoryLayout", "Mirror", "Hasher", "hashValue",
            "CommandLine", "unsafeBitCast", "UnsafeBufferPointer", "withUnsafeBytes",
        ] {
            #expect(issues("let value = \(name)").first?.message
                == "'\(name)' is not allowed in configuration files")
        }
        for source in ["value.hash(into: &state)", "value.`hash`(`into`: &state)"] {
            #expect(issues(source).first?.message
                == "'hash(into:)' is not allowed in configuration files")
        }
        for source in [
            "class Box {}", "actor Box {}", "class `Box` {}", "actor `Box` {}", "class 🐕 {}",
        ] {
            #expect(issues(source).first?.message
                == "reference-type declarations are not allowed in configuration files")
        }
        for op in ["===", "!=="] {
            #expect(issues("left \(op) right").first?.message
                == "identity operators are not allowed in configuration files")
        }
        for source in [
            "let quotient = a / b; value /= 2", "struct Box { let name: String }",
            "enum State { case ready }; func name(_ text: String) -> String { text + text }",
            "let actor = 1; func hash(_ value: Int) -> Int { value }",
            "for actor in actors { print(actor) }", "enum Kind { case `class`, actor }",
            "enum Kind { case `class`\nfunc text() -> String { \"value\" } }",
            "let kind = Kind.`class`; var actor = 1",
            #"let text = "Hasher hashValue hash(into: class actor === !== \\Box.value /[/*]/""#,
            #"// \Box.value /"/ class Hasher"#,
            #"/* /[/*]/ Hasher hashValue */ */"#,
        ] {
            #expect(issues(source).isEmpty, "Rejected reasonable config: \(source)")
        }
    }
    @Test func coreAndConfigProgramShareGlobSemantics() {
        let cases: [(String, String, Bool)] = [
            ("", "", true), ("", "x", false), ("*", "", true), ("**", "x/y", true),
            ("*", "*suffix", true), ("a*b", "a*middleb", true),
            ("GET /*", "GET /pets/42", true), ("GET /*", "POST /pets", false),
            ("get*Pet", "getLostPet", true), ("a*b*c", "axbybc", true),
            ("a*b", "ac", false), ("a?b", "acb", false), ("a?b", "a?b", true),
            ("[ab]", "a", false), ("é*", "é東京", true), ("é", "e\u{301}", false),
            ("get*", "GETpets", false), ("*/*", "x/y/z", true),
        ]
        for (pattern, value, expected) in cases {
            #expect(matchesGlob(pattern, value) == expected, "Core: \(pattern), \(value)")
            #expect(_EndpointsConfigTransport.matches(pattern, value) == expected,
                "Config: \(pattern), \(value)")
        }
    }
    @Test func headersAndEntryDeclarationsAreLocated() {
        let missing = ConfigLexicalCheck.check(Data("let petsConfiguration = 1".utf8), stem: "Pets")
        #expect(missing.first?.line == 1 && missing.first?.message.contains("first line") == true)
        #expect(
            ConfigLexicalCheck.check(Data((header + "let other = 1").utf8), stem: "Pets").contains {
                $0.message.contains("exactly one")
            })
        let duplicates = ConfigLexicalCheck.check(
            Data((header + "let petsConfiguration = 1\nlet petsConfiguration = 2").utf8),
            stem: "Pets")
        #expect(duplicates.map(\.line) == [3, 4])
        #expect(issues("func f() { let petsConfiguration = 1 }").isEmpty)
        #expect(ConfigLexicalCheck.entrySymbol(stem: "API") == "apiConfiguration")
    }
    @Test func protocolRoundTripsIdentitiesAndRejectsBrokenFrames() throws {
        let op = OperationID.route(method: .get, path: "/café/{id}")
        let targets: [NameTarget] = [
            .type("Pet"), .property("", in: "Pet"), .enumCase("\t\r\n\\東京", in: "Pet"),
            .operation(op), .parameter("id", in: .header, of: op), .environment("Production US"),
            .type(.inline(.items(of: .inline(.property("tags", in: "Pet"))))),
            .type(.inline(.parameter("id", in: .query, of: op))), .type(.inline(.body(op))),
            .type(.inline(.response(op, status: "200"))),
            .type(.inline(.errorResponse(op, status: "default"))),
        ]
        let records = (0..<10_000).map { i in
            _EndpointsConfigTransport.Record(
                target: targets[i % targets.count], wire: "\t\r\n\\café東京\(i)",
                spec: i % 2 == 0 ? "" : nil, integer: nil, operationID: nil, route: nil)
        }
        let encoded = _EndpointsConfigTransport.request(records)
        let decoded = try _EndpointsConfigTransport.readRequest(encoded)
        #expect(decoded.count == records.count)
        for (a, b) in zip(records, decoded) {
            #expect(a.target == b.target && a.wire == b.wire && a.spec == b.spec)
        }
        let names: [String?] = [nil, "", "\r\t\n\\東京"]
        let response = _EndpointsConfigTransport.response(names, json: "{\"version\":1}", fingerprint: "abc")
        let parsed = try _EndpointsConfigTransport.readResponse(response, count: 3, fingerprint: "abc")
        #expect(parsed.0 == "{\"version\":1}" && parsed.1 == names)
        for broken in [
            response.replacingOccurrences(of: "abc", with: "def"), String(response.dropLast(6)),
            response.replacingOccurrences(of: "end 3", with: "end 4"),
            response.replacingOccurrences(of: "1\t", with: "9\t"),
        ] {
            #expect(throws: (any Error).self) {
                try _EndpointsConfigTransport.readResponse(broken, count: 3, fingerprint: "abc")
            }
        }
        #expect(throws: (any Error).self) { try _EndpointsConfigTransport.unfield("=\\q") }
    }
    @Test func declarativeDumpFeedsThePrivateCoreReader() {
        let settings = EndpointsConfiguration(
            namespace: "Pets", accessLevel: .public,
            server: .environments([.production: "https://example.com"], default: .production),
            operations: .init(include: ["GET /*"], exclude: ["delete*"]), enums: .closed,
            strict: false,
            enumCaseNamingStrategy: .custom { $0.verbatim }, acronyms: ["ID"],
            renames: [
                .type(.inline(.items(of: "Pet"))): "Item", .enumCase("a\r\n", in: "Pet"): "value",
            ])
        let (value, diagnostics) = Configuration.load(
            Data(_EndpointsConfigTransport.dump(settings).utf8), path: "transport", allowCustom: true)
        #expect(diagnostics.isEmpty)
        #expect(
            value.namespace == "Pets" && value.accessLevel == .public && value.closedEnums
                && !value.strict)
        #expect(value.environments.first?.url == "https://example.com")
        #expect(value.settings.renames == settings.renames)
        #expect(value.settings.enumCaseNamingStrategy.kind == .custom)
    }
}
#endif
