#if OpenAPIGenerator
import Foundation
import Yams
import OpenAPIKit
import OpenAPIKit30
import OpenAPIKitCompat

struct LoadedDocument {
    let document: OpenAPIKit.OpenAPI.Document
    let source: Source
}

enum Loader {
    static func load(_ data: Data, path: String) -> (LoadedDocument?, [Diagnostic]) {
        guard let text = String(data: data, encoding: .utf8) else {
            return (
                nil, [Source(path: path, root: nil).diagnostic("Specification must be UTF-8")]
            )
        }
        let root: Node
        do {
            guard let node = try compose(yaml: text, .default, .default, .utf8) else {
                return (nil, [Source(path: path, root: nil).diagnostic("Empty specification")])
            }
            root = node
        } catch {
            return (
                nil,
                [
                    yamlFailure(
                        error, path: path,
                        message: "Invalid YAML or JSON specification: "
                            + swiftLiteral(String(describing: error)))
                ]
            )
        }
        let source = Source(path: path, root: root)
        var diagnostics: [Diagnostic] = []
        // Scan before decoding/lookup. No external reference loader is ever invoked.
        func scan(_ node: Node, _ pointer: String) {
            if let mapping = node.mapping {
                var seen: [String] = []
                for pair in mapping {
                    guard let key = pair.key.string else {
                        diagnostics.append(
                            source.diagnostic("Object keys must be strings", pointer))
                        continue
                    }
                    let child = pointer + "/" + pointerPart(key)
                    if seen.contains(where: { wireEqual($0, key) }) {
                        diagnostics.append(
                            source.diagnostic("Duplicate object key '\(key)'", child))
                    }
                    seen.append(key)
                    if key == "$ref", let reference = pair.value.string, !reference.hasPrefix("#/")
                    {
                        diagnostics.append(
                            source.diagnostic(
                                "External references are not supported; use a local #/components reference",
                                child))
                    }
                    scan(pair.value, child)
                }
            } else if let sequence = node.sequence {
                for (index, child) in sequence.enumerated() { scan(child, pointer + "/\(index)") }
            }
        }
        scan(root, "")
        if !diagnostics.isEmpty { return (nil, diagnostics) }
        let version = source.node(at: "/openapi")?.string ?? ""
        if source.node(at: "/swagger") != nil || version.hasPrefix("2.") {
            return (
                nil,
                [
                    source.diagnostic(
                        "OpenAPI 2.0 is not supported; convert the specification to 3.0 or 3.1",
                        "/swagger")
                ]
            )
        }
        let document: OpenAPIKit.OpenAPI.Document
        do {
            if version.hasPrefix("3.0.") {
                let old = try YAMLDecoder(encoding: .utf8).decode(
                    OpenAPIKit30.OpenAPI.Document.self, from: text)
                document = old.convert(to: .v3_1_1)
            } else if version.hasPrefix("3.1.") || version.hasPrefix("3.2.") {
                document = try YAMLDecoder(encoding: .utf8).decode(
                    OpenAPIKit.OpenAPI.Document.self, from: text)
            } else {
                return (
                    nil,
                    [
                        source.diagnostic(
                            "Expected OpenAPI version 3.0.x, 3.1.x, or 3.2.x", "/openapi")
                    ]
                )
            }
        } catch {
            let detail = OpenAPIKit.OpenAPI.Error(from: error)
            let pointer = detail.codingPath.map { "/" + pointerPart($0.stringValue) }.joined()
            return (
                nil,
                [
                    source.diagnostic(
                        "OpenAPI document decoding failed: "
                            + swiftLiteral(detail.description), pointer)
                ]
            )
        }
        do {
            // Strict here means upstream warnings-as-errors, not our unsupported policy.
            // Non-fatal OpenAPIKit warnings are deliberately not surfaced.
            _ = try document.validate(strict: false)
        } catch let errors as OpenAPIKit.ValidationErrorCollection {
            for error in errors.values {
                let pointer = error.codingPath.map { "/" + pointerPart($0.stringValue) }
                    .joined()
                diagnostics.append(
                    source.diagnostic(
                        "OpenAPI validation failed: " + swiftLiteral(error.reason), pointer))
            }
        } catch {
            let detail = OpenAPIKit.OpenAPI.Error(from: error)
            let pointer = detail.codingPath.map { "/" + pointerPart($0.stringValue) }.joined()
            diagnostics.append(
                source.diagnostic(
                    "OpenAPI validation failed: " + swiftLiteral(detail.description),
                    pointer))
        }
        return (
            diagnostics.isEmpty ? LoadedDocument(document: document, source: source) : nil,
            diagnostics
        )
    }
}
#endif
