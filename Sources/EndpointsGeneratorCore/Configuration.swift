#if OpenAPIGenerator
import Foundation
import Yams

import EndpointsGeneratorConfig

struct Rename {
    let target: NameTarget
    let replacement: String
    let pointer: String
}

struct ConfiguredEnvironment {
    let name: String
    let url: String
}

/// Typed settings are the single source of truth; transport metadata only records locations.
struct Configuration {
    var settings = EndpointsConfiguration()
    private var renamePointers: [NameTarget: String] = [:]
    var transportSource: Source?
    init() {}
    init(_ value: EndpointsConfiguration) { settings = value }

    var namespace: String? {
        get { settings.namespace }
        set { settings.namespace = newValue }
    }
    var accessLevel: AccessLevel {
        get { settings.accessLevel }
        set { settings.accessLevel = newValue }
    }
    var strict: Bool {
        get { settings.strict }
        set { settings.strict = newValue }
    }
    var include: [String] {
        get { settings.operations.include }
        set { settings.operations.include = newValue }
    }
    var exclude: [String] {
        get { settings.operations.exclude }
        set { settings.operations.exclude = newValue }
    }
    var closedEnums: Bool {
        get { settings.enums == .closed }
        set { settings.enums = newValue ? .closed : .extensible }
    }
    var serverType: String? {
        if case .type(let name) = settings.server { return name }
        return nil
    }
    var hasEnvironments: Bool {
        if case .environments = settings.server { return true }
        return false
    }
    var environments: [ConfiguredEnvironment] {
        guard case .environments(let values, _) = settings.server else { return [] }
        return values.map { ConfiguredEnvironment(name: $0.key.rawValue, url: $0.value) }
            .sorted { utf8Less($0.name, $1.name) }
    }
    var defaultEnvironment: String? {
        if case .environments(_, let environment) = settings.server { return environment.rawValue }
        return nil
    }
    var renames: [Rename] {
        settings.renames.sorted { utf8Less(targetSwift($0.key), targetSwift($1.key)) }
            .enumerated().map { index, entry in
                Rename(
                    target: entry.key, replacement: entry.value,
                    pointer: renamePointers[entry.key] ?? "/renames/\(index)")
            }
    }
    var access: String { accessLevel.prefix }

    private func validate(source: Source) -> [Diagnostic] {
        let result = self
        var diagnostics: [Diagnostic] = []
        func error(_ message: String, _ pointer: String) {
            diagnostics.append(source.diagnostic(message, pointer))
        }
        if let namespace = result.namespace,
            !Naming.isIdentifier(namespace) || Naming.keywords.contains(namespace)
                || Naming.namespaceReserved.contains(namespace)
        {
            error("Namespace must be a non-reserved ASCII Swift identifier", "/namespace")
        }
        if let serverType = result.serverType,
            !serverType.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({
                Naming.isIdentifier(String($0)) && !Naming.keywords.contains(String($0))
            })
        {
            error("server: .type(...) requires a qualified Swift type name", "/server/type")
        }
        if result.serverType == "Server" {
            error(
                "server: .type(\"Server\") must be module-qualified to avoid a recursive typealias",
                "/server/type")
        }
        var acronyms: Set<String> = []
        for (i, value) in result.settings.acronyms.enumerated() {
            if value.isEmpty || !value.utf8.allSatisfy(ASCII.isAlnum) {
                error("Acronyms must be non-empty ASCII letters and digits", "/acronyms/\(i)")
            } else if !acronyms.insert(ASCII.lower(value)).inserted {
                error("Duplicate acronym '\(value)'", "/acronyms/\(i)")
            }
        }
        for rename in result.renames {
            let target = rename.target
            let name = rename.replacement
            let pointer = rename.pointer
            do {
                _ = try Naming.validated(name, isType: target.isType)
                let reserved: Set<String>
                switch target {
                case .type: reserved = Naming.namespaceReserved
                case .operation: reserved = []  // The emitted name has an Endpoint suffix.
                case .environment: reserved = ["rawValue", "allCases", "hashValue"]
                default: reserved = Naming.structReserved
                }
                if reserved.contains(name) {
                    throw NameError("Reserved name '\(name)' in rename")
                }
            } catch let failure as NameError {
                error("Invalid rename value: " + failure.description, pointer + "/name")
            } catch let failure {
                diagnostics.append(
                    source.diagnostic("Invalid rename: \(failure)", pointer + "/name"))
            }
        }
        return diagnostics.sorted(by: Diagnostic.less)
    }

    func diagnostics(path: String) -> [Diagnostic] {
        validate(source: Source(path: path, root: nil))
    }

    /// Private transport format; no compatibility contract for its keys or values.
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
        result.transportSource = source
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
        func operationID(_ pointer: String) -> OperationID? {
            if source.node(at: pointer)?.tag.rawValue == Tag.Name.str.rawValue {
                return str(pointer).map(OperationID.id)
            }
            closed(source.node(at: pointer), ["method", "path"], pointer)
            guard let method = str(pointer + "/method"), let path = str(pointer + "/path")
            else {
                error("Operation requires method and path", pointer)
                return nil
            }
            guard let value = HTTPMethod(rawValue: ASCII.lower(method)) else {
                error("Unknown HTTP method", pointer + "/method")
                return nil
            }
            return .route(method: value, path: path)
        }
        func typeID(_ pointer: String) -> TypeID? {
            if source.node(at: pointer)?.tag.rawValue == Tag.Name.str.rawValue {
                return str(pointer).map(TypeID.component)
            }
            guard let map = source.node(at: pointer)?.mapping else {
                error("Expected a component name or inline origin", pointer)
                return nil
            }
            let keys = map.compactMap { $0.key.string }
            if keys.contains("property") {
                closed(source.node(at: pointer), ["property", "in"], pointer)
                guard let name = str(pointer + "/property"), let owner = typeID(pointer + "/in")
                else { return nil }
                return .inline(.property(name, in: owner))
            }
            if keys.contains("items") {
                closed(source.node(at: pointer), ["items"], pointer)
                return typeID(pointer + "/items").map { .inline(.items(of: $0)) }
            }
            if keys.contains("parameter") {
                closed(
                    source.node(at: pointer), ["parameter", "location", "operation"], pointer)
                guard let name = str(pointer + "/parameter"),
                    let location = str(pointer + "/location"),
                    let place = ParameterLocation(rawValue: location),
                    let op = operationID(pointer + "/operation")
                else {
                    error("Inline parameter requires name, location, and operation", pointer)
                    return nil
                }
                return .inline(.parameter(name, in: place, of: op))
            }
            if keys.contains("body") {
                closed(source.node(at: pointer), ["body"], pointer)
                return operationID(pointer + "/body").map { .inline(.body($0)) }
            }
            for key in ["response", "errorResponse"] where keys.contains(key) {
                closed(source.node(at: pointer), [key, "status"], pointer)
                guard let op = operationID(pointer + "/" + key),
                    let status = str(pointer + "/status")
                else { return nil }
                return .inline(
                    key == "response"
                        ? .response(op, status: status) : .errorResponse(op, status: status))
            }
            error("Unknown inline type origin", pointer)
            return nil
        }
        func target(_ pointer: String) -> NameTarget? {
            let keys = source.node(at: pointer)?.mapping?.compactMap { $0.key.string } ?? []
            let roles =
                ["type", "property", "parameter", "enumCase", "environment"].filter {
                    keys.contains($0)
                }
                + (keys.contains("operation") && !keys.contains("parameter")
                    ? ["operation"] : [])
            guard roles.count == 1, let role = roles.first else {
                error("Rename must identify exactly one target", pointer)
                return nil
            }
            switch role {
            case "type":
                closed(source.node(at: pointer), ["type", "name"], pointer)
                return typeID(pointer + "/type").map(NameTarget.type)
            case "property", "enumCase":
                closed(source.node(at: pointer), [role, "in", "name"], pointer)
                guard let name = str(pointer + "/" + role), let owner = typeID(pointer + "/in")
                else { return nil }
                return role == "property"
                    ? .property(name, in: owner) : .enumCase(name, in: owner)
            case "parameter":
                closed(
                    source.node(at: pointer), ["parameter", "location", "operation", "name"],
                    pointer)
                guard let name = str(pointer + "/parameter"),
                    let location = str(pointer + "/location"),
                    let place = ParameterLocation(rawValue: location),
                    let op = operationID(pointer + "/operation")
                else {
                    error("Parameter rename requires name, location, and operation", pointer)
                    return nil
                }
                return .parameter(name, in: place, of: op)
            case "operation":
                closed(source.node(at: pointer), ["operation", "name"], pointer)
                return operationID(pointer + "/operation").map(NameTarget.operation)
            default:
                closed(source.node(at: pointer), ["environment", "name"], pointer)
                return str(pointer + "/environment").map(NameTarget.environment)
            }
        }
        closed(
            root,
            [
                "version", "namespace", "accessLevel", "server", "operations", "renames",
                "enums", "strict", "typeNamingStrategy", "propertyNamingStrategy",
                "parameterNamingStrategy", "enumCaseNamingStrategy", "operationNamingStrategy",
                "environmentNamingStrategy", "acronyms",
            ], "")
        if source.node(at: "/version")?.int != 1
            || source.node(at: "/version")?.tag.rawValue != Tag.Name.int.rawValue
        {
            error("Configuration requires version: 1", "/version")
        }
        result.namespace = str("/namespace")
        if let access = str("/accessLevel") {
            if let level = AccessLevel(rawValue: access) {
                result.accessLevel = level
            } else {
                error("accessLevel must be internal, package, or public", "/accessLevel")
            }
        }
        if let server = source.node(at: "/server") {
            closed(server, ["type", "environments", "defaultEnvironment"], "/server")
            let typeName =
                source.node(at: "/server/type")?.tag.rawValue == Tag.Name.null.rawValue
                ? nil : str("/server/type")
            let defaultName = str("/server/defaultEnvironment") ?? "production"
            if let environments = source.node(at: "/server/environments") {
                closed(
                    environments, ["local", "development", "staging", "production"],
                    "/server/environments")
                var values: [ServerEnvironment: String] = [:]
                for pair in environments.mapping ?? [:] {
                    guard let key = pair.key.string,
                        let environment = ServerEnvironment(rawValue: key),
                        let url = str("/server/environments/" + pointerPart(key))
                    else { continue }
                    values[environment] = url
                }
                if let environment = ServerEnvironment(rawValue: defaultName) {
                    result.settings.server = .environments(values, default: environment)
                } else {
                    error("Unknown default server environment", "/server/defaultEnvironment")
                }
                if typeName != nil {
                    error(
                        "Configure server: with either .type(...) or .environments(...)", "/server")
                }
            } else if let typeName {
                result.settings.server = .type(typeName)
            } else if source.node(at: "/server/defaultEnvironment") != nil {
                error(
                    "A default environment requires server: .environments(...)",
                    "/server/defaultEnvironment")
            }
        }
        if let operations = source.node(at: "/operations") {
            closed(operations, ["include", "exclude"], "/operations")
            result.include = strings("/operations/include") ?? ["*"]
            result.exclude = strings("/operations/exclude") ?? []
        }
        let strategies: [(String, WritableKeyPath<EndpointsConfiguration, NamingStrategy>)] = [
            ("typeNamingStrategy", \.typeNamingStrategy),
            ("propertyNamingStrategy", \.propertyNamingStrategy),
            ("parameterNamingStrategy", \.parameterNamingStrategy),
            ("enumCaseNamingStrategy", \.enumCaseNamingStrategy),
            ("operationNamingStrategy", \.operationNamingStrategy),
            ("environmentNamingStrategy", \.environmentNamingStrategy),
        ]
        for (key, keyPath) in strategies {
            if let value = str("/" + key) {
                switch value {
                case "camelCase": result.settings[keyPath: keyPath] = .camelCase
                case "upperCamelCase": result.settings[keyPath: keyPath] = .upperCamelCase
                case "verbatim": result.settings[keyPath: keyPath] = .verbatim
                default:
                    error(
                        "Naming strategy must be camelCase, upperCamelCase, or verbatim",
                        "/" + key)
                }
            }
        }
        result.settings.acronyms = strings("/acronyms") ?? EndpointsConfiguration.defaultAcronyms
        if let renameNode = source.node(at: "/renames") {
            if let array = renameNode.sequence {
                for i in array.indices {
                    let pointer = "/renames/\(i)"
                    guard let target = target(pointer) else { continue }
                    guard let name = str(pointer + "/name") else {
                        if source.node(at: pointer + "/name") == nil {
                            error("Rename requires name", pointer + "/name")
                        }
                        continue
                    }
                    if result.renames.contains(where: { $0.target == target }) {
                        error("Duplicate rename target; use one rename per target", pointer)
                    }
                    result.settings.renames[target] = name
                    result.renamePointers[target] = pointer
                }
            } else {
                error(
                    "renames must be an array of structured targets",
                    "/renames")
            }
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
        diagnostics += result.validate(source: source)
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
        if patternIndex < patternBytes.count,
            patternBytes[patternIndex] == valueBytes[valueIndex]
        {
            patternIndex += 1
            valueIndex += 1
        } else if patternIndex < patternBytes.count,
            patternBytes[patternIndex] == UInt8(ascii: "*")
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
