import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension CodingUserInfoKey {
    /// `Int`: the HTTP status code, set by ``HTTPResponseJSONDecoder/decode(_:from:response:)``.
    public static let httpStatusCode = CodingUserInfoKey(
        rawValue: "com.velos.endpoints.httpStatusCode")!

    /// `[String: String]`: response headers as received, set by
    /// ``HTTPResponseJSONDecoder/decode(_:from:response:)``.
    public static let httpHeaders = CodingUserInfoKey(rawValue: "com.velos.endpoints.httpHeaders")!
}

/// Decodes response bodies using a fresh `JSONDecoder` for every call.
///
/// Empty JSON bodies decode as `null`. Only ``decode(_:from:response:)`` sets
/// ``Foundation/CodingUserInfoKey/httpStatusCode`` and
/// ``Foundation/CodingUserInfoKey/httpHeaders`` in the decoder's `userInfo`.
/// That overload can also decode non-JSON bodies as `Data`, selected by status code.
public struct HTTPResponseJSONDecoder: DecoderType, Sendable {
    /// Configures a fresh `JSONDecoder` before every decode call.
    ///
    /// The response-aware overload then sets the HTTP userInfo keys. For raw data
    /// statuses, it also sets `dataDecodingStrategy` to `.base64`, overriding this configuration.
    public var configure: @Sendable (JSONDecoder) -> Void

    /// Return `true` for status codes whose body isn't JSON; the body is decoded as `Data`.
    ///
    /// Only ``decode(_:from:response:)`` calls this selector. Raw bodies, including
    /// empty data, are presented as a base64 JSON string. The decoder's
    /// `dataDecodingStrategy` is set to `.base64` after ``configure`` runs.
    public var isRawDataStatus: @Sendable (_ statusCode: Int) -> Bool

    /// Creates a JSON response decoder with no raw-data statuses.
    ///
    /// - Parameter configure: Configures a fresh `JSONDecoder` for every call.
    ///   Defaults to no changes and can be supplied as a trailing closure.
    public init(configure: @Sendable @escaping (JSONDecoder) -> Void = { _ in }) {
        self.init(isRawDataStatus: { _ in false }, configure: configure)
    }

    /// Creates a response decoder that also decodes selected statuses as `Data`.
    ///
    /// A trailing closure after `isRawDataStatus:` configures the JSON decoder.
    /// - Parameters:
    ///   - isRawDataStatus: Returns `true` for non-JSON statuses whose body should decode
    ///     as `Data`. Raw decoding forces `.base64` after configuration, so a custom
    ///     data decoding strategy cannot change the bytes.
    ///   - configure: Configures a fresh `JSONDecoder` for every call. Defaults to no changes.
    public init(
        isRawDataStatus: @Sendable @escaping (_ statusCode: Int) -> Bool,
        configure: @Sendable @escaping (JSONDecoder) -> Void = { _ in }
    ) {
        self.configure = configure
        self.isRawDataStatus = isRawDataStatus
    }

    /// Decodes JSON without adding HTTP metadata or selecting raw-data statuses.
    ///
    /// Runs ``configure`` on a fresh `JSONDecoder`. An empty body decodes as JSON `null`.
    /// This overload does not set the HTTP userInfo keys.
    /// - Parameters:
    ///   - type: The response type to decode.
    ///   - data: The JSON response body.
    /// - Returns: The decoded value.
    /// - Throws: An error if the body cannot be decoded as `type`.
    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        configure(decoder)
        return try decoder.decode(type, from: data.isEmpty ? Data("null".utf8) : data)
    }

    /// Decodes a response body with its HTTP status and headers in `userInfo`.
    ///
    /// Runs ``configure`` on a fresh `JSONDecoder`, then sets the HTTP userInfo keys.
    /// An empty JSON body decodes as `null`. When ``isRawDataStatus`` returns `true`,
    /// the body decodes as `Data` instead, with `.base64` forced after configuration.
    /// - Parameters:
    ///   - type: The response type to decode.
    ///   - data: The response body.
    ///   - response: The HTTP response supplying the status code and headers.
    /// - Returns: The decoded value.
    /// - Throws: An error if the body cannot be decoded as `type`.
    public func decode<T: Decodable>(
        _ type: T.Type, from data: Data, response: HTTPURLResponse
    ) throws -> T {
        let decoder = JSONDecoder()
        configure(decoder)
        decoder.userInfo[.httpStatusCode] = response.statusCode
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields {
            headers[String(describing: name)] = String(describing: value)
        }
        decoder.userInfo[.httpHeaders] = headers
        let json: Data
        if isRawDataStatus(response.statusCode) {
            decoder.dataDecodingStrategy = .base64
            json = try JSONEncoder().encode(data)
        } else {
            json = data
        }
        return try decoder.decode(type, from: json.isEmpty ? Data("null".utf8) : json)
    }
}
