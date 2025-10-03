import Foundation

/// An encoder that transforms an ``Encodable`` body into `multipart/form-data`.
///
/// Use this encoder by overriding ``Endpoint/bodyEncoder`` for endpoints that require multipart payloads.
public final class MultipartFormEncoder: EncoderType {

    /// Strategy defining how `Date` values should be represented inside the multipart payload.
    public enum DateEncodingStrategy {
        case deferredToDate
        case secondsSince1970
        case millisecondsSince1970
        case iso8601
        case formatted(DateFormatter)
        case custom((Date) throws -> String)
    }

    /// Strategy defining how raw `Data` values should be encoded.
    public enum DataEncodingStrategy {
        case binary(contentType: String? = "application/octet-stream")
        case deferredToData
        case custom((Data, String, [CodingKey]) throws -> Part)
    }

    /// Represents a single multipart section.
    public struct Part {
        public var name: String
        public var data: Data
        public var filename: String?
        public var contentType: String?

        public init(name: String, data: Data, filename: String? = nil, contentType: String? = nil) {
            self.name = name
            self.data = data
            self.filename = filename
            self.contentType = contentType
        }
    }

    public var boundary: String
    public var stringEncoding: String.Encoding {
        get { options.stringEncoding }
        set { options.stringEncoding = newValue }
    }
    public var dateEncodingStrategy: DateEncodingStrategy {
        get { options.dateEncodingStrategy }
        set { options.dateEncodingStrategy = newValue }
    }
    public var dataEncodingStrategy: DataEncodingStrategy {
        get { options.dataEncodingStrategy }
        set { options.dataEncodingStrategy = newValue }
    }
    public var filenameProvider: ([CodingKey]) -> String {
        get { options.filenameProvider }
        set { options.filenameProvider = newValue }
    }

    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
    }

    public static var contentType: String? { "multipart/form-data" }

    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = _MultipartFormDataEncoder(options: options, boundary: boundary, userInfo: userInfo)
        try value.encode(to: encoder)
        return try encoder.finalize()
    }

    // MARK: - Private

    fileprivate struct Options {
        var stringEncoding: String.Encoding = .utf8
        var dateEncodingStrategy: DateEncodingStrategy = .iso8601
        var dataEncodingStrategy: DataEncodingStrategy = .binary()
        var filenameProvider: ([CodingKey]) -> String = { codingPath in
            if let lastKey = codingPath.last {
                return lastKey.stringValue
            }
            return "file"
        }
    }

    fileprivate var options = Options()
}

/// Represents a binary field in a multipart payload.
public struct MultipartFormFile: Encodable {
    public let data: Data
    public let fileName: String
    public let contentType: String

    public init(data: Data, fileName: String, contentType: String) {
        self.data = data
        self.fileName = fileName
        self.contentType = contentType
    }

    public func encode(to encoder: Encoder) throws {
        if let encoder = encoder as? _MultipartFormDataEncoder {
            try encoder.append(file: self, at: encoder.codingPath)
            return
        }

        if let superEncoder = encoder as? _MultipartSuperEncoder {
            try superEncoder.parent.append(file: self, at: superEncoder.codingPath)
            return
        }

        var container = encoder.singleValueContainer()
        try container.encode(data)
    }
}

fileprivate protocol MultipartFormJSONProtocol {
    func _encodeJSON(to encoder: _MultipartFormDataEncoder, path: [CodingKey]) throws
}

/// Wraps an ``Encodable`` value so it is embedded as a JSON part within a multipart payload.
public struct MultipartFormJSON<Value: Encodable>: Encodable {
    public let value: Value
    fileprivate let jsonEncoder: JSONEncoder
    public let fileName: String?
    public let contentType: String

    public init(_ value: Value, encoder: JSONEncoder = JSONEncoder(), fileName: String? = nil, contentType: String = "application/json") {
        self.value = value
        self.jsonEncoder = encoder
        self.fileName = fileName
        self.contentType = contentType
    }

    public func encode(to encoder: Encoder) throws {
        if let encoder = encoder as? _MultipartFormDataEncoder {
            try encoder.append(json: self, at: encoder.codingPath)
            return
        }

        if let superEncoder = encoder as? _MultipartSuperEncoder {
            try superEncoder.parent.append(json: self, at: superEncoder.codingPath)
            return
        }

        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension MultipartFormJSON: MultipartFormJSONProtocol {
    fileprivate func _encodeJSON(to encoder: _MultipartFormDataEncoder, path: [CodingKey]) throws {
        try encoder.append(json: self, at: path)
    }
}

// MARK: - Internal Encoder

final class _MultipartFormDataEncoder: Encoder {
    fileprivate let options: MultipartFormEncoder.Options
    let boundary: String
    var codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    private var parts: [MultipartFormEncoder.Part] = []

    fileprivate init(options: MultipartFormEncoder.Options, boundary: String, userInfo: [CodingUserInfoKey: Any]) {
        self.options = options
        self.boundary = boundary
        self.userInfo = userInfo
        self.codingPath = []
    }

    func container<Key>(keyedBy keyType: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        let container = MultipartKeyedEncodingContainer<Key>(encoder: self, codingPath: codingPath)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        MultipartUnkeyedEncodingContainer(encoder: self, codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        MultipartSingleValueEncodingContainer(encoder: self, codingPath: codingPath)
    }

    func container<Key>(keyedBy keyType: Key.Type, at codingPath: [CodingKey]) -> KeyedEncodingContainer<Key> {
        let container = MultipartKeyedEncodingContainer<Key>(encoder: self, codingPath: codingPath)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer(at codingPath: [CodingKey]) -> UnkeyedEncodingContainer {
        MultipartUnkeyedEncodingContainer(encoder: self, codingPath: codingPath)
    }

    func singleValueContainer(at codingPath: [CodingKey]) -> SingleValueEncodingContainer {
        MultipartSingleValueEncodingContainer(encoder: self, codingPath: codingPath)
    }

    func encode<T: Encodable>(_ value: T, at path: [CodingKey]) throws {
        let previous = codingPath
        codingPath = path
        defer { codingPath = previous }
        try encode(value)
    }

    private func encode<T: Encodable>(_ value: T) throws {
        if let file = value as? MultipartFormFile {
            try append(file: file, at: codingPath)
            return
        }

        if let json = value as? MultipartFormJSONProtocol {
            try json._encodeJSON(to: self, path: codingPath)
            return
        }

        try value.encode(to: self)
    }

    func append(file: MultipartFormFile, at path: [CodingKey]) throws {
        let contentType = file.contentType
        try append(data: file.data, filename: file.fileName, contentType: contentType, at: path)
    }

    func append(field string: String, at path: [CodingKey]) throws {
        guard let data = string.data(using: options.stringEncoding) else {
            throw EncodingError.invalidValue(string, EncodingError.Context(codingPath: path, debugDescription: "Unable to represent string using chosen encoding."))
        }

        let name = try fieldName(for: path)
        parts.append(MultipartFormEncoder.Part(name: name, data: data))
    }

    func append(data: Data, filename: String?, contentType: String?, at path: [CodingKey]) throws {
        let name = try fieldName(for: path)
        let resolvedFileName: String
        if let filename = filename, !filename.isEmpty {
            resolvedFileName = filename
        } else {
            resolvedFileName = options.filenameProvider(path)
        }

        var part = MultipartFormEncoder.Part(name: name, data: data, filename: resolvedFileName, contentType: contentType)
        if part.contentType == nil {
            switch options.dataEncodingStrategy {
            case .binary(let defaultType):
                part.contentType = defaultType
            case .deferredToData:
                break
            case .custom:
                break
            }
        }
        parts.append(part)
    }

    func append(part: MultipartFormEncoder.Part, at path: [CodingKey]) throws {
        var mutablePart = part
        if mutablePart.name.isEmpty {
            mutablePart.name = try fieldName(for: path)
        }
        if mutablePart.filename == nil, case .binary(let defaultType) = options.dataEncodingStrategy {
            mutablePart.filename = options.filenameProvider(path)
            if mutablePart.contentType == nil {
                mutablePart.contentType = defaultType
            }
        }
        parts.append(mutablePart)
    }

    func append<Value>(json: MultipartFormJSON<Value>, at path: [CodingKey]) throws {
        let name = try fieldName(for: path)
        let data = try json.jsonEncoder.encode(json.value)

        let part = MultipartFormEncoder.Part(
            name: name,
            data: data,
            filename: (json.fileName?.isEmpty == false) ? json.fileName : nil,
            contentType: json.contentType
        )

        parts.append(part)
    }

    func fieldName(for path: [CodingKey]) throws -> String {
        guard !path.isEmpty else {
            throw EncodingError.invalidValue(path, EncodingError.Context(codingPath: path, debugDescription: "Multipart form data requires keyed coding keys."))
        }

        var components: [String] = []
        for (index, key) in path.enumerated() {
            let keyString: String
            if let intValue = key.intValue {
                keyString = String(intValue)
            } else {
                keyString = key.stringValue
            }

            if index == 0 {
                components.append(keyString)
            } else {
                components.append("[\(keyString)]")
            }
        }

        return components.joined()
    }

    func string(for date: Date) throws -> String {
        switch options.dateEncodingStrategy {
        case .deferredToDate:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .deferredToDate
            let data = try encoder.encode(date)
            guard let string = String(data: data, encoding: .utf8) else {
                throw EncodingError.invalidValue(date, EncodingError.Context(codingPath: codingPath, debugDescription: "Unable to encode date."))
            }
            return string.replacingOccurrences(of: "\"", with: "")
        case .secondsSince1970:
            return String(date.timeIntervalSince1970)
        case .millisecondsSince1970:
            return String(Int(date.timeIntervalSince1970 * 1000))
        case .iso8601:
            return iso8601Formatter.string(from: date)
        case .formatted(let formatter):
            return formatter.string(from: date)
        case .custom(let block):
            return try block(date)
        }
    }

    func finalize() throws -> Data {
        var data = Data()
        let prefix = "--\(boundary)\r\n"

        for part in parts {
            guard let prefixData = prefix.data(using: .utf8) else { continue }
            data.append(prefixData)

            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            disposition += "\r\n"
            data.append(Data(disposition.utf8))

            if let contentType = part.contentType {
                let header = "Content-Type: \(contentType)\r\n"
                data.append(Data(header.utf8))
            }

            data.append(Data("\r\n".utf8))
            data.append(part.data)
            data.append(Data("\r\n".utf8))
        }

        if let closingData = "--\(boundary)--\r\n".data(using: .utf8) {
            data.append(closingData)
        }

        return data
    }
}

// MARK: - Containers

private struct MultipartKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let encoder: _MultipartFormDataEncoder
    var codingPath: [CodingKey]

    mutating func encodeNil(forKey key: Key) throws { }

    mutating func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        let newPath = codingPath + [key]
        try encoder.encode(value, at: newPath)
    }

    mutating func encodeIfPresent<T>(_ value: T?, forKey key: Key) throws where T: Encodable {
        if let value = value {
            try encode(value, forKey: key)
        }
    }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let newPath = codingPath + [key]
        return encoder.container(keyedBy: keyType, at: newPath)
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let newPath = codingPath + [key]
        return encoder.unkeyedContainer(at: newPath)
    }

    mutating func superEncoder() -> Encoder {
        _MultipartSuperEncoder(parent: encoder, codingPath: codingPath + [MultipartCodingKey.superKey])
    }

    mutating func superEncoder(forKey key: Key) -> Encoder {
        _MultipartSuperEncoder(parent: encoder, codingPath: codingPath + [key])
    }
}

private struct MultipartUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    let encoder: _MultipartFormDataEncoder
    var codingPath: [CodingKey]
    var count: Int = 0

    mutating func encodeNil() throws { count += 1 }

    mutating func encode<T>(_ value: T) throws where T: Encodable {
        let key = MultipartCodingKey(index: count)
        let newPath = codingPath + [key]
        try encoder.encode(value, at: newPath)
        count += 1
    }

    mutating func encodeIfPresent<T>(_ value: T?) throws where T: Encodable {
        if let value = value {
            try encode(value)
        }
    }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        let key = MultipartCodingKey(index: count)
        count += 1
        return encoder.container(keyedBy: keyType, at: codingPath + [key])
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let key = MultipartCodingKey(index: count)
        count += 1
        return encoder.unkeyedContainer(at: codingPath + [key])
    }

    mutating func superEncoder() -> Encoder {
        let key = MultipartCodingKey(index: count)
        count += 1
        return _MultipartSuperEncoder(parent: encoder, codingPath: codingPath + [key])
    }
}

private struct MultipartSingleValueEncodingContainer: SingleValueEncodingContainer {
    let encoder: _MultipartFormDataEncoder
    var codingPath: [CodingKey]

    mutating func encodeNil() throws { }

    mutating func encode(_ value: Bool) throws {
        try encoder.append(field: value ? "true" : "false", at: codingPath)
    }

    mutating func encode(_ value: String) throws {
        try encoder.append(field: value, at: codingPath)
    }

    mutating func encode(_ value: Double) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: Float) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: Int) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: Int8) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: Int16) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: Int32) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: Int64) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: UInt) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: UInt8) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: UInt16) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: UInt32) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: UInt64) throws {
        try encoder.append(field: String(value), at: codingPath)
    }

    mutating func encode(_ value: Date) throws {
        let string = try encoder.string(for: value)
        try encoder.append(field: string, at: codingPath)
    }

    mutating func encode(_ value: Data) throws {
        switch encoder.options.dataEncodingStrategy {
        case .binary(let defaultType):
            let name = encoder.options.filenameProvider(codingPath)
            try encoder.append(data: value, filename: name, contentType: defaultType, at: codingPath)
        case .deferredToData:
            let string = value.base64EncodedString()
            try encoder.append(field: string, at: codingPath)
        case .custom(let transform):
            let fallbackName = try encoder.fieldName(for: codingPath)
            var part = try transform(value, fallbackName, codingPath)
            if part.name.isEmpty {
                part.name = fallbackName
            }
            try encoder.append(part: part, at: codingPath)
        }
    }

    mutating func encode(_ value: URL) throws {
        try encoder.append(field: value.absoluteString, at: codingPath)
    }

    mutating func encode<T>(_ value: T) throws where T: Encodable {
        try encoder.encode(value, at: codingPath)
    }
}

// MARK: - Supporting Types

private struct MultipartCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    static let superKey = MultipartCodingKey(stringValue: "super")!

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = Int(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }

    init(index: Int) {
        self.stringValue = String(index)
        self.intValue = index
    }
}

final class _MultipartSuperEncoder: Encoder {
    let parent: _MultipartFormDataEncoder
    var codingPath: [CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { parent.userInfo }

    init(parent: _MultipartFormDataEncoder, codingPath: [CodingKey]) {
        self.parent = parent
        self.codingPath = codingPath
    }

    func container<Key>(keyedBy keyType: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
        parent.container(keyedBy: keyType, at: codingPath)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        parent.unkeyedContainer(at: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        parent.singleValueContainer(at: codingPath)
    }
}

// MARK: - Date helpers

private let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
