#if OpenAPIGenerator
import EndpointsGeneratorCore
import Foundation
import Testing
@testable import endpoints_generate

func programCLI() throws -> URL {
    var directory = Bundle.module.bundleURL
    var found: URL?
    for _ in 0..<6 {
        let candidate = directory.appendingPathComponent("endpoints-generate")
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            found = candidate
            break
        }
        directory = directory.deletingLastPathComponent()
    }
    return try #require(found)
}

@Suite struct HostAndProcessTests {
    @Test func configDiagnosticsPreserveTheSuppliedPathSpelling() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("Pets.endpoints.swift")
        let spec = root.appendingPathComponent("Pets.openapi.yaml")
        try simpleProgramSpec.write(to: spec)
        let warning = """
            @available(*, deprecated, message: "configuration warning probe")
            func previousConfiguration() -> EndpointsConfiguration { .init() }
            let petsConfiguration = previousConfiguration()
            """
        let scenarios: [(String, Int32, String)] = [
            ("let petsConfiguration = EndpointsConfiguration(); let value = Int.random(in: 0...1)",
                1, "'random' is not allowed"),
            ("let petsConfiguration = EndpointsConfiguration(accessLevel: 42)",
                1, ": error:"),
            ("let petsConfiguration = 42", 1, "exactly one"),
            (#"let petsConfiguration = EndpointsConfiguration(operationNamingStrategy: .custom { _ in struct Local {}; return "\([Local()])" })"#,
                1, "configuration program is not deterministic"),
            (#"let petsConfiguration = EndpointsConfiguration(renames: [.type("Absent"): "Missing"])"#,
                0, "Unused rename target"),
            (warning, 0, "configuration warning probe"),
            (warning, 0, "configuration warning probe"),  // Replay the cached warning.
        ]
        for (index, scenario) in scenarios.enumerated() {
            let (declarations, status, message) = scenario
            try Data(("// endpoints-configuration-version: 1\nimport EndpointsGeneratorConfig\n"
                + declarations + "\n").utf8).write(to: config)
            let suppliedPath = "../Pets.endpoints.swift"
            let result = try ConfigProcessRunner().run(
                programCLI(), arguments: [
                    "generate", "--spec", spec.path, "--stem", "Pets",
                    "--config-swift", suppliedPath,
                    "--output-dir", root.appendingPathComponent("out").path,
                    "--config-cache", root.appendingPathComponent("cache").path,
                ], directory: root.appendingPathComponent("run\(index)"), timeout: 60)
            let text = result.text(result.stderr)
            try #require(!result.timedOut && result.status == status, "\(text)")
            #expect(text.contains(message), "\(text)")
            let blocks = CompilerDiagnosticBlock.parse(text)
            try #require(!blocks.isEmpty, "\(text)")
            #expect(blocks.allSatisfy { $0.path == suppliedPath }, "\(text)")
            #expect(!text.contains(".tmp-"))
        }
    }
    @Test func configurationCompilesInConsumerLanguageAndIsolationModes() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = programFixture("Naming", ".endpoints.swift")
        let program = try ConfigProgram(
            path: config, stem: "Naming", swiftc: nil, cache: root.appendingPathComponent("cache"))
        let dsl = root.appendingPathComponent("EndpointsGeneratorConfig.swift")
        try Data(Embedded.dsl.utf8).write(to: dsl)
        let runner = ConfigProcessRunner()
        let library = try runner.run(
            program.compiler,
            arguments: [
                "-swift-version", "6", "-package-name", "ConfigLibrary", "-parse-as-library",
                "-emit-module", "-module-name", "EndpointsGeneratorConfig", "-emit-module-path",
                root.appendingPathComponent("EndpointsGeneratorConfig.swiftmodule").path,
                "-module-cache-path", root.appendingPathComponent("ModuleCache").path,
            ] + program.sdkFlags + [dsl.path], directory: root.appendingPathComponent("library"),
            timeout: 60)
        try #require(library.status == 0, "\(library.text(library.stderr))")
        var variants = [("Swift5", ["-swift-version", "5"]), ("Swift6", ["-swift-version", "6"])]
        #if compiler(>=6.2)
        variants.append(("MainActor", ["-swift-version", "6", "-default-isolation", "MainActor"]))
        #endif
        for (name, flags) in variants {
            let result = try runner.run(
                program.compiler,
                arguments: flags + program.sdkFlags + [
                    "-package-name", "Consumer", "-typecheck", "-warnings-as-errors", "-I",
                    root.path,
                    "-module-cache-path", root.appendingPathComponent("ModuleCache").path,
                    config.path,
                ], directory: root.appendingPathComponent(name), timeout: 60)
            #expect(
                result.status == 0 && !result.timedOut, "\(name): \(result.text(result.stderr))")
        }
    }
    @Test func compilerAndRuntimeFailuresAreActionable() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("cache")
        let invalid = try configFile(
            root, body: "EndpointsConfiguration(accessLevel: .notAnAccessLevel)")
        do {
            let program = try ConfigProgram(path: invalid, stem: "Pets", swiftc: nil, cache: cache)
            _ = try evaluate(program, spec: simpleProgramSpec)
            Issue.record("Accepted a compiler error")
        } catch let error as ConfigProgramFailure {
            #expect(error.diagnostics.joined(separator: "\n").contains(invalid.path + ":3:"))
            #expect(error.diagnostics.joined(separator: "\n").contains("notAnAccessLevel"))
        }
        let wrongType = try configFile(root, body: "42")
        try Data(
            ("// endpoints-configuration-version: 1\nimport EndpointsGeneratorConfig\n"
                + "// let petsConfiguration is declared below\n\nlet petsConfiguration = 42\n").utf8
        ).write(to: wrongType)
        do {
            let program = try ConfigProgram(
                path: wrongType, stem: "Pets", swiftc: nil, cache: cache)
            _ = try evaluate(program, spec: simpleProgramSpec)
            Issue.record("Accepted a wrong entry type")
        } catch let error as ConfigProgramFailure {
            #expect(
                error.diagnostics.contains {
                    $0.contains(wrongType.path + ":5:1:")
                        && $0.contains("let petsConfiguration: EndpointsConfiguration")
                })
        }
        let failure = try configFile(
            root, body: "EndpointsConfiguration { _ in fatalError(\"config failed\") }")
        do {
            let program = try ConfigProgram(path: failure, stem: "Pets", swiftc: nil, cache: cache)
            _ = try evaluate(program, spec: simpleProgramSpec)
            Issue.record("Accepted a failed program")
        } catch let error as ConfigProgramFailure {
            #expect(
                error.diagnostics.first?.contains("configuration program was terminated by signal")
                    == true)
            #expect(error.diagnostics.count > 1)
            #expect(error.diagnostics.dropFirst().allSatisfy { $0.hasPrefix(failure.path + ":1:1: note:") })
        }
    }
    @Test func compilerDiagnosticsStayOnTheAuthoredSource() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("Pets.endpoints.swift")
        let header = "// endpoints-configuration-version: 1\nimport EndpointsGeneratorConfig\n\n// Entry below\n"
        for declaration in [
            "let petsConfiguration = EndpointsConfiguration(accessLevel: 42)",
            "let context = NameContext(target: .type(\"A\")); let petsConfiguration = EndpointsConfiguration()",
            "let petsConfiguration = 42",
            "private let petsConfiguration = EndpointsConfiguration()",
            "let petsConfiguration = EndpointsConfiguration(",
        ] {
            try Data((header + declaration + "\n").utf8).write(to: path)
            do {
                let program = try ConfigProgram(
                    path: path, stem: "Pets", swiftc: nil,
                    cache: root.appendingPathComponent("cache"))
                _ = try evaluate(program, spec: simpleProgramSpec)
                Issue.record("Accepted invalid configuration: \(declaration)")
            } catch let failure as ConfigProgramFailure {
                let text = failure.diagnostics.joined(separator: "\n")
                #expect(!text.contains("exited with status") && !text.contains("import check"))
                #expect(!text.contains(".tmp-") && !text.contains("main.swift"))
                if declaration == "let petsConfiguration = 42"
                    || declaration.hasPrefix("private")
                {
                    let column = declaration.hasPrefix("private") ? 9 : 1
                    #expect(failure.diagnostics.filter { $0.contains(": error:") } == [
                        "\(path.path):5:\(column): error: configuration must declare exactly one 'let petsConfiguration: EndpointsConfiguration'"
                    ])
                } else {
                    #expect(!text.contains("exactly one"))
                    let headers = text.split(separator: "\n").filter {
                        $0.hasPrefix(path.path + ":") && $0.contains(": error:")
                    }
                    #expect(headers.count == 1, "\(text)")
                    #expect(failure.diagnostics.allSatisfy { $0.hasPrefix(path.path + ":") })
                }
            }
        }
    }
    @Test func userWarningsAreForwardedOnCompileAndCacheHits() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try configFile(root)
        try Data(("""
            // endpoints-configuration-version: 1
            import EndpointsGeneratorConfig
            @available(*, deprecated, message: "configuration warning probe")
            func previousConfiguration() -> EndpointsConfiguration { .init() }
            let petsConfiguration = previousConfiguration()
            """ + "\n").utf8).write(to: config)
        let spec = root.appendingPathComponent("Pets.openapi.yaml")
        try simpleProgramSpec.write(to: spec)
        var first: String?
        var cachedBinary: URL?
        var cachedDate: Date?
        for run in 0..<3 {
            if run == 1 {
                let entries = root.appendingPathComponent("cache/entries")
                let entry = try #require(FileManager.default.contentsOfDirectory(
                    at: entries, includingPropertiesForKeys: nil).first)
                let metadata = entry.appendingPathComponent("diagnostics.json")
                var diagnostics = try JSONDecoder().decode([String].self, from: Data(contentsOf: metadata))
                let alias = root.appendingPathComponent("alias")
                try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
                diagnostics = diagnostics.map {
                    $0.replacingOccurrences(of: "<configuration>",
                        with: alias.appendingPathComponent(config.lastPathComponent).path)
                }
                cachedBinary = entry.appendingPathComponent("config")
                cachedDate = try FileManager.default.attributesOfItem(
                    atPath: cachedBinary!.path)[.modificationDate] as? Date
                diagnostics.append("/deleted/.tmp-old/EndpointsGeneratorConfig.swift:205:12: note: declared here\n")
                try JSONEncoder().encode(diagnostics).write(to: metadata)
            }
            let currentConfig: URL
            if run == 2 {
                let entries = root.appendingPathComponent("cache/entries")
                let entry = try #require(FileManager.default.contentsOfDirectory(
                    at: entries, includingPropertiesForKeys: nil).first)
                let metadata = entry.appendingPathComponent("diagnostics.json")
                let diagnostics = try JSONDecoder().decode([String].self, from: Data(contentsOf: metadata))
                let alias = root.appendingPathComponent("alias/" + config.lastPathComponent).path
                try JSONEncoder().encode(diagnostics.map {
                    $0.replacingOccurrences(of: alias, with: "<configuration>")
                }).write(to: metadata)
                let restored = root.appendingPathComponent("restored")
                try FileManager.default.createDirectory(at: restored, withIntermediateDirectories: true)
                currentConfig = restored.appendingPathComponent(config.lastPathComponent)
                try FileManager.default.copyItem(at: config, to: currentConfig)
            } else { currentConfig = config }
            let result = try ConfigProcessRunner().run(
                programCLI(), arguments: [
                    "generate", "--spec", spec.path, "--stem", "Pets",
                    "--config-swift", currentConfig.path,
                    "--output-dir", root.appendingPathComponent("out").path,
                    "--config-cache", root.appendingPathComponent("cache").path,
                ], directory: root.appendingPathComponent("run\(run)"), timeout: 60)
            let text = result.text(result.stderr)
            try #require(!result.timedOut && result.status == 0, "\(text)")
            #expect(text.contains(currentConfig.path + ":5:"))
            #expect(text.contains(": warning:") && text.contains("configuration warning probe"))
            #expect(!text.contains(": error:") && !text.contains(".tmp-"))
            if let first {
                #expect(text == first.replacingOccurrences(of: config.path, with: currentConfig.path))
            } else { first = text }
            if run == 1, let cachedBinary {
                let date = try FileManager.default.attributesOfItem(
                    atPath: cachedBinary.path)[.modificationDate] as? Date
                #expect(date == cachedDate, "Restored diagnostics must be sanitized on a cache hit")
            }
        }
    }
    @Test func separateProcessesHaveIdenticalOutputAndReuseTheCache() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let cli = try programCLI()
        let spec = root.appendingPathComponent("Pets.openapi.yaml")
        try simpleProgramSpec.write(to: spec)
        let path = try configFile(
            root,
            body:
                "EndpointsConfiguration(operationNamingStrategy: .custom { _ in Set([\"B\", \"A\", \"C\"]).first })"
        )
        let cache = root.appendingPathComponent("cache")
        var outputs: [[Data]] = []
        var firstManifest: Data?
        var firstDate: Date?
        for iteration in 0..<3 {
            let output = root.appendingPathComponent("output-\(iteration)")
            var environment = ProcessInfo.processInfo.environment
            environment["SWIFT_DETERMINISTIC_HASHING"] = iteration == 1 ? "1" : nil
            environment["TZ"] = iteration == 1 ? "UTC" : "Pacific/Honolulu"
            let result = try ConfigProcessRunner().run(
                cli,
                arguments: [
                    "generate", "--spec", spec.path, "--stem", "Pets", "--output-dir", output.path,
                    "--config-swift", path.path, "--config-cache", cache.path,
                ], directory: root.appendingPathComponent("process-\(iteration)"),
                environment: environment, timeout: 90)
            try #require(result.status == 0, "\(result.text(result.stderr))")
            let files = try FileManager.default.contentsOfDirectory(
                at: output, includingPropertiesForKeys: nil
            ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            outputs.append(try files.map { try Data(contentsOf: $0) })
            let entries = try FileManager.default.contentsOfDirectory(
                at: cache.appendingPathComponent("entries"), includingPropertiesForKeys: nil)
            try #require(entries.count == 1)
            let manifest = try Data(contentsOf: entries[0].appendingPathComponent("manifest"))
            let modified =
                try FileManager.default.attributesOfItem(
                    atPath: entries[0].appendingPathComponent("config").path)[.modificationDate]
                as? Date
            if iteration == 0 {
                firstManifest = manifest
                firstDate = modified
            } else {
                #expect(manifest == firstManifest && modified == firstDate)
            }
        }
        #expect(outputs[0] == outputs[1] && outputs[1] == outputs[2])
        let checkedOutput = root.appendingPathComponent("output-2")
        let checkArguments = [
            "generate", "--spec", spec.path, "--stem", "Pets", "--output-dir", checkedOutput.path,
            "--config-swift", path.path, "--config-cache", cache.path, "--check",
        ]
        let unchanged = try ConfigProcessRunner().run(
            cli, arguments: checkArguments, directory: root.appendingPathComponent("check"),
            timeout: 60)
        #expect(unchanged.status == 0, "\(unchanged.text(unchanged.stderr))")
        let support = checkedOutput.appendingPathComponent("Pets.Support.swift")
        let changed = try Data(contentsOf: support) + Data("// drift\n".utf8)
        try changed.write(to: support)
        let drift = try ConfigProcessRunner().run(
            cli, arguments: checkArguments, directory: root.appendingPathComponent("drift"),
            timeout: 60)
        #expect(drift.status == 1)
        #expect(drift.text(drift.stderr).contains("Generated files differ: Pets.Support.swift"))
        #expect(try Data(contentsOf: support) == changed)
    }
}
#endif
