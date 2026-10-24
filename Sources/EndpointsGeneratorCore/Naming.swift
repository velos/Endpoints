#if OpenAPIGenerator
import Foundation

public enum Naming {
    public enum Style { case type, member }
    static let keywords = Set(
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
    public static let namespaceReserved = Set(
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
    static let endpointReserved = Set(
        ("Server Response ErrorResponse Body PathComponents ParameterComponents "
            + "HeaderComponents Auth TaskError BodyEncoder ErrorDecoder ResponseDecoder "
            + "definition body pathComponents parameterComponents headerComponents auth "
            + "bodyEncoder errorDecoder responseDecoder queryEncodingStrategy")
            .split(separator: " ").map(String.init))
    static let structReserved = Set([
        "CodingKeys", "init", "hashValue", "rawValue", "allCases", "knownValues",
        "wrappedValue",
    ])
    private static let asciiCaseOffset = UInt8(ascii: "a") - UInt8(ascii: "A")

    private static func isUppercaseASCII(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isLowercaseASCII(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
    }

    private static func isDigitASCII(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private static func firstUpper(_ value: String) -> String {
        var bytes = Array(value.utf8)
        if let firstByte = bytes.first, isLowercaseASCII(firstByte) {
            bytes[0] = firstByte - asciiCaseOffset
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func firstLower(_ value: String) -> String {
        var bytes = Array(value.utf8)
        if let firstByte = bytes.first, isUppercaseASCII(firstByte) {
            bytes[0] = firstByte + asciiCaseOffset
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func asciiUpper(_ value: String) -> String {
        let bytes = value.utf8.map { byte in
            isLowercaseASCII(byte) ? byte - asciiCaseOffset : byte
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func asciiLower(_ value: String) -> String {
        let bytes = value.utf8.map { byte in
            isUppercaseASCII(byte) ? byte + asciiCaseOffset : byte
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public static func isIdentifier(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        guard let firstByte = bytes.first, value != "_" else { return false }
        let validStart =
            isUppercaseASCII(firstByte) || isLowercaseASCII(firstByte)
            || firstByte == UInt8(ascii: "_")
        return validStart
            && bytes.allSatisfy { byte in
                isUppercaseASCII(byte) || isLowercaseASCII(byte) || isDigitASCII(byte)
                    || byte == UInt8(ascii: "_")
            }
    }

    public static func tokens(_ value: String) -> [String] {
        // Non-ASCII scalars are separators, never classified using Unicode tables.
        let bytes = Array(value.utf8)
        var tokens: [String] = []
        var currentToken: [UInt8] = []
        for index in bytes.indices {
            let byte = bytes[index]
            guard
                isUppercaseASCII(byte) || isLowercaseASCII(byte) || isDigitASCII(byte)
                    || byte == UInt8(ascii: "_")
            else {
                if !currentToken.isEmpty {
                    tokens.append(String(decoding: currentToken, as: UTF8.self))
                    currentToken = []
                }
                continue
            }
            if let previous = currentToken.last, isUppercaseASCII(byte),
                isLowercaseASCII(previous)
                    || (isUppercaseASCII(previous) && index + 1 < bytes.count
                        && isLowercaseASCII(bytes[index + 1]))
            {
                tokens.append(String(decoding: currentToken, as: UTF8.self))
                currentToken = []
            }
            currentToken.append(byte)
        }
        if !currentToken.isEmpty {
            tokens.append(String(decoding: currentToken, as: UTF8.self))
        }
        return tokens
    }

    public static func name(_ original: String, style: Style, rename: String? = nil) throws
        -> String
    {
        var value: String
        if let rename {
            guard isIdentifier(rename) else {
                throw NameError("Rename '\(rename)' must be an ASCII Swift identifier")
            }
            value = rename
        } else {
            let parts = tokens(original)
            guard let first = parts.first else {
                throw NameError("Name '\(original)' has no ASCII identifier; use renames")
            }
            if style == .type {
                value = parts.map(firstUpper).joined()
            } else {
                let allCaps = first.utf8.filter { isUppercaseASCII($0) || isLowercaseASCII($0) }
                    .allSatisfy(isUppercaseASCII)
                value =
                    (allCaps ? asciiLower(first) : firstLower(first))
                    + parts.dropFirst().map(firstUpper).joined()
            }
            if let firstByte = value.utf8.first, isDigitASCII(firstByte) { value = "_" + value }
        }
        guard isIdentifier(value) else {
            throw NameError("Name '\(original)' does not form a Swift identifier; use renames")
        }
        if style == .type, keywords.contains(value) {
            throw NameError("Type name '\(value)' is a Swift keyword; use renames")
        }
        return style == .member && keywords.contains(value) ? "`\(value)`" : value
    }
}

public struct NameError: Error, CustomStringConvertible {
    public let description: String
    init(_ message: String) { description = message }
}

struct NameAllocator {
    let reserved: Set<String>
    private struct AllocatedName {
        let swift: String
        let original: String
    }
    private var used: [AllocatedName] = []
    init(reserved: Set<String>) { self.reserved = reserved }
    mutating func claim(_ name: String, original: String, hint: String) throws {
        let bare = name.replacingOccurrences(of: "`", with: "")
        guard !reserved.contains(bare) else {
            throw NameError("Reserved name '\(bare)' for '\(original)'; use \(hint)")
        }
        if let other = used.first(where: { $0.swift == bare }) {
            throw NameError(
                "Name collision '\(bare)' between '\(other.original)' and '\(original)'; use \(hint)"
            )
        }
        used.append(AllocatedName(swift: bare, original: original))
    }
}
#endif
