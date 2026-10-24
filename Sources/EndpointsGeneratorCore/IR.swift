#if OpenAPIGenerator
import Foundation

// The lowering/rendering boundary contains arrays and values only. No hash collection
// can silently acquire observable order when a renderer is extended.
enum HTTPMethod: String {
    case get, post, put, patch, delete, head, options, trace, query

    var isSupported: Bool {
        switch self {
        case .get, .post, .put, .patch, .delete, .head: return true
        default: return false
        }
    }

    var uppercase: String { Naming.asciiUpper(rawValue) }
}

indirect enum TypeRef: Equatable {
    case string, int, int32, int64, double, bool, date, data, uuid, url, void
    case array(TypeRef)
    case optional(TypeRef)
    case named(String)

    var swift: String {
        switch self {
        case .string: return "String"
        case .int: return "Int"
        case .int32: return "Int32"
        case .int64: return "Int64"
        case .double: return "Double"
        case .bool: return "Bool"
        case .date: return "Date"
        case .data: return "Data"
        case .uuid: return "UUID"
        case .url: return "URL"
        case .void: return "Void"
        case .array(let item): return "[\(item.swift)]"
        case .optional(let item): return item.swift + "?"
        case .named(let path): return path
        }
    }

    var unwrapped: TypeRef {
        if case .optional(let item) = self { return item }
        return self
    }
}

enum Presence { case optional, requiredNullable, required }

struct Property {
    var name: String
    var wire: String
    var type: TypeRef
    var presence: Presence
    var docs: [String] = []
    var deprecated = false

    var storageName: String {
        deprecated ? "_" + name.replacingOccurrences(of: "`", with: "") : name
    }
}

struct EnumValue {
    var name: String
    var raw: String
}

enum StatusMatch: Equatable {
    case code(Int)
    case range(Int)
    case fallback

    var pattern: String {
        switch self {
        case .code(let status): return String(status)
        case .range(let hundreds): return "\(hundreds * 100)..<\((hundreds + 1) * 100)"
        case .fallback: return "default"
        }
    }
}

struct StatusOutcome {
    var name: String
    var match: StatusMatch
    var payload: TypeRef?
    var docs: [String] = []
    var rawBody = false
}

struct ParameterConformance {
    var typeName: String
    var deprecated = false
}

struct TypeDecl {
    enum Kind {
        case structure, openEnum, closedEnum, statusUnion
        case alias(TypeRef)
    }
    var name: String
    var kind: Kind
    var pointer = ""
    var renameKey = ""
    var properties: [Property] = []
    var enumRawType: TypeRef = .string
    var values: [EnumValue] = []
    var outcomes: [StatusOutcome] = []
    var nested: [TypeDecl] = []
    var docs: [String] = []
    var deprecated = false
}

struct EnvironmentDecl {
    var name: String
    var url: String
    var docs: [String]
}

struct ServerDecl {
    var customType: String?
    var typical = false
    var environments: [EnvironmentDecl] = []
    var defaultEnvironment = ""
    var securityDocs: [String] = []
}

enum PathSegment {
    case literal(String)
    case parameter(String)
}

/// Computed paths preserve embedded placeholders under the existing runtime's
/// segment interpolation rules. Lowering chooses the strategy; rendering spells it.
enum EndpointPath {
    case template([PathSegment])
    case computed([PathSegment])
}

struct FixedHeader {
    var name: String
    var value: String
}

struct EndpointDecl {
    var name: String
    var method: HTTPMethod
    var path: EndpointPath = .template([])
    var pointer = ""
    var pathParams: [Property] = []
    var queryParams: [Property] = []
    var headerParams: [Property] = []
    var body: TypeRef?
    var response: TypeRef = .void
    var errorResponse: TypeRef?
    var responseOutcomes: [StatusOutcome] = []
    var errorOutcomes: [StatusOutcome] = []
    var bodyUsesDate = false
    var responseUsesDate = false
    var errorUsesDate = false
    var noAuth = false
    var fixedHeaders: [FixedHeader] = []
    var nested: [TypeDecl] = []
    var docs: [String] = []
    var deprecated = false
}

struct Module {
    var namespace: String
    var access: AccessLevel
    var title: String
    var server: ServerDecl
    var schemas: [TypeDecl] = []
    var endpoints: [EndpointDecl] = []
    var usesDate = false
    var parameterConformances: [ParameterConformance] = []

    /// Resolve Date use through aliases and nested declarations once per named
    /// type. Memoization also keeps a shared acyclic component graph linear.
    mutating func resolveDateUsage() {
        var declarations: [String: TypeDecl] = [:]
        func collect(_ declaration: TypeDecl, parent: String) {
            let path = parent + "." + declaration.name
            declarations[path] = declaration
            for child in declaration.nested { collect(child, parent: path) }
        }
        for schema in schemas { collect(schema, parent: namespace) }
        for endpoint in endpoints {
            for declaration in endpoint.nested {
                collect(declaration, parent: namespace + "." + endpoint.name)
            }
        }
        var memo: [String: Bool] = [:]
        func involvesDate(_ type: TypeRef) -> Bool {
            switch type {
            case .date: return true
            case .array(let element), .optional(let element): return involvesDate(element)
            case .named(let name):
                if let result = memo[name] { return result }
                // Cycles are rejected before this phase; this sentinel is defensive.
                memo[name] = false
                guard let declaration = declarations[name] else { return false }
                let result: Bool
                if case .alias(let aliased) = declaration.kind {
                    result = involvesDate(aliased)
                } else {
                    result =
                        declaration.properties.contains { involvesDate($0.type) }
                        || declaration.outcomes.contains { $0.payload.map(involvesDate) ?? false }
                }
                memo[name] = result
                return result
            default: return false
            }
        }
        func enumDeclaration(_ type: TypeRef) -> String? {
            switch type {
            case .array(let element), .optional(let element): return enumDeclaration(element)
            case .named(let name):
                guard let declaration = declarations[name] else { return nil }
                switch declaration.kind {
                case .openEnum, .closedEnum: return name
                case .alias(let target): return enumDeclaration(target)
                default: return nil
                }
            default: return nil
            }
        }
        for endpoint in endpoints {
            for property in endpoint.pathParams + endpoint.queryParams {
                if let name = enumDeclaration(property.type),
                    !parameterConformances.contains(where: { wireEqual($0.typeName, name) })
                {
                    let nestedInEndpoint = name.hasPrefix(namespace + "." + endpoint.name + ".")
                    parameterConformances.append(
                        ParameterConformance(
                            typeName: name, deprecated: endpoint.deprecated && nestedInEndpoint))
                }
            }
        }
        parameterConformances.sort { utf8Less($0.typeName, $1.typeName) }
        // JSONCoding remains available for the four-file output contract. Emit the
        // RFC 3339 helper only if a retained schema or endpoint actually uses Date.
        usesDate = schemas.contains { involvesDate(.named(namespace + "." + $0.name)) }
        for index in endpoints.indices {
            endpoints[index].bodyUsesDate = endpoints[index].body.map(involvesDate) ?? false
            endpoints[index].responseUsesDate = involvesDate(endpoints[index].response)
            endpoints[index].errorUsesDate =
                endpoints[index].errorResponse.map(involvesDate) ?? false
            usesDate =
                usesDate || endpoints[index].bodyUsesDate
                || endpoints[index].responseUsesDate || endpoints[index].errorUsesDate
        }
    }
}
#endif
