import Foundation
import PackagePlugin

@main
struct EndpointsGeneratorPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        return try makeCommands(
            files: target.sourceFiles.map(\.url),
            toolURL: context.tool(named: "endpoints-generate").url,
            workDirectory: context.pluginWorkDirectoryURL,
            swiftc: { try context.tool(named: "swiftc").url },
            hasConfigDependency: target.recursiveTargetDependencies.contains {
                $0.name == "EndpointsGeneratorConfig"
            },
            targetName: target.name,
            sourceMembershipHint: "remove it from exclude and add it to the target's sources"
        )
    }
}

private struct Specification {
    let url: URL
    let stem: String
    let configuration: URL?
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

private func generatedNames(stem: String) -> [String] {
    ["Server", "Schemas", "Endpoints", "Support"].map { stem + "." + $0 + ".generated.swift" }
}

private func makeCommands(
    files: [URL], toolURL: URL, workDirectory: URL, swiftc: () throws -> URL,
    hasConfigDependency: Bool?, targetName: String, sourceMembershipHint: String
) throws -> [Command] {
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
                "Invalid OpenAPI stem '\(stem)' (the stem becomes the Swift namespace); "
                    + "rename the file"
            )
            invalid = true
            continue
        }
        for output in generatedNames(stem: stem) {
            for file in files where file != url
                && asciiLower(file.lastPathComponent) == asciiLower(output)
            {
                Diagnostics.error(
                    "Target file '\(file.path)' conflicts with generated output '\(output)' "
                        + "for '\(url.lastPathComponent)' (ASCII case insensitive); rename the target file")
                invalid = true
            }
        }
        if let previous = specifications.first(where: { asciiLower($0.stem) == asciiLower(stem) }) {
            Diagnostics.error(
                "Duplicate OpenAPI stems '\(previous.stem)' and '\(stem)' "
                    + "(ASCII case insensitive); rename one specification"
            )
            invalid = true
        }
        let configurationURL = url.deletingLastPathComponent()
            .appendingPathComponent(stem + ".endpoints.swift")
        let configuration = FileManager.default.fileExists(atPath: configurationURL.path)
            ? configurationURL : nil
        if let configuration, !files.contains(where: {
            $0.standardizedFileURL == configuration.standardizedFileURL
        }) {
            Diagnostics.error(
                "\(configuration.lastPathComponent) must remain a regular Swift source "
                    + "of target '\(targetName)'; " + sourceMembershipHint)
            invalid = true
        }
        if let configuration, hasConfigDependency == false {
            Diagnostics.error(
                "\(configuration.lastPathComponent) requires the EndpointsGeneratorConfig "
                    + "product as a dependency of target '\(targetName)'")
            invalid = true
        }
        specifications.append(Specification(url: url, stem: stem, configuration: configuration))
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
    return try specifications.map { specification in
        let directory = generatedRoot.appendingPathComponent(specification.stem)
        // The plugin owns this directory. Remove outputs from the old naming
        // convention while planning, before a build system can discover them.
        for name in generatedNames(stem: specification.stem) {
            let legacy = directory.appendingPathComponent(
                name.replacingOccurrences(of: ".generated.swift", with: ".swift"))
            if FileManager.default.fileExists(atPath: legacy.path) {
                try FileManager.default.removeItem(at: legacy)
            }
        }
        var arguments = [
            "generate", "--spec", specification.url.path,
            "--stem", specification.stem, "--output-dir", directory.path,
        ]
        var inputs = [specification.url]
        if let configuration = specification.configuration {
            let swiftcURL = try swiftc()
            arguments += [
                "--config-swift", configuration.path, "--swiftc", swiftcURL.path,
                "--config-cache", workDirectory.appendingPathComponent("ConfigProgram").path,
            ]
            inputs.append(configuration)
        }
        let outputs = generatedNames(stem: specification.stem).map { name in
            directory.appendingPathComponent(name)
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
            workDirectory: context.pluginWorkDirectoryURL,
            swiftc: { try context.tool(named: "swiftc").url },
            // XcodeTarget.dependencies omits package products. The target compiler
            // diagnoses a missing EndpointsGeneratorConfig import instead.
            hasConfigDependency: nil,
            targetName: target.displayName,
            sourceMembershipHint: "add it to the target's Compile Sources"
        )
    }
}
#endif
