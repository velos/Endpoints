#if OpenAPIGenerator
import Foundation
import Yams

public enum AccessLevel: String {
    case `internal`, package, `public`

    var prefix: String { self == .internal ? "" : rawValue + " " }
}

public struct Rename {
    public var original: String
    public var replacement: String
}

public struct ConfiguredEnvironment {
    public var name: String
    public var url: String
}

public struct Configuration {
    public var namespace: String?
    public var accessLevel: AccessLevel = .internal
    public var serverType: String?
    public var environments: [ConfiguredEnvironment] = []
    public var hasEnvironments = false
    public var defaultEnvironment: String?
    public var include = ["*"]
    public var exclude: [String] = []
    public var schemaRenames: [Rename] = []
    public var operationRenames: [Rename] = []
    public var propertyRenames: [Rename] = []
    public var closedEnums = false
    public var strict = true
    public init() {}
    var access: String { accessLevel.prefix }

    static func load(_ data: Data?, path: String) -> (Self, [Diagnostic]) {
        guard let data else { return (Self(), []) }
        guard let text = String(data: data, encoding: .utf8),
            let root = try? compose(yaml: text, .default, .default, .utf8),
            let json = try? JSONSerialization.jsonObject(with: data), json is [String: Any]
        else {
            return (
                Self(), [Source(path: path, root: nil).diagnostic("Invalid configuration JSON")]
            )
        }
        let source = Source(path: path, root: root)
        var result = Self()
        var diagnostics: [Diagnostic] = []
        func error(_ message: String, _ pointer: String) {
            diagnostics.append(source.diagnostic(message, pointer))
        }
        func closed(_ node: Node?, _ allowed: [String], _ pointer: String) {
            guard let map = node?.mapping else {
                error("Expected an object", pointer)
                return
            }
            for key in map.compactMap({ $0.key.string }).filter({ !allowed.contains($0) })
                .sorted(by: utf8Less)
            {
                error("Unknown configuration key '\(key)'", pointer + "/" + pointerPart(key))
            }
        }
        func str(_ pointer: String) -> String? {
            guard let node = source.node(at: pointer) else { return nil }
            // JSON types are checked on the decoded object, not YAML's permissive scalar conversions.
            guard node.tag.rawValue == Tag.Name.str.rawValue else {
                error("Expected a string", pointer)
                return nil
            }
            return node.string
        }
        func strings(_ pointer: String) -> [String]? {
            guard let node = source.node(at: pointer) else { return nil }
            guard let array = node.sequence else {
                error("Expected an array of strings", pointer)
                return nil
            }
            return array.enumerated().compactMap { str(pointer + "/\($0.offset)") }
        }
        func renames(_ category: String) -> [Rename] {
            let pointer = "/renames/" + category
            guard let node = source.node(at: pointer) else { return [] }
            guard let map = node.mapping else {
                error("Expected an object of renames", pointer)
                return []
            }
            return map.compactMap { pair -> Rename? in
                guard let key = pair.key.string, let value = str(pointer + "/" + pointerPart(key))
                else { return nil }
                if !Naming.isIdentifier(value) {
                    error(
                        "Rename '\(value)' must be an ASCII Swift identifier",
                        pointer + "/" + pointerPart(key))
                }
                return Rename(original: key, replacement: value)
            }.sorted { utf8Less($0.original, $1.original) }
        }
        closed(
            root,
            [
                "version", "namespace", "accessLevel", "server", "operations", "renames",
                "enums", "strict",
            ], "")
        if source.node(at: "/version")?.int != 1
            || source.node(at: "/version")?.tag.rawValue != Tag.Name.int.rawValue
        {
            error("Configuration requires version: 1", "/version")
        }
        result.namespace = str("/namespace")
        if let namespace = result.namespace,
            !Naming.isIdentifier(namespace) || Naming.keywords.contains(namespace)
                || Naming.namespaceReserved.contains(namespace)
        {
            error("Namespace must be a non-reserved ASCII Swift identifier", "/namespace")
        }
        if let access = str("/accessLevel") {
            if let level = AccessLevel(rawValue: access) {
                result.accessLevel = level
            } else {
                error("accessLevel must be internal, package, or public", "/accessLevel")
            }
        }
        if let server = source.node(at: "/server") {
            closed(server, ["type", "environments", "defaultEnvironment"], "/server")
            if source.node(at: "/server/type")?.tag.rawValue != Tag.Name.null.rawValue {
                result.serverType = str("/server/type")
            }
            if let serverType = result.serverType,
                !serverType.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                    Naming.isIdentifier(String($0)) && !Naming.keywords.contains(String($0))
                })
            {
                error("server.type must be a qualified Swift type name", "/server/type")
            }
            if result.serverType == "Server" {
                error(
                    "server.type Server must be module-qualified to avoid a recursive typealias",
                    "/server/type")
            }
            result.defaultEnvironment = str("/server/defaultEnvironment")
            if let environments = source.node(at: "/server/environments") {
                result.hasEnvironments = true
                closed(
                    environments, ["local", "development", "staging", "production"],
                    "/server/environments")
                result.environments =
                    (environments.mapping?.compactMap { pair -> ConfiguredEnvironment? in
                        guard let key = pair.key.string,
                            let url = str("/server/environments/" + pointerPart(key))
                        else { return nil }
                        return ConfiguredEnvironment(name: key, url: url)
                    } ?? []).sorted { utf8Less($0.name, $1.name) }
            }
            if result.serverType != nil && result.hasEnvironments {
                error("server.type and server.environments are mutually exclusive", "/server")
            }
        }
        if let operations = source.node(at: "/operations") {
            closed(operations, ["include", "exclude"], "/operations")
            result.include = strings("/operations/include") ?? ["*"]
            result.exclude = strings("/operations/exclude") ?? []
        }
        if let renameNode = source.node(at: "/renames") {
            closed(renameNode, ["schemas", "operations", "properties"], "/renames")
            result.schemaRenames = renames("schemas")
            result.operationRenames = renames("operations")
            result.propertyRenames = renames("properties")
        }
        if let enums = str("/enums") {
            if !["open", "closed"].contains(enums) {
                error("enums must be open or closed", "/enums")
            }
            result.closedEnums = enums == "closed"
        }
        if let strict = source.node(at: "/strict") {
            if strict.tag.rawValue != Tag.Name.bool.rawValue {
                error("strict must be a boolean", "/strict")
            } else {
                result.strict = strict.bool ?? true
            }
        }
        return (result, diagnostics.sorted(by: Diagnostic.less))
    }
}

func matchesGlob(_ pattern: String, _ value: String) -> Bool {
    let patternBytes = Array(pattern.utf8)
    let valueBytes = Array(value.utf8)
    var patternIndex = 0
    var valueIndex = 0
    var lastStar: Int?
    var retryIndex = 0
    while valueIndex < valueBytes.count {
        if patternIndex < patternBytes.count, patternBytes[patternIndex] == valueBytes[valueIndex] {
            patternIndex += 1
            valueIndex += 1
        } else if patternIndex < patternBytes.count, patternBytes[patternIndex] == UInt8(ascii: "*")
        {
            lastStar = patternIndex
            patternIndex += 1
            retryIndex = valueIndex
        } else if let starIndex = lastStar {
            retryIndex += 1
            valueIndex = retryIndex
            patternIndex = starIndex + 1
        } else {
            return false
        }
    }
    while patternIndex < patternBytes.count, patternBytes[patternIndex] == UInt8(ascii: "*") {
        patternIndex += 1
    }
    return patternIndex == patternBytes.count
}
#endif
