import EndpointsGeneratorConfig
import Foundation
import Testing

@testable import EndpointsGeneratorCore

let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
func fixture(_ stem: String, _ suffix: String = ".openapi.yaml") -> URL {
    Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(stem)/\(stem)\(suffix)")
}
func generation(_ stem: String, config override: Data? = nil) throws -> GenerationResult {
    let config = override ?? (try? Data(contentsOf: fixture(stem, ".configuration.json")))
    return Generator.generate(
        spec: try Data(contentsOf: fixture(stem)), config: config, stem: stem,
        specPath: stem + ".openapi.yaml", configPath: stem + ".configuration.json")
}

func generation(_ stem: String, configuration: EndpointsConfiguration) throws -> GenerationResult {
    Generator.generate(
        spec: try Data(contentsOf: fixture(stem)), configuration: configuration,
        stem: stem, specPath: stem + ".openapi.yaml")
}

@Suite struct GoldenTests {
    @Test(arguments: [
        "Boundaries", "Petstore", "SchemaEdges", "DateScopes", "Operations", "NamingConfigured",
    ])
    func sourceGoldens(
        stem: String
    ) throws {
        let result = try generation(stem)
        #expect(
            result.diagnostics.isEmpty,
            "\(result.diagnostics.map(\.formatted).joined(separator: "\n"))")
        #expect(result.files.count == 4)
        let directory = repository.appendingPathComponent(
            "Tests/EndpointsGeneratedGoldenTests/\(stem)")
        if ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" {
            try Generator.write(result.files, to: directory)
        }
        for file in result.files {
            #expect(
                try Data(contentsOf: directory.appendingPathComponent(file.name)) == file.bytes,
                "Golden drift: \(file.name)")
            let text = String(decoding: file.bytes, as: UTF8.self)
            #expect(!text.contains("\r") && !text.contains("\u{feff}") && !text.contains("\t"))
            #expect(text.hasSuffix("\n") && !text.hasSuffix("\n\n") && !text.contains("\n\n\n"))
            #expect(!text.components(separatedBy: "\n").contains { $0.hasSuffix(" ") })
        }
    }

    @Test(arguments: ["Reserved", "Collisions", "NoOperationId"]) func diagnosticGoldens(
        stem: String
    ) throws {
        let result = try generation(stem)
        #expect(result.hasErrors && result.files.isEmpty)
        let text = result.diagnostics.map(\.formatted).joined(separator: "\n") + "\n"
        let url = repository.appendingPathComponent(
            "Tests/EndpointsGeneratorCoreTests/Fixtures/\(stem)/diagnostics.txt")
        if ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" {
            try Data(text.utf8).write(to: url)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == text)
        #expect(result.diagnostics.allSatisfy { $0.line > 1 && $0.column > 1 })
    }

    @Test func writeOnlyWhenBytesChange() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = try generation("Petstore")
        #expect(try Generator.write(result.files, to: directory).count == 4)
        let urls = result.files.map { directory.appendingPathComponent($0.name) }
        let dates = try urls.map {
            try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        #expect(try Generator.write(result.files, to: directory).isEmpty)
        #expect(
            try urls.map {
                try $0.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
            } == dates)
        try Data("corrupted\n".utf8).write(to: urls[0])
        #expect(try Generator.write(result.files, to: directory) == [result.files[0].name])
    }

    @Test func canonicalLabelAndDeclarationOrder() throws {
        let spec = try Data(contentsOf: fixture("Petstore"))
        let a = Generator.generate(spec: spec, stem: "Pets", specPath: "/a/Pets.openapi.yaml")
        let b = Generator.generate(
            spec: spec, stem: "Pets", specPath: "/different/bare.openapi.json")
        #expect(!a.hasErrors && !b.hasErrors)
        #expect(a.files.map(\.bytes) == b.files.map(\.bytes))
        #expect(
            String(decoding: a.files[0].bytes, as: UTF8.self).contains("for Pets (Pets.openapi)"))
        let text = try String(contentsOf: fixture("Boundaries"), encoding: .utf8)
        // Reorder file-level declarations but retain the observable member order.
        let split = text.components(separatedBy: "    Problem:\n")
        let tail = split[1].components(separatedBy: "    Metadata:\n")
        let shuffled = split[0] + "    Metadata:\n" + tail[1] + "    Problem:\n" + tail[0]
        let config = try Data(contentsOf: fixture("Boundaries", ".configuration.json"))
        let normal = Generator.generate(
            spec: Data(text.utf8), config: config, stem: "Boundaries",
            specPath: "Boundaries.openapi.yaml")
        let changed = Generator.generate(
            spec: Data(shuffled.utf8), config: config, stem: "Boundaries",
            specPath: "Boundaries.openapi.yaml")
        #expect(!changed.hasErrors)
        // Hash header intentionally changes when input bytes change.
        for (a, b) in zip(normal.files, changed.files) {
            #expect(
                String(decoding: a.bytes, as: UTF8.self).split(
                    separator: "\n", omittingEmptySubsequences: false
                ).dropFirst(3).joined(separator: "\n")
                    == String(decoding: b.bytes, as: UTF8.self).split(
                        separator: "\n", omittingEmptySubsequences: false
                    ).dropFirst(3).joined(separator: "\n"))
        }
    }
}

@Suite struct ProcessDeterminismTests {
    @Test(arguments: ["Petstore", "Operations"]) func separateHashSeedsAndDirectories(stem: String)
        throws
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var directory = Bundle.module.bundleURL
        var located: URL?
        for _ in 0..<6 {
            let candidate = directory.appendingPathComponent("endpoints-generate")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                located = candidate
                break
            }
            directory = directory.deletingLastPathComponent()
        }
        let executable = try #require(
            located, "swift test must build the CLI beside the test products")
        var outputs: [[Data]] = []
        for (index, seed) in [nil, "1", nil].enumerated() {
            let input = root.appendingPathComponent("input-\(index)")
            let output = root.appendingPathComponent("output-\(index)")
            try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
            let spec = input.appendingPathComponent(
                index == 1 ? stem + ".openapi.yml" : stem + ".openapi.yaml")
            try FileManager.default.copyItem(at: fixture(stem), to: spec)
            let config = input.appendingPathComponent(stem + ".configuration.json")
            try FileManager.default.copyItem(at: fixture(stem, ".configuration.json"), to: config)
            let process = Process()
            process.executableURL = executable
            process.arguments = [
                "generate", "--spec", spec.path, "--configuration-json", config.path, "--stem",
                stem,
                "--output-dir", output.path,
            ]
            var environment = ProcessInfo.processInfo.environment
            environment["SWIFT_DETERMINISTIC_HASHING"] = seed
            environment["LANG"] = index == 1 ? "tr_TR.UTF-8" : "C"
            environment["LC_ALL"] = index == 1 ? "tr_TR.UTF-8" : "C"
            environment["TZ"] = index == 1 ? "Asia/Tokyo" : "UTC"
            environment["YAMS_DEFAULT_ENCODING"] = index == 1 ? "UTF16" : "UTF8"
            process.environment = environment
            let errors = Pipe()
            process.standardError = errors
            // Yams may log its ambient default during Options initialization,
            // even though the generator explicitly selects UTF-8. Only generated
            // file bytes are the determinism contract.
            process.standardOutput = FileHandle.nullDevice
            try process.run()
            let stderr = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0, "\(String(decoding: stderr, as: UTF8.self))")
            outputs.append(
                try ["Server", "Schemas", "Endpoints", "Support"].map {
                    try Data(contentsOf: output.appendingPathComponent(stem + ".\($0).swift"))
                })
        }
        #expect(outputs[0] == outputs[1] && outputs[1] == outputs[2])
    }
}

@Suite struct BannedAPITests {
    @Test func noAmbientOrNetworkingAPIs() throws {
        let roots = ["Sources/EndpointsGeneratorCore", "Sources/endpoints-generate"]
        let tokens = [
            "Date()", "Date.now", ".random(", "getenv", "UUID()", "ProcessInfo",
            "currentDirectoryPath", "NSUserName", "#file", "#function", "Bundle", "Locale",
            ".capitalized", "localized", "String(format:", "Mirror", "Hasher", "URLSession",
            "FoundationNetworking",
        ]
        for root in roots {
            let iterator = FileManager.default.enumerator(
                at: repository.appendingPathComponent(root), includingPropertiesForKeys: nil)!
            for case let url as URL in iterator where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                for token in tokens {
                    #expect(
                        !text.contains(token), "Banned API '\(token)' in \(url.lastPathComponent)")
                }
            }
        }
    }
}
