import EndpointsGeneratorCore
import Foundation

func fail(_ message: String, path: String = "endpoints-generate") -> Never {
    FileHandle.standardError.write(Data("\(path):1:1: error: \(message) [#]\n".utf8))
    exit(1)
}

#if OpenAPIGenerator
struct Option {
    let flag: String
    let value: String
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.first == "generate" else {
    fail(
        "Usage: endpoints-generate generate --spec <path> --stem <Stem> --output-dir <dir> [--config <path>]"
    )
}
var options: [Option] = []
var index = 1
while index < arguments.count {
    let flag = arguments[index]
    guard ["--spec", "--stem", "--output-dir", "--config"].contains(flag),
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
if let path = option("--config") {
    do { config = try Data(contentsOf: URL(fileURLWithPath: path)) } catch {
        fail("Cannot read configuration", path: path)
    }
} else {
    config = nil
}
let result = Generator.generate(
    spec: spec, config: config, stem: stem, specPath: specPath, configPath: option("--config"))
for diagnostic in result.diagnostics {
    FileHandle.standardError.write(Data((diagnostic.formatted + "\n").utf8))
}
if result.hasErrors { exit(1) }
do {
    try Generator.write(result.files, to: URL(fileURLWithPath: outputDirectory, isDirectory: true))
} catch { fail("Cannot write generated files", path: outputDirectory) }
#else
fail(
    "To generate endpoints, enable the OpenAPIGenerator trait on the Endpoints package dependency"
)
#endif
