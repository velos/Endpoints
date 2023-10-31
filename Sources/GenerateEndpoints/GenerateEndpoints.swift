import Foundation
import ArgumentParser
import OpenAPIKit
import Yams

struct GeneratorError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var localizedDescription: String {
        message
    }
}

@main
struct GenerateEndpoints: AsyncParsableCommand {

    private static let supportedFileFormats: [String] = ["yml", "yaml", "json"]

    @Argument(
        help: "The path to the OpenAPI spec in either JSON or YAML format",
        completion: .file(extensions: Self.supportedFileFormats)
    )
    var input: String

    @Option(
        help: "The directory where generated outputs are written",
        completion: .directory
    )
    var output = "Endpoints"

    @Flag(name: .shortAndLong, help: "Enables verbose log messages")
    var verbose = false

    @Flag(help: "Treats warnings as errors and fails generation")
    var strict = false

    @Flag(help: "Ignore errors that occur during generation and continue if possible")
    var allowErrors = false

    @Flag(name: .shortAndLong, help: "Removes the output directory before writing generated outputs")
    var clean = false

    func run() async throws {
        var document = try await parseInputSpec()
        for route in document.routes {
            print("route: \(route)")
        }
    }

    private func parseInputSpec() async throws -> OpenAPI.Document {

        let inputURL = URL(fileURLWithPath: (input as NSString).expandingTildeInPath)

        guard Self.supportedFileFormats.contains(inputURL.pathExtension) else {
            let extensions = Self.supportedFileFormats.map({ "`\($0)`" }).joined(separator: ", ")
            throw GeneratorError("The file must have one of the following extensions: \(extensions).")
        }

        let data = try Data(contentsOf: inputURL)

        let spec: OpenAPI.Document
        do {
            spec = try YAMLDecoder().decode(OpenAPI.Document.self, from: data)
        } catch {
            throw GeneratorError("ERROR! The spec is missing or invalid. \(OpenAPI.Error(from: error))")
        }

        return spec
    }
}
