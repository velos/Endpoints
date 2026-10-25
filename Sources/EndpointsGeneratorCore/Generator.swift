#if OpenAPIGenerator
import EndpointsGeneratorConfig
import Foundation

public struct GeneratedFile {
    public let name: String
    public let bytes: Data
}
public struct GenerationResult {
    public let files: [GeneratedFile]
    public let diagnostics: [Diagnostic]
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}
package struct EvaluatedSwiftConfiguration: Sendable {
    package let declarativeJSON: Data
    package let names: [String?]
    package init(declarativeJSON: Data, names: [String?]) {
        self.declarativeJSON = declarativeJSON
        self.names = names
    }
}
public enum Generator {
    /// Internal CLI/fixture transport. Its JSON vocabulary is not public API.
    public static func generate(
        spec: Data, config: Data? = nil, stem: String, specPath: String,
        configPath: String? = nil
    ) -> GenerationResult {
        let (configuration, configDiagnostics) = Configuration.load(
            config, path: configPath ?? stem + ".configuration.json")
        let configSource =
            configuration.transportSource
            ?? Source(path: configPath ?? stem + ".configuration.json", root: nil)
        return generate(
            spec: spec, configuration: configuration, configDiagnostics: configDiagnostics,
            configSource: configSource, configBytes: config, stem: stem, specPath: specPath)
    }

    /// In-process configuration. Source bytes, when supplied, fingerprint the authored config;
    /// a missing fingerprint is rendered as `none`, just as for a call without config bytes.
    public static func generate(
        spec: Data, configuration: EndpointsConfiguration, stem: String, specPath: String,
        configurationSource: Data? = nil
    ) -> GenerationResult {
        let config = Configuration(configuration)
        let path = stem + ".endpoints.swift"
        return generate(
            spec: spec, configuration: config, configDiagnostics: config.diagnostics(path: path),
            configSource: Source(path: path, root: nil), configBytes: configurationSource,
            stem: stem, specPath: specPath)
    }

    /// Collect once without names, evaluate once, filter the inventory, and lower once.
    package static func generate(
        spec: Data, swiftConfiguration: Data, stem: String, specPath: String,
        configurationPath: String,
        evaluate: ([NameRequest]) throws -> EvaluatedSwiftConfiguration
    ) throws -> GenerationResult {
        let (input, loaderDiagnostics) = Loader.load(spec, path: specPath)
        guard let input else { return GenerationResult(files: [], diagnostics: loaderDiagnostics) }
        var inventory = NameInventory(
            document: input.document, source: input.source, config: Configuration())
        inventory.collect()
        let evaluated = try evaluate(inventory.requests)
        guard evaluated.names.count == inventory.requests.count else {
            throw NameError("Configuration response count mismatch")
        }
        let (loadedConfig, errors) = Configuration.load(
            evaluated.declarativeJSON, path: configurationPath, allowCustom: true)
        var config = loadedConfig
        let candidates = Dictionary(
            uniqueKeysWithValues: zip(inventory.requests, evaluated.names).map {
                ($0.0.target, $0.1)
            })
        let strategy = NamingStrategy.custom { context in candidates[context.target] ?? nil }
        config.settings.typeNamingStrategy = strategy
        config.settings.propertyNamingStrategy = strategy
        config.settings.parameterNamingStrategy = strategy
        config.settings.enumCaseNamingStrategy = strategy
        config.settings.operationNamingStrategy = strategy
        config.settings.environmentNamingStrategy = strategy
        let source = Source(
            path: configurationPath, root: config.transportSource?.root,
            swiftText: String(decoding: swiftConfiguration, as: UTF8.self))
        let diagnostics = errors.map { source.diagnostic($0.message, $0.pointer, $0.severity) }
        return generate(
            spec: spec, configuration: config, configDiagnostics: diagnostics,
            configSource: source, configBytes: swiftConfiguration, stem: stem, specPath: specPath,
            prepared: PreparedGeneration(
                document: input, diagnostics: loaderDiagnostics,
                inventory: inventory.filtered(using: config)))
    }

    private struct PreparedGeneration {
        let document: LoadedDocument
        let diagnostics: [Diagnostic]
        let inventory: NameInventory
    }

    private static func generate(
        spec: Data, configuration: Configuration, configDiagnostics: [Diagnostic],
        configSource: Source, configBytes: Data?, stem: String, specPath: String,
        prepared: PreparedGeneration? = nil
    ) -> GenerationResult {
        var diagnostics = configDiagnostics
        let emptySource = Source(path: specPath, root: nil)
        if !Naming.isIdentifier(stem) || Naming.keywords.contains(stem) {
            diagnostics.append(
                emptySource.diagnostic(
                    "Stem must be a non-keyword ASCII Swift identifier; "
                        + "rename the specification file"
                ))
        }
        let namespace = configuration.namespace ?? stem
        if Naming.namespaceReserved.contains(namespace) {
            diagnostics.append(
                emptySource.diagnostic(
                    "Reserved namespace '\(namespace)'; choose another with namespace: \"…\""))
        }
        if configuration.serverType?.split(separator: ".").first.map(String.init) == namespace {
            diagnostics.append(
                emptySource.diagnostic(
                    "Namespace '\(namespace)' collides with the configured server type; "
                        + "choose another namespace: or module-qualify server: "
                        + ".type(\"Module.\(namespace)\")"
                ))
        }
        if !diagnostics.isEmpty {
            return GenerationResult(
                files: [], diagnostics: diagnostics.sorted(by: Diagnostic.less))
        }
        let loaded: LoadedDocument
        var inventory: NameInventory
        if let prepared {
            loaded = prepared.document
            inventory = prepared.inventory
            diagnostics += prepared.diagnostics
        } else {
            let (document, loaderDiagnostics) = Loader.load(spec, path: specPath)
            diagnostics += loaderDiagnostics
            guard let document else {
                return GenerationResult(
                    files: [], diagnostics: diagnostics.sorted(by: Diagnostic.less))
            }
            loaded = document
            inventory = NameInventory(
                document: loaded.document, source: loaded.source, config: configuration)
            inventory.collect()
        }
        diagnostics += inventory.diagnostics
        let resolutions = DeclarativeNameResolver().resolve(
            inventory.requests, config: configuration, source: configSource)
        diagnostics += resolutions.diagnostics
        var lowering = Lowering(
            document: loaded.document, source: loaded.source,
            configSource: configSource, config: configuration, namespace: namespace,
            resolutions: resolutions)
        let module = lowering.lower()
        diagnostics += lowering.diagnostics
        diagnostics.sort(by: Diagnostic.less)
        if diagnostics.contains(where: { $0.severity == .error }) {
            return GenerationResult(files: [], diagnostics: diagnostics)
        }
        // The canonical source label is part of the determinism contract.
        let sourceLabel = stem + ".openapi"
        let specHash = String(SHA256.hex(Array(spec)).prefix(16))
        let configHash = configBytes.map { String(SHA256.hex(Array($0)).prefix(16)) } ?? "none"
        let header = [
            "// Generated by EndpointsGenerator \(GeneratorVersion.current) "
                + "for \(stem) (\(sourceLabel)). Do not edit.",
            "// Inputs: spec sha256 \(specHash), config sha256 \(configHash)",
            "// swiftlint:disable all",
        ].joined(separator: "\n")
        let rendering = Rendering(module: module, header: header)
        let files = [
            GeneratedFile(name: stem + ".Server.swift", bytes: rendering.server()),
            GeneratedFile(name: stem + ".Schemas.swift", bytes: rendering.schemas()),
            GeneratedFile(name: stem + ".Endpoints.swift", bytes: rendering.endpoints()),
            GeneratedFile(name: stem + ".Support.swift", bytes: rendering.support()),
        ]
        return GenerationResult(files: files, diagnostics: diagnostics)
    }

    /// Returns filenames whose bytes changed. Unchanged outputs retain their mtime.
    @discardableResult
    public static func write(_ files: [GeneratedFile], to directory: URL) throws -> [String] {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        var changed: [String] = []
        for file in files {
            let url = directory.appendingPathComponent(file.name)
            if (try? Data(contentsOf: url)) != file.bytes {
                try file.bytes.write(to: url, options: .atomic)
                changed.append(file.name)
            }
        }
        return changed
    }
}
#endif
