import EndpointsGeneratorCore
import Foundation

func fail(_ message: String, path: String = "endpoints-generate") -> Never {
    FileHandle.standardError.write(Data("\(path):1:1: error: \(message) [#]\n".utf8))
    exit(1)
}

#if OpenAPIGenerator
func report(_ diagnostics: [String]) {
    for diagnostic in diagnostics {
        FileHandle.standardError.write(Data(
            (diagnostic + (diagnostic.hasSuffix("\n") ? "" : "\n")).utf8))
    }
}

struct Option {
    let flag: String
    let value: String
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.first == "generate" else {
    fail(
        "Usage: endpoints-generate generate --spec <path> --stem <Stem> --output-dir <dir> "
            + "[--config-swift <path>] [--swiftc <path>] [--config-cache <dir>] [--check]"
    )
}
var options: [Option] = []
var checkOnly = false
var index = 1
while index < arguments.count {
    let flag = arguments[index]
    if flag == "--check" {
        guard !checkOnly else { fail("Duplicate option '--check'") }
        checkOnly = true
        index += 1
        continue
    }
    guard [
        "--spec", "--stem", "--output-dir", "--configuration-json", "--config-swift",
        "--swiftc", "--config-cache",
    ].contains(flag),
        index + 1 < arguments.count,
        !arguments[index + 1].hasPrefix("--"), !options.contains(where: { $0.flag == flag })
    else {
        fail("Unknown, duplicate, or incomplete option '\(flag)'")
    }
    options.append(Option(flag: flag, value: arguments[index + 1]))
    index += 2
}
@MainActor func option(_ name: String) -> String? { options.first { $0.flag == name }?.value }
guard let specPath = option("--spec"), let stem = option("--stem"),
    let outputDirectory = option("--output-dir")
else {
    fail("--spec, --stem, and --output-dir are required")
}
let spec: Data
let config: Data?
do { spec = try Data(contentsOf: URL(fileURLWithPath: specPath)) } catch {
    fail("Cannot read specification", path: specPath)
}
if let path = option("--configuration-json") {
    do { config = try Data(contentsOf: URL(fileURLWithPath: path)) } catch {
        fail("Cannot read configuration", path: path)
    }
} else {
    config = nil
}
let result: GenerationResult
if let path = option("--config-swift") {
    if config != nil { fail("Choose --config-swift or the internal JSON transport, not both") }
    do {
        let file = URL(fileURLWithPath: path)
        let cache = option("--config-cache").map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: outputDirectory).deletingLastPathComponent()
                .appendingPathComponent("ConfigProgram")
        let program = try ConfigProgram(
            path: file, stem: stem,
            swiftc: option("--swiftc").map { URL(fileURLWithPath: $0) }, cache: cache)
        result = try Generator.generate(
            spec: spec, swiftConfiguration: program.source, stem: stem,
            specPath: specPath, configurationPath: file.path, evaluate: program.evaluate)
        report(program.compilerDiagnostics)
    } catch let failure as ConfigProgramFailure {
        report(failure.diagnostics)
        exit(1)
    } catch { fail("Cannot evaluate Swift configuration: \(error)", path: path) }
} else {
    result = Generator.generate(
        spec: spec, config: config, stem: stem, specPath: specPath,
        configPath: option("--configuration-json"))
}
for diagnostic in result.diagnostics {
    FileHandle.standardError.write(Data((diagnostic.formatted + "\n").utf8))
}
if result.hasErrors { exit(1) }
let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
if checkOnly {
    let changed = result.files.filter {
        (try? Data(contentsOf: outputURL.appendingPathComponent($0.name))) != $0.bytes
    }
    if !changed.isEmpty {
        fail("Generated files differ: " + changed.map(\.name).joined(separator: ", "),
            path: outputDirectory)
    }
} else {
    do { try Generator.write(result.files, to: outputURL) }
    catch { fail("Cannot write generated files", path: outputDirectory) }
}
#else
fail(
    "To generate endpoints, enable the OpenAPIGenerator trait on the Endpoints package dependency"
)
#endif
