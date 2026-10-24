import Foundation
import PackagePlugin

@main
struct EndpointsGeneratorPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        return try makeCommands(
            files: target.sourceFiles.map(\.url),
            toolURL: context.tool(named: "endpoints-generate").url,
            workDirectory: context.pluginWorkDirectoryURL
        )
    }
}

private struct Specification {
    let url: URL
    let stem: String
    let namespace: String
    let config: URL?
}

private let asciiCaseOffset = UInt8(ascii: "a") - UInt8(ascii: "A")

private func asciiLower(_ value: String) -> String {
    let bytes = value.utf8.map { byte in
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + asciiCaseOffset : byte
    }
    return String(decoding: bytes, as: UTF8.self)
}

private func validIdentifier(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    func startsIdentifier(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || byte == UInt8(ascii: "_")
    }
    return !bytes.isEmpty && value != "_" && startsIdentifier(bytes[0])
        && bytes.allSatisfy { byte in
            startsIdentifier(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
        }
}

private func makeCommands(files: [URL], toolURL: URL, workDirectory: URL) throws -> [Command] {
    var specifications: [Specification] = []
    var invalid = false
    for url in files.sorted(by: { lhs, rhs in
        lhs.path.utf8.lexicographicallyPrecedes(rhs.path.utf8)
    }) {
        let name = url.lastPathComponent
        let parts = name.components(separatedBy: ".")
        let bare = parts.count == 2 && parts[0] == "openapi"
        let named = parts.count >= 3 && parts[parts.count - 2] == "openapi"
        guard bare || named || name.contains(".openapi.") else { continue }
        guard ["json", "yaml", "yml"].contains(parts.last ?? ""), bare || parts.count == 3 else {
            Diagnostics.error(
                "Invalid OpenAPI filename '\(name)'; rename the file to "
                    + "<Stem>.openapi.yaml, .yml, or .json; the stem becomes the Swift namespace"
            )
            invalid = true
            continue
        }
        let stem = bare ? "API" : parts[0]
        guard validIdentifier(stem) else {
            Diagnostics.error(
                "Invalid OpenAPI stem '\(stem)' (the stem becomes the Swift namespace); rename the file"
            )
            invalid = true
            continue
        }
        let sidecar = url.deletingLastPathComponent().appendingPathComponent(
            stem + ".endpoints.json")
        let config = FileManager.default.fileExists(atPath: sidecar.path) ? sidecar : nil
        var namespace = stem
        if let config {
            do {
                let data = try Data(contentsOf: config)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    Diagnostics.error(
                        "Configuration '\(config.lastPathComponent)' must be a JSON object")
                    invalid = true
                    continue
                }
                if let value = object["namespace"] as? String { namespace = value }
            } catch {
                Diagnostics.error("Cannot read configuration JSON '\(config.lastPathComponent)'")
                invalid = true
                continue
            }
        }
        if let previous = specifications.first(where: { asciiLower($0.stem) == asciiLower(stem) }) {
            Diagnostics.error(
                "Duplicate OpenAPI stems '\(previous.stem)' and '\(stem)' "
                    + "(ASCII case insensitive); rename one specification"
            )
            invalid = true
        }
        if let previous = specifications.first(where: { $0.namespace == namespace }) {
            Diagnostics.error(
                "Duplicate OpenAPI namespace '\(namespace)' in '\(previous.url.lastPathComponent)' "
                    + "and '\(name)'; set a distinct config.namespace"
            )
            invalid = true
        }
        specifications.append(
            Specification(url: url, stem: stem, namespace: namespace, config: config))
    }
    guard !invalid else { return [] }
    let generatedRoot = workDirectory.appendingPathComponent("GeneratedSources")
    if let previous = try? FileManager.default.contentsOfDirectory(
        at: generatedRoot, includingPropertiesForKeys: nil
    ) {
        for directory in previous.sorted(by: { lhs, rhs in
            lhs.lastPathComponent.utf8.lexicographicallyPrecedes(rhs.lastPathComponent.utf8)
        }) where !specifications.contains(where: { $0.stem == directory.lastPathComponent }) {
            try FileManager.default.removeItem(at: directory)
        }
    }
    if specifications.isEmpty {
        Diagnostics.warning(
            "EndpointsGeneratorPlugin found no <Stem>.openapi.yaml, .yml, or .json "
                + "specifications in this target"
        )
    }
    return specifications.map { specification in
        let directory = generatedRoot.appendingPathComponent(specification.stem)
        var arguments = [
            "generate", "--spec", specification.url.path,
            "--stem", specification.stem, "--output-dir", directory.path,
        ]
        var inputs = [specification.url]
        if let config = specification.config {
            arguments += ["--config", config.path]
            inputs.append(config)
        }
        let outputs = ["Server", "Schemas", "Endpoints", "Support"].map { suffix in
            directory.appendingPathComponent(specification.stem + "." + suffix + ".swift")
        }
        return .buildCommand(
            displayName: "Generate Endpoints for \(specification.stem)", executable: toolURL,
            arguments: arguments, inputFiles: inputs, outputFiles: outputs
        )
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension EndpointsGeneratorPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        try makeCommands(
            files: target.inputFiles.map(\.url),
            toolURL: context.tool(named: "endpoints-generate").url,
            workDirectory: context.pluginWorkDirectoryURL
        )
    }
}
#endif
