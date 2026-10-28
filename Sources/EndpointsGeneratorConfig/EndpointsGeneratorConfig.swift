/// The settings value declared by a `<Stem>.endpoints.swift` configuration file.
///
/// Controls generation and Swift naming without changing wire values.
/// The library has no runtime dependencies.
public struct EndpointsConfiguration: Sendable {
    /// The single default acronym list for all naming strategies.
    package static let defaultAcronyms: [String] = []
    /// The outer Swift namespace. Uses the specification filename stem when nil.
    public var namespace: String? = nil
    /// The access level of generated declarations. Defaults to internal.
    public var accessLevel: AccessLevel = .internal
    /// How the generated client chooses its server type and environments.
    public var server: ServerConfiguration = .fromSpec
    /// Which operations to generate. Exclusions take precedence over inclusions.
    public var operations: OperationFilter = .all
    /// Whether string and integer enums accept values not listed in the specification.
    public var enums: EnumStyle = .extensible
    /// Whether unsupported constructs are errors. When false, they warn and are skipped.
    /// Invalid names, collisions, references and servers remain errors in either mode.
    public var strict: Bool = true
    /// The strategy for component and inline type names. Defaults to upper camel case.
    public var typeNamingStrategy: NamingStrategy = .upperCamelCase
    /// The strategy for stored property names. Defaults to camel case.
    public var propertyNamingStrategy: NamingStrategy = .camelCase
    /// The strategy for path, query and header parameter names. Defaults to camel case.
    public var parameterNamingStrategy: NamingStrategy = .camelCase
    /// The strategy for enum case and extensible enum constant names. Defaults to camel case.
    public var enumCaseNamingStrategy: NamingStrategy = .camelCase
    /// The strategy for operation type names, before adding the `Endpoint` suffix.
    public var operationNamingStrategy: NamingStrategy = .upperCamelCase
    /// The strategy for environment case names. Defaults to camel case.
    public var environmentNamingStrategy: NamingStrategy = .camelCase
    /// Whole-token acronym spellings shared by the camel-case strategies, initially empty.
    /// Entries must match `[A-Za-z0-9]+` with no case-insensitive duplicates. They
    /// apply only to whole tokens. The first lower camel-case token follows its
    /// ordinary casing rule without an acronym override.
    public var acronyms: [String] = []
    /// Exact Swift spellings keyed by original wire identity. Applied last, after
    /// specification name extensions and strategies; they can repair a missing candidate.
    /// Values must be ASCII identifiers. Ambiguous or invalid renames are errors;
    /// unused renames warn. Renames never change wire values.
    public var renames: [NameTarget: String] = [:]

    /// Creates settings with idiomatic Swift naming and internal access by default.
    public init(
        namespace: String? = nil, accessLevel: AccessLevel = .internal,
        server: ServerConfiguration = .fromSpec, operations: OperationFilter = .all,
        enums: EnumStyle = .extensible, strict: Bool = true,
        typeNamingStrategy: NamingStrategy = .upperCamelCase,
        propertyNamingStrategy: NamingStrategy = .camelCase,
        parameterNamingStrategy: NamingStrategy = .camelCase,
        enumCaseNamingStrategy: NamingStrategy = .camelCase,
        operationNamingStrategy: NamingStrategy = .upperCamelCase,
        environmentNamingStrategy: NamingStrategy = .camelCase,
        acronyms: [String] = [], renames: [NameTarget: String] = [:]
    ) {
        self.namespace = namespace
        self.accessLevel = accessLevel
        self.server = server
        self.operations = operations
        self.enums = enums
        self.strict = strict
        self.typeNamingStrategy = typeNamingStrategy
        self.propertyNamingStrategy = propertyNamingStrategy
        self.parameterNamingStrategy = parameterNamingStrategy
        self.enumCaseNamingStrategy = enumCaseNamingStrategy
        self.operationNamingStrategy = operationNamingStrategy
        self.environmentNamingStrategy = environmentNamingStrategy
        self.acronyms = acronyms
        self.renames = renames
    }
    /// Creates default settings, then applies the supplied changes.
    public init(_ configure: (inout EndpointsConfiguration) -> Void) {
        self.init()
        configure(&self)
    }
    package func strategy(for target: NameTarget) -> NamingStrategy {
        switch target {
        case .type: return typeNamingStrategy
        case .property: return propertyNamingStrategy
        case .parameter: return parameterNamingStrategy
        case .enumCase: return enumCaseNamingStrategy
        case .operation: return operationNamingStrategy
        case .environment: return environmentNamingStrategy
        }
    }
}

/// The visibility of generated declarations.
public enum AccessLevel: String, Sendable {
    /// Visible within the generated target.
    case `internal`
    /// Visible to targets in the same Swift package.
    case package
    /// Visible to importing modules.
    case `public`
}
/// How generated string and integer enums handle unknown raw values.
public enum EnumStyle: Sendable {
    /// A RawRepresentable struct that preserves unknown values, for forward compatibility.
    case extensible
    /// A Swift enum whose decoding rejects unknown raw values.
    case closed
}
/// An environment supported by the runtime’s `TypicalEnvironments`.
public enum ServerEnvironment: String, Hashable, Sendable {
    /// A local development server.
    case local
    /// A shared development server.
    case development
    /// A staging server.
    case staging
    /// The production server.
    case production
}
/// The generated server definition or a reference to an existing server type.
public enum ServerConfiguration: Sendable {
    /// Generate environments from the specification’s servers, using the first as default.
    case fromSpec
    /// Use an existing, optionally module-qualified `ServerDefinition` type with `init()`.
    case type(String)
    /// Use the runtime’s typical environments with absolute URLs. Defaults to
    /// `.production`, which must have a URL in the dictionary; invalid URLs are errors.
    case environments([ServerEnvironment: String], default: ServerEnvironment = .production)
}
/// Filters operations by their original ID or route. Patterns are case-sensitive
/// UTF-8 globs: `*` matches any bytes, including `/`; all other characters are literal.
/// A pattern matches either `operationId` or `METHOD /path`; exclusions always win.
public struct OperationFilter: Sendable {
    /// Patterns selecting operations. Defaults to `["*"]`.
    public var include: [String]
    /// Patterns removing operations from the inclusion set. Defaults to empty.
    public var exclude: [String]
    /// Creates a case-sensitive glob filter. Includes all operations by default.
    public init(include: [String] = ["*"], exclude: [String] = []) {
        self.include = include
        self.exclude = exclude
    }
    /// Includes every operation.
    public static let all = OperationFilter()
}

/// Computes a Swift name candidate from a naming context.
/// The generator validates the candidate and escapes member keywords after applying renames.
public struct NamingStrategy: Sendable {
    package enum Kind: String, Sendable { case verbatim, camelCase, upperCamelCase, custom }
    package let kind: Kind
    private let resolve: @Sendable (NameContext) -> String?
    private init(kind: Kind, _ resolve: @escaping @Sendable (NameContext) -> String?) {
        self.kind = kind
        self.resolve = resolve
    }
    /// Uses the verbatim candidate: replaces each nonidentifier scalar with `_`
    /// and prefixes a leading digit with `_`. Returns nil for an empty non-enum name,
    /// `_` alone, or a wholly non-ASCII spelling. An empty enum value becomes `empty`.
    public static let verbatim = NamingStrategy(kind: .verbatim) { $0.verbatim }
    /// Uses the lower camel-case candidate. Returns nil when there are no ASCII
    /// letters or digits, except that an enum value without tokens becomes `empty`.
    public static let camelCase = NamingStrategy(kind: .camelCase) { $0.camelCased }
    /// Uses the upper camel-case candidate, with the same nil and enum `empty`
    /// behavior as ``camelCase``.
    public static let upperCamelCase = NamingStrategy(kind: .upperCamelCase) { $0.upperCamelCased }
    /// Uses a closure to produce a candidate. Returning nil is an error unless an
    /// explicit rename supplies the name. Keep the closure pure and deterministic:
    /// its result must depend only on the supplied context and fixed constants.
    public static func custom(_ name: @escaping @Sendable (NameContext) -> String?)
        -> NamingStrategy
    {
        NamingStrategy(kind: .custom, name)
    }
    /// Returns this strategy’s candidate. A nil candidate needs an explicit rename.
    public func name(for context: NameContext) -> String? { resolve(context) }
}

/// The original identity and spelling candidates passed to a naming strategy.
/// Candidates use `specName ?? wireName`. Swift keyword escaping and validation
/// happen after strategy resolution; these fields are unescaped candidates.
public struct NameContext: Sendable {
    /// The role and original owner of the name; unaffected by any Swift rename.
    public let target: NameTarget
    /// The server spelling, including an enum raw value (decimal text for integers).
    /// For operations without an ID, this is the constructed method/path naming input.
    public let wireName: String
    /// The optional validated `x-swift-name` or `x-enum-varnames` spelling.
    /// When present it replaces the wire spelling as candidate input.
    public let specName: String?
    /// The configured whole-token acronym spellings used to prepare the candidates.
    public let acronyms: [String]
    /// The lower camel-case candidate, or nil without ASCII letters or digits.
    /// Tokenless enum values use `empty`; integer enums use `valueN` or `valueMinusN`.
    public let camelCased: String?
    /// The upper camel-case candidate, with the same nil and enum fallback rules
    /// as ``camelCased``.
    public let upperCamelCased: String?
    /// The scalar-sanitized candidate. Empty enum values use `empty`; empty names
    /// elsewhere, `_` alone and wholly non-ASCII spellings yield nil. Integer enums
    /// use `valueN` or `valueMinusN` when the generator prepares this context.
    public let verbatim: String?
    /// Whether the target is a type or an operation (whose name receives an `Endpoint` suffix).
    public var isType: Bool { target.isType }
    /// Prepares candidates from the original identity and optional specification name.
    /// Treats every input as a string, even for enum targets: `"5"` produces `_5`.
    /// Generator-prepared integer enum contexts instead use `value5` or `valueMinus5`.
    /// Enum targets without tokens use `empty`; other tokenless names have nil camel candidates.
    public init(
        target: NameTarget, wireName: String, specName: String? = nil,
        acronyms: [String] = []
    ) {
        self.target = target
        self.wireName = wireName
        self.specName = specName
        self.acronyms = acronyms
        let input = specName ?? wireName
        let empty: String? = target.isEnumCase ? "empty" : nil
        camelCased = Naming.camel(input, upper: false, acronyms: acronyms) ?? empty
        upperCamelCased = Naming.camel(input, upper: true, acronyms: acronyms) ?? empty
        verbatim = Naming.verbatim(input, enumCase: target.isEnumCase)
    }

    /// Creates a context from already prepared candidates, including integer enum spellings.
    package init(
        target: NameTarget, wireName: String, specName: String?, acronyms: [String],
        camelCased: String?, upperCamelCased: String?, verbatim: String?
    ) {
        self.target = target
        self.wireName = wireName
        self.specName = specName
        self.acronyms = acronyms
        self.camelCased = camelCased
        self.upperCamelCased = upperCamelCased
        self.verbatim = verbatim
    }

    /// Removes a case-sensitive UTF-8 prefix once from `specName ?? wireName`.
    /// Returns this context unchanged if it does not match or would leave nothing.
    /// Otherwise clears `specName`, preserves the identity and acronyms, and recomputes candidates.
    public func removingPrefix(_ prefix: String) -> NameContext {
        let bytes = Array((specName ?? wireName).utf8)
        let part = Array(prefix.utf8)
        guard bytes.starts(with: part), bytes.count > part.count else { return self }
        return replacing(String(decoding: bytes.dropFirst(part.count), as: UTF8.self))
    }
    /// Removes a case-sensitive UTF-8 suffix once from `specName ?? wireName`.
    /// Returns this context unchanged if it does not match or would leave nothing.
    /// Otherwise clears `specName`, preserves the identity and acronyms, and recomputes candidates.
    public func removingSuffix(_ suffix: String) -> NameContext {
        let bytes = Array((specName ?? wireName).utf8)
        let part = Array(suffix.utf8)
        guard bytes.count > part.count, bytes.suffix(part.count).elementsEqual(part) else {
            return self
        }
        return replacing(String(decoding: bytes.dropLast(part.count), as: UTF8.self))
    }
    /// Replaces the naming input, clears `specName`, and recomputes all candidates.
    /// The target and acronyms stay unchanged; the original wire value in generated code is preserved.
    public func replacing(_ wireName: String) -> NameContext {
        NameContext(target: target, wireName: wireName, acronyms: acronyms)
    }
    /// Lowercases only ASCII `A` through `Z`, leaving all other bytes unchanged.
    public func lowercasedASCII(_ value: String) -> String { ASCII.lower(value) }
    /// Uppercases only ASCII `a` through `z`, leaving all other bytes unchanged.
    public func uppercasedASCII(_ value: String) -> String { ASCII.upper(value) }
}

/// An identifier’s role and original owner, used as a rename key.
/// Equality and hashing compare string identities by exact UTF-8 bytes, so
/// canonically equivalent Unicode spellings remain distinct.
public enum NameTarget: Hashable, Sendable {
    /// A component or inline type. Operation names use `.operation` instead.
    case type(TypeID)
    /// A property identified by its original wire name and declaring type.
    case property(String, in: TypeID)
    /// A parameter identified by original wire name, location and operation.
    case parameter(String, in: ParameterLocation, of: OperationID)
    /// An enum case or extensible enum constant identified by its original raw value.
    case enumCase(String, in: TypeID)
    /// An operation type, before the generated `Endpoint` suffix.
    case operation(OperationID)
    /// A server’s description or the fallback `serverN` (one-based spec order).
    case environment(String)
    /// The target’s type for `.type`, or the declaring type for a property or enum case.
    /// Returns nil for operations, parameters and environments.
    public var owner: TypeID? {
        switch self {
        case .type(let type): return type
        case .property(_, let owner), .enumCase(_, let owner): return owner
        default: return nil
        }
    }
    package var isType: Bool {
        switch self {
        case .type, .operation: return true
        default: return false
        }
    }
    package var isEnumCase: Bool {
        if case .enumCase = self { return true }
        return false
    }
}
/// A component or inline type identified independently of its Swift name.
/// Equality and hashing compare every string by exact UTF-8 bytes. A string literal
/// names a component, not a dotted path through generated Swift types.
public indirect enum TypeID: Hashable, Sendable, ExpressibleByStringLiteral {
    /// A named schema under `components.schemas`.
    case component(String)
    /// A type defined inline at the given original location.
    case inline(InlineOrigin)
    /// Creates a component identity from its original schema name.
    public init(stringLiteral value: String) { self = .component(value) }
}
/// The original location of an inline type, independent of generated names.
/// Equality and hashing compare every string by exact UTF-8 bytes. Response
/// payloads retain their status identity even inside a generated status union.
public indirect enum InlineOrigin: Hashable, Sendable {
    /// The schema declared inline for a property of the given original type.
    case property(String, in: TypeID)
    /// The item schema of an array at the given type identity.
    case items(of: TypeID)
    /// The schema declared inline for the given original parameter.
    case parameter(String, in: ParameterLocation, of: OperationID)
    /// An operation’s request body schema.
    case body(OperationID)
    /// A success payload for an original status such as `200`, `2XX` or `default`.
    case response(OperationID, status: String)
    /// An error payload for an original status such as `404`, `4XX` or `default`.
    case errorResponse(OperationID, status: String)
}
/// An operation’s original ID or method/path pair.
/// Equality and hashing compare strings by exact UTF-8 bytes. A string literal
/// means an `operationId`; use `.route` when the specification omits one.
public enum OperationID: Hashable, Sendable, ExpressibleByStringLiteral {
    /// The specification’s `operationId`.
    case id(String)
    /// An operation identified by its method and original path template.
    case route(method: HTTPMethod, path: String)
    /// Creates an operation ID from its original `operationId`.
    public init(stringLiteral value: String) { self = .id(value) }
}
/// A supported parameter location. Cookies and querystring parameters are unsupported.
public enum ParameterLocation: String, Hashable, Sendable {
    /// A path template parameter.
    case path
    /// A query string parameter.
    case query
    /// An HTTP header parameter.
    case header
}
/// An HTTP method used to identify an operation by route.
public enum HTTPMethod: String, Hashable, Sendable {
    /// The `GET` method.
    case get
    /// The `PUT` method.
    case put
    /// The `POST` method.
    case post
    /// The `DELETE` method.
    case delete
    /// The `OPTIONS` method.
    case options
    /// The `HEAD` method.
    case head
    /// The `PATCH` method.
    case patch
    /// The `TRACE` method.
    case trace
    /// The `QUERY` method.
    case query
}

/// Identity equality is byte-exact, even for canonically equivalent Unicode wire names.
private protocol ByteIdentity: Hashable { var identity: [UInt8] { get } }
private func key(_ tag: String, _ parts: [[UInt8]]) -> [UInt8] {
    Array(tag.utf8) + parts.flatMap { Array(String($0.count).utf8) + [58] + $0 }
}
extension ByteIdentity {
    /// Compares original identities using exact UTF-8 bytes.
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }
    /// Hashes the original identity’s exact UTF-8 bytes.
    public func hash(into hasher: inout Hasher) { hasher.combine(identity) }
}
extension OperationID: ByteIdentity {
    fileprivate var identity: [UInt8] {
        switch self {
        case .id(let name): return key("id", [Array(name.utf8)])
        case .route(let method, let path):
            return key("route", [Array(method.rawValue.utf8), Array(path.utf8)])
        }
    }
}
extension TypeID: ByteIdentity {
    fileprivate var identity: [UInt8] {
        switch self {
        case .component(let name): return key("component", [Array(name.utf8)])
        case .inline(let origin): return key("inline", [origin.identity])
        }
    }
}
extension InlineOrigin: ByteIdentity {
    fileprivate var identity: [UInt8] {
        switch self {
        case .property(let name, let owner):
            return key("property", [Array(name.utf8), owner.identity])
        case .items(let owner): return key("items", [owner.identity])
        case .parameter(let name, let location, let operation):
            return key(
                "parameter", [Array(name.utf8), Array(location.rawValue.utf8), operation.identity])
        case .body(let operation): return key("body", [operation.identity])
        case .response(let operation, let status):
            return key("response", [operation.identity, Array(status.utf8)])
        case .errorResponse(let operation, let status):
            return key("error", [operation.identity, Array(status.utf8)])
        }
    }
}
extension NameTarget: ByteIdentity {
    fileprivate var identity: [UInt8] {
        switch self {
        case .type(let type): return key("type", [type.identity])
        case .property(let name, let owner):
            return key("property", [Array(name.utf8), owner.identity])
        case .parameter(let name, let location, let operation):
            return key(
                "parameter", [Array(name.utf8), Array(location.rawValue.utf8), operation.identity])
        case .enumCase(let name, let owner): return key("enum", [Array(name.utf8), owner.identity])
        case .operation(let operation): return key("operation", [operation.identity])
        case .environment(let name): return key("environment", [Array(name.utf8)])
        }
    }
}

package enum ASCII {
    package static func isUpper(_ byte: UInt8) -> Bool { (65...90).contains(byte) }
    package static func isLower(_ byte: UInt8) -> Bool { (97...122).contains(byte) }
    package static func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
    package static func isAlnum(_ byte: UInt8) -> Bool {
        isUpper(byte) || isLower(byte) || isDigit(byte)
    }
    package static func lower(_ value: String) -> String {
        String(decoding: value.utf8.map { isUpper($0) ? $0 + 32 : $0 }, as: UTF8.self)
    }
    package static func upper(_ value: String) -> String {
        String(decoding: value.utf8.map { isLower($0) ? $0 - 32 : $0 }, as: UTF8.self)
    }
    package static func firstUpper(_ value: String) -> String {
        var bytes = Array(value.utf8)
        if let first = bytes.first, isLower(first) { bytes[0] -= 32 }
        return String(decoding: bytes, as: UTF8.self)
    }
    package static func firstLower(_ value: String) -> String {
        var bytes = Array(value.utf8)
        if let first = bytes.first, isUpper(first) { bytes[0] += 32 }
        return String(decoding: bytes, as: UTF8.self)
    }
    package static func isIdentifier(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard let first = bytes.first, value != "_", isUpper(first) || isLower(first) || first == 95
        else { return false }
        return bytes.allSatisfy { isAlnum($0) || $0 == 95 }
    }
}

package enum Naming {
    package static let keywords = Set(
        ("associatedtype class deinit enum extension fileprivate func import init "
            + "inout internal let open operator private precedencegroup protocol public "
            + "rethrows static struct subscript typealias var break case continue default "
            + "defer do else fallthrough for guard if in repeat return switch where while "
            + "as Any catch false is nil super self Self throw throws true try async await "
            + "actor nonisolated isolated some any borrowing consuming consume copy each "
            + "sending package macro distributed reasync yield mutating nonmutating "
            + "convenience dynamic didSet willSet get set indirect lazy optional override "
            + "required final weak unowned Type Protocol")
            .split(separator: " ").map(String.init))
    package static let namespaceReserved = Set(
        ("Server Environment JSONCoding RFC3339 JSONValue Indirect RawBodyEncoder EncodedPath "
            + "String Int Int32 Int64 Double Bool Date Data UUID URL Optional Array "
            + "Dictionary Decodable Encodable Codable CodingKey Hashable Sendable "
            + "CaseIterable RawRepresentable Decoder Encoder DecodingError EncodingError "
            + "KeyedDecodingContainer KeyedEncodingContainer Endpoint Definition Header "
            + "HeaderField Parameter PathTemplate Method NoAuth EmptyCodable JSONEncoder "
            + "JSONDecoder HTTPResponseJSONDecoder MultipartFormEncoder MultipartFormFile "
            + "MultipartFormJSON EncoderType DecoderType ParameterRepresentable "
            + "PathRepresentable ServerDefinition TypicalEnvironments")
            .split(separator: " ").map(String.init))
    package static let endpointReserved = Set(
        ("Server Response ErrorResponse Body PathComponents ParameterComponents "
            + "HeaderComponents Auth TaskError BodyEncoder ErrorDecoder ResponseDecoder "
            + "definition body pathComponents parameterComponents headerComponents auth "
            + "bodyEncoder errorDecoder responseDecoder queryEncodingStrategy")
            .split(separator: " ").map(String.init))
    package static let structReserved = Set([
        "CodingKeys", "init", "hashValue", "rawValue", "allCases", "knownValues",
        "wrappedValue",
    ])

    package static func asciiLower(_ value: String) -> String { ASCII.lower(value) }
    package static func asciiUpper(_ value: String) -> String { ASCII.upper(value) }
    package static func isIdentifier(_ value: String) -> Bool { ASCII.isIdentifier(value) }
    package static func tokens(_ value: String) -> [String] {
        let bytes = Array(value.utf8)
        var result: [String] = []
        var token: [UInt8] = []
        func flush() {
            if !token.isEmpty {
                result.append(String(decoding: token, as: UTF8.self))
                token = []
            }
        }
        for i in bytes.indices {
            let c = bytes[i]
            guard ASCII.isAlnum(c) else {
                flush()
                continue
            }
            if let p = token.last,
                (ASCII.isLower(p) && ASCII.isUpper(c))
                    || (ASCII.isUpper(p) && ASCII.isUpper(c) && i + 1 < bytes.count
                        && ASCII.isLower(bytes[i + 1]))
                    || (ASCII.isDigit(p) && ASCII.isUpper(c) && i + 1 < bytes.count
                        && ASCII.isLower(bytes[i + 1]))
            {
                flush()
            }
            token.append(c)
        }
        flush()
        return result
    }
    package static func camel(
        _ wire: String, upper: Bool, acronyms: [String] = []
    ) -> String? {
        let parts = tokens(wire)
        guard !parts.isEmpty else { return nil }
        let screaming = !wire.utf8.contains(where: ASCII.isLower)
        var result = ""
        for (i, raw) in parts.enumerated() {
            let token = screaming ? ASCII.lower(raw) : raw
            let lower = ASCII.lower(token)
            if i == 0 && !upper {
                result +=
                    token.utf8.allSatisfy { !ASCII.isLower($0) } ? lower : ASCII.firstLower(token)
            } else if let acronym = acronyms.first(where: { ASCII.lower($0) == lower }) {
                result += acronym
            } else if token.utf8.allSatisfy({ !ASCII.isLower($0) }) {
                result += token
            } else {
                result += ASCII.firstUpper(token)
            }
        }
        return result.utf8.first.map(ASCII.isDigit) == true ? "_" + result : result
    }
    package static func verbatim(_ wire: String, enumCase: Bool = false) -> String? {
        if wire.isEmpty { return enumCase ? "empty" : nil }
        // The reference table rejects wholly non-ASCII spellings, rather than inventing an underscore-only name.
        guard wire.unicodeScalars.contains(where: { $0.value < 128 }) else { return nil }
        var result = String(
            decoding: wire.unicodeScalars.map {
                let n = $0.value
                return n < 128 && (ASCII.isAlnum(UInt8(n)) || n == 95) ? UInt8(n) : 95
            }, as: UTF8.self)
        if result.utf8.first.map(ASCII.isDigit) == true { result = "_" + result }
        return result == "_" ? nil : result
    }
    package static func validated(_ value: String, isType: Bool) throws -> String {
        guard ASCII.isIdentifier(value) else {
            throw NameError("Name '\(value)' must be an ASCII Swift identifier")
        }
        if isType && keywords.contains(value) {
            throw NameError("Type name '\(value)' is a Swift keyword")
        }
        return !isType && keywords.contains(value) ? "`" + value + "`" : value
    }
    package static func fallbackOperationName(method: HTTPMethod, path: String) -> String {
        var result = method.rawValue + " "
        for scalar in path.unicodeScalars {
            if scalar == "{" {
                result += " By "
            } else if scalar == "}" {
                result += " "
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
package struct NameError: Error, CustomStringConvertible, Sendable {
    package let description: String
    package init(_ message: String) { description = message }
}
