#if OpenAPIGenerator
import Dispatch
import EndpointsGeneratorConfig
import EndpointsGeneratorCore
import Foundation
import Testing
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@testable import endpoints_generate

func programFixture(_ stem: String, _ suffix: String) -> URL {
    Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(stem)/\(stem)\(suffix)")
}
func programScratch() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "EndpointsConfigTests-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}
func configFile(
    _ root: URL, body: String = "EndpointsConfiguration(accessLevel: .public)",
    stem: String = "Pets"
) throws -> URL {
    let file = root.appendingPathComponent(stem + ".endpoints.swift")
    try Data(
        "// endpoints-configuration-version: 1\nimport EndpointsGeneratorConfig\nlet \(ConfigLexicalCheck.entrySymbol(stem: stem)) = \(body)\n"
            .utf8
    ).write(to: file)
    return file
}
func evaluate(_ program: ConfigProgram, spec: Data, stem: String = "Pets") throws
    -> GenerationResult
{
    try Generator.generate(
        spec: spec, swiftConfiguration: program.source, stem: stem, specPath: stem + ".yaml",
        configurationPath: program.path.path, evaluate: program.evaluate)
}
let simpleProgramSpec = Data(
    """
    openapi: 3.1.0
    info: {title: Config program, version: 1.0.0}
    servers: [{url: 'https://example.com'}]
    paths:
      /pets:
        get:
          operationId: legacy_get_pets
          parameters: [{name: pet_id, in: query, schema: {type: string}}]
          responses: {'204': {description: Empty}}
    """.utf8)

@Suite struct ConfigProgramTests {
    @Test func identityProbesAreCachedRestoredAndInvalidated() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try configFile(root)
        let original = try ConfigProgram(
            path: path, stem: "Pets", swiftc: nil, cache: root.appendingPathComponent("original"))
        let wrapper = root.appendingPathComponent("swiftc")
        let counter = root.appendingPathComponent("versions")
        func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let script = "#!/bin/sh\nif [ \"$1\" = --version ]; then printf x >> \(quote(counter.path)); fi\nexec \(quote(original.compiler.path)) \"$@\"\n"
        try Data(script.utf8).write(to: wrapper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        let cache = root.appendingPathComponent("cache")
        let first = try ConfigProgram(path: path, stem: "Pets", swiftc: wrapper, cache: cache)
        let second = try ConfigProgram(path: path, stem: "Pets", swiftc: wrapper, cache: cache)
        #expect(first.compilerIdentity == second.compilerIdentity && first.sdkFlags == second.sdkFlags)
        #expect(try String(contentsOf: counter, encoding: .utf8) == "x")
        let restored = root.appendingPathComponent("restored")
        try FileManager.default.copyItem(at: cache, to: restored)
        _ = try ConfigProgram(path: path, stem: "Pets", swiftc: wrapper, cache: restored)
        #expect(try String(contentsOf: counter, encoding: .utf8) == "x")
        try Data((script + "# changed compiler metadata\n").utf8).write(to: wrapper)
        _ = try ConfigProgram(path: path, stem: "Pets", swiftc: wrapper, cache: cache)
        #expect(try String(contentsOf: counter, encoding: .utf8) == "xx")
        // Touching a compiler without changing its size must also invalidate the probes.
        let date = Date().addingTimeInterval(5)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: wrapper.path)
        _ = try ConfigProgram(path: path, stem: "Pets", swiftc: wrapper, cache: cache)
        #expect(try String(contentsOf: counter, encoding: .utf8) == "xxx")
        let spec = root.appendingPathComponent("Pets.openapi.yaml")
        try simpleProgramSpec.write(to: spec)
        #if os(Linux)
        let developer = "/tmp"
        #else
        let sdk = try #require(original.sdkFlags.last)
        let developer = sdk.components(separatedBy: "/Platforms/")[0]
        #endif
        for run in 0..<2 {
            var environment = ProcessInfo.processInfo.environment
            environment["DEVELOPER_DIR"] = developer + String(repeating: "/.", count: run + 2)
            let result = try ConfigProcessRunner().run(
                programCLI(), arguments: [
                    "generate", "--spec", spec.path, "--stem", "Pets", "--config-swift", path.path,
                    "--swiftc", wrapper.path, "--config-cache", cache.path,
                    "--output-dir", root.appendingPathComponent("out").path,
                ], directory: root.appendingPathComponent("developer\(run)"),
                environment: environment, timeout: 60)
            try #require(result.status == 0, "\(result.text(result.stderr))")
            #expect(try String(contentsOf: counter, encoding: .utf8).count == run + 4)
        }
    }
    @Test func swiftConfigGoldenMatchesTypedConfiguration() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = programFixture("Naming", ".endpoints.swift")
        let spec = try Data(contentsOf: programFixture("Naming", ".openapi.yaml"))
        let program = try ConfigProgram(path: path, stem: "Naming", swiftc: nil, cache: root)
        let actual = try evaluate(program, spec: spec, stem: "Naming")
        let typed = EndpointsConfiguration(
            accessLevel: .public, enumCaseNamingStrategy: .verbatim,
            operationNamingStrategy: .custom { $0.removingPrefix("legacy_").upperCamelCased },
            acronyms: ["ID", "URL"],
            renames: [
                .type("Date"): "CalendarDate", .type("東京"): "Tokyo",
                .property("owner_name", in: "pet_record"): "owner",
                .type(.inline(.property("status", in: "pet_record"))): "OrderStatus",
                .enumCase("IN_PROGRESS", in: .inline(.property("status", in: "pet_record"))):
                    "working",
                .parameter("id", in: .query, of: .route(method: .get, path: "/pets/{pet_id}")):
                    "queryIdentifier",
                .parameter("id", in: .header, of: .route(method: .get, path: "/pets/{pet_id}")):
                    "headerIdentifier",
                .environment("Production US"): "production",
            ])
        let expected = Generator.generate(
            spec: spec, configuration: typed, stem: "Naming", specPath: "Naming.yaml",
            configurationSource: program.source)
        #expect(actual.diagnostics.isEmpty, "\(actual.diagnostics)")
        #expect(actual.files.map(\.bytes) == expected.files.map(\.bytes))
        #expect(program.runDurations.count == 2)
        let directory = programRepository.appendingPathComponent(
            "Tests/EndpointsGeneratedGoldenTests/Naming")
        if ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" {
            try Generator.write(actual.files, to: directory)
        }
        for file in actual.files {
            #expect(try Data(contentsOf: directory.appendingPathComponent(file.name)) == file.bytes)
        }
        print(
            "Naming config timings: compile=\(program.compileDuration)s run=\(program.runDuration)s verification=\(program.runDurations.last ?? 0)s"
        )
    }
    @Test func runtimeGuardRejectsLocalAndPrivateTypeDescriptions() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let header = "// endpoints-configuration-version: 1\nimport EndpointsGeneratorConfig\n"
        let operationNote = "first differing entry: .operation(\"legacy_get_pets\")"
        let bodies = [
            (#"let petsConfiguration = EndpointsConfiguration(operationNamingStrategy: .custom { _ in struct Local {}; return "\([Local()])" })"#, operationNote),
            (#"private struct Local {}; let petsConfiguration = EndpointsConfiguration(operationNamingStrategy: .custom { _ in "\([Local()])" })"#, operationNote),
            (#"let petsConfiguration: EndpointsConfiguration = { struct Local {}; return .init(namespace: "\([Local()])") }()"#, "declarative configuration differs between runs"),
        ]
        for (index, scenario) in bodies.enumerated() {
            let (body, note) = scenario
            let file = root.appendingPathComponent("Pets.endpoints.swift")
            try Data((header + body + "\n").utf8).write(to: file)
            for attempt in 0..<2 {
                let program = try ConfigProgram(
                    path: file, stem: "Pets", swiftc: nil,
                    cache: root.appendingPathComponent("cache\(index)"))
                do {
                    _ = try evaluate(program, spec: simpleProgramSpec)
                    Issue.record("Accepted an address-dependent description")
                } catch let failure as ConfigProgramFailure {
                    #expect(failure.diagnostics.first == file.path
                        + ":1:1: error: configuration program is not deterministic: two runs produced different names")
                    #expect(failure.diagnostics.contains {
                        $0 == file.path + ":1:1: note: " + note
                    })
                    #expect(program.runDurations.count == 2)
                    #expect(program.cacheHit == (attempt == 1))
                }
            }
        }
    }
    @Test func unusedRenameWarningsPointToEachAuthoredTarget() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = programFixture("Naming", ".endpoints.swift")
        let program = try ConfigProgram(path: file, stem: "Naming", swiftc: nil, cache: root)
        let spec = try Data(contentsOf: programRepository.appendingPathComponent(
            "Examples/PetstoreClient/Sources/PetstoreAPI/Petstore.openapi.yaml"))
        let result = try evaluate(program, spec: spec, stem: "Naming")
        let warnings = result.diagnostics.filter { $0.message.hasPrefix("Unused rename target ") }
        let expected: [(String, Int)] = [
            (#".type("Date")"#, 10), (#".type("東京")"#, 11),
            (#".property("owner_name", in: "pet_record")"#, 12),
            (#".type(.inline(.property("status", in: "pet_record")))"#, 13),
            (#".enumCase("IN_PROGRESS", in: .inline(.property("status", in: "pet_record")))"#, 14),
            (#".parameter("id", in: .query, of: .route(method: .get, path: "/pets/{pet_id}"))"#, 15),
            (#".parameter("id", in: .header, of: .route(method: .get, path: "/pets/{pet_id}"))"#, 16),
            (#".environment("Production US")"#, 17),
        ]
        #expect(warnings.count == expected.count)
        for (target, line) in expected {
            let diagnostic = try #require(warnings.first { $0.message == "Unused rename target " + target })
            #expect(diagnostic.line == line, "\(target): \(diagnostic)")
        }
    }
    @Test func semanticConfigErrorsPointToSwiftRenameLines() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try configFile(
            root,
            body: """
                EndpointsConfiguration(
                    renames: [
                        .operation(.route(method: .get, path: "/pets")): "class"
                    ])
                """)
        let program = try ConfigProgram(
            path: file, stem: "Pets", swiftc: nil, cache: root.appendingPathComponent("cache"))
        let result = try evaluate(program, spec: simpleProgramSpec)
        let error = try #require(result.diagnostics.first { $0.severity == .error })
        #expect(error.path == file.path && error.line == 5)
        #expect(error.message.contains("Invalid rename value"))
    }
    @Test func namingErrorsGolden() throws {
        let file = programFixture("NamingErrors", ".endpoints.swift")
        let diagnostics =
            ConfigLexicalCheck.check(try Data(contentsOf: file), stem: "NamingErrors")
            .map { $0.formatted(path: file.lastPathComponent) }.joined(separator: "\n") + "\n"
        let expected = programRepository.appendingPathComponent(
            "Tests/EndpointsGeneratorProgramTests/Fixtures/NamingErrors/diagnostics.txt")
        if ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" {
            try Data(diagnostics.utf8).write(to: expected)
        }
        #expect(try String(contentsOf: expected, encoding: .utf8) == diagnostics)
    }
    @Test func cacheHitRestorationAndCorruption() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try configFile(
            root,
            body:
                "EndpointsConfiguration(operationNamingStrategy: .custom { context in print(\"stdout is not protocol\"); return context.removingPrefix(\"legacy_\").upperCamelCased })"
        )
        let cache = root.appendingPathComponent("cache")
        let first = try ConfigProgram(path: path, stem: "Pets", swiftc: nil, cache: cache)
        let a = try evaluate(first, spec: simpleProgramSpec)
        #expect(!first.cacheHit && !a.hasErrors)
        let second = try ConfigProgram(path: path, stem: "Pets", swiftc: nil, cache: cache)
        let b = try evaluate(second, spec: simpleProgramSpec)
        #expect(second.cacheHit && first.key == second.key)
        #expect(a.files.map(\.bytes) == b.files.map(\.bytes))
        print(
            "Cache timings: coldCompile=\(first.compileDuration)s warmCompile=\(second.compileDuration)s warmRun=\(second.runDuration)s verification=\(second.runDurations.last ?? 0)s"
        )
        let restored = root.appendingPathComponent("restored")
        try FileManager.default.copyItem(at: cache, to: restored)
        let copy = try ConfigProgram(path: path, stem: "Pets", swiftc: nil, cache: restored)
        #expect(
            try evaluate(copy, spec: simpleProgramSpec).files.map(\.bytes) == a.files.map(\.bytes))
        #expect(copy.cacheHit && copy.key == first.key)
        try Data("truncated".utf8).write(
            to: restored.appendingPathComponent("entries/\(copy.key)/config"))
        let repaired = try ConfigProgram(path: path, stem: "Pets", swiftc: nil, cache: restored)
        #expect(
            try evaluate(repaired, spec: simpleProgramSpec).files.map(\.bytes)
                == a.files.map(\.bytes))
        #expect(!repaired.cacheHit)
    }
    @Test func concurrentGenerationsPublishOneImmutableEntry() async throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try configFile(root)
        let cache = root.appendingPathComponent("cache")
        let outputs = try await withThrowingTaskGroup(of: [Data].self) { group in
            for _ in 0..<2 {
                group.addTask {
                    let program = try ConfigProgram(
                        path: path, stem: "Pets", swiftc: nil, cache: cache)
                    return try evaluate(program, spec: simpleProgramSpec).files.map(\.bytes)
                }
            }
            var values: [[Data]] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(outputs.count == 2 && outputs[0] == outputs[1])
        let entries = try FileManager.default.contentsOfDirectory(
            atPath: cache.appendingPathComponent("entries").path)
        #expect(entries.count == 1 && !entries[0].hasPrefix("."))
        #expect(
            try FileManager.default.contentsOfDirectory(
                atPath: cache.appendingPathComponent("runs").path
            ).isEmpty)
    }
    @Test func excludedNamesDoNotRunClosuresOrReportExtensionErrors() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try configFile(
            root,
            body:
                "EndpointsConfiguration(server: .type(\"CustomServer\"), operations: .init(exclude: [\"*\"]), operationNamingStrategy: .custom { _ in fatalError(\"excluded\") })"
        )
        let spec = String(decoding: simpleProgramSpec, as: UTF8.self).replacingOccurrences(
            of: "operationId: legacy_get_pets",
            with: "operationId: legacy_get_pets\n      x-swift-name: 42")
        let program = try ConfigProgram(
            path: path, stem: "Pets", swiftc: nil, cache: root.appendingPathComponent("cache"))
        let result = try evaluate(program, spec: Data(spec.utf8))
        #expect(result.diagnostics.isEmpty && result.files.count == 4)
    }
    @Test func evictionProtectsLeasesAndCleansAbandonedWork() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache")
        let path = try configFile(root)
        let first = try ConfigProgram(path: path, stem: "Pets", swiftc: nil, cache: cache)
        _ = try evaluate(first, spec: simpleProgramSpec)
        let entry = cache.appendingPathComponent("entries/\(first.key)")
        let descriptor = open(entry.appendingPathComponent("lease").path, O_RDWR | O_CLOEXEC)
        try #require(descriptor >= 0)
        defer { _ = close(descriptor) }
        try #require(flock(descriptor, LOCK_SH) == 0)
        let old = Date(timeIntervalSinceNow: -7200)
        try FileManager.default.setAttributes(
            [.modificationDate: old],
            ofItemAtPath: cache.appendingPathComponent("usage/\(first.key)").path)
        for name in ["runs/abandoned", "entries/.tmp-abandoned"] {
            let directory = cache.appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try Data("partial".utf8).write(to: directory.appendingPathComponent("partial"))
            try FileManager.default.setAttributes(
                [.modificationDate: old], ofItemAtPath: directory.path)
        }
        var last: ConfigProgram?
        for number in 1...2 {
            _ = try configFile(root, body: "EndpointsConfiguration(namespace: \"Pets\(number)\")")
            let program = try ConfigProgram(path: path, stem: "Pets", swiftc: nil, cache: cache)
            #expect(try !evaluate(program, spec: simpleProgramSpec).hasErrors)
            last = program
        }
        #expect(
            FileManager.default.fileExists(atPath: entry.path),
            "An active lease protects an old executable")
        #expect(
            !FileManager.default.fileExists(
                atPath: cache.appendingPathComponent("runs/abandoned").path)
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: cache.appendingPathComponent("entries/.tmp-abandoned").path))
        #expect(flock(descriptor, LOCK_UN) == 0)
        _ = try evaluate(#require(last), spec: simpleProgramSpec)
        #expect(!FileManager.default.fileExists(atPath: entry.path))
        #expect(
            try FileManager.default.contentsOfDirectory(
                atPath: cache.appendingPathComponent("entries").path
            ).count == 2)
    }
    @Test func cacheKeyLengthPrefixesEverySemanticInput() {
        #expect(
            ConfigProgram.identity([Data("a".utf8), Data("bc".utf8)])
                != ConfigProgram.identity([Data("ab".utf8), Data("c".utf8)]))
        let original = ConfigCacheInputs(
            config: Data("config".utf8), header: "1", dsl: "dsl", transport: "transport",
            main: "main",
            stem: "Pets", entrySymbol: "petsConfiguration", flags: ["-swift-version", "6"],
            compiler: "swiftc", sdk: "sdk", generator: "1")
        let key = original.key
        for field in [
            \ConfigCacheInputs.header, \.dsl, \.transport, \.main, \.stem, \.entrySymbol,
            \.compiler,
            \.sdk, \.generator,
        ] {
            var changed = original
            changed[keyPath: field] += "!"
            #expect(changed.key != key)
        }
        var changed = original
        changed.config.append(0)
        #expect(changed.key != key)
        changed = original
        changed.flags.append("-O")
        #expect(changed.key != key)
    }
}
#endif
