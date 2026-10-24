//
//  PathTemplate.swift
//  Endpoints
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

private let percentEscapeHexDigits = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")

/// A type that can be interpolated into a ``PathTemplate``.
public protocol PathRepresentable: Sendable {
    /// The value, percent-encoded as a single path segment.
    ///
    /// A `/` is kept as a separator, so encode it as `%2F` when it belongs to the value.
    /// `%XX` sequences are kept as escapes, so encode a literal `%` as `%25`. Other
    /// characters not allowed in a path, such as spaces, `?`, and `#`, are encoded for you.
    var pathSafe: String { get }
}

extension String: PathRepresentable {
    /// Percent-encodes this string as a path segment, including `.` and `..` as
    /// `%2E` and `%2E%2E` so URL resolution preserves them.
    public var pathSafe: String {
        if self == "." || self == ".." {
            return String(repeating: "%2E", count: self.count)
        }

        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

extension Optional: PathRepresentable where Wrapped: PathRepresentable {
    public var pathSafe: String {
        switch self {
        case .none: return ""
        case .some(let representable): return representable.pathSafe
        }
    }
}

extension Int: PathRepresentable {
    public var pathSafe: String {
        return "\(self)"
    }
}

/// A URL path with placeholders filled from an endpoint's ``Endpoint/PathComponents``.
///
/// Create one from a string literal, interpolating key paths with `\(path:)`:
///
/// ```swift
/// let path: PathTemplate<EventEndpoint.PathComponents> = "calendars/\(path: \.calendarId)/events/\(path: \.eventId)"
/// ```
///
/// Slashes are added between components as needed. Pass `includesSlash: false` to
/// place a value directly against the surrounding text.
public struct PathTemplate<T>: Sendable {

    private struct Literal: PathRepresentable {
        let value: String

        var pathSafe: String {
            return value
        }
    }

    private struct RepresentableInfo: Equatable, Sendable {
        static func == (lhs: RepresentableInfo, rhs: RepresentableInfo) -> Bool {
            return lhs.index == rhs.index &&
                lhs.includesSlash == rhs.includesSlash &&
                lhs.representable.pathSafe == rhs.representable.pathSafe
        }

        let index: Int
        let representable: PathRepresentable
        let includesSlash: Bool
    }

    private var pathComponents: [RepresentableInfo] = []
    private var keyPathComponents: [(Int, PartialKeyPath<T> & Sendable, Bool)] = []

    private var currentIndex: Int = 0

    public init() { }

    mutating func append(path: PathRepresentable, indexOverride: Int? = nil, includesSlash: Bool = true) {
        // Fixed text, from string literals or the + operators, arrives as String. Wrap it
        // so template slashes and %XX escapes are kept rather than segment-encoded.
        let representable: PathRepresentable
        if let literal = path as? String {
            representable = Literal(value: literal)
        } else {
            representable = path
        }

        if let index = indexOverride {
            pathComponents.append(RepresentableInfo(index: index, representable: representable, includesSlash: includesSlash))
            currentIndex = index
        } else {
            pathComponents.append(RepresentableInfo(index: currentIndex, representable: representable, includesSlash: includesSlash))
            currentIndex += 1
        }
    }

    mutating func append(keyPath: PartialKeyPath<T> & Sendable, indexOverride: Int? = nil, includesSlash: Bool = true) {
        if let index = indexOverride {
            keyPathComponents.append((index, keyPath, includesSlash))
            currentIndex = index
        } else {
            keyPathComponents.append((currentIndex, keyPath, includesSlash))
            currentIndex += 1
        }
    }

    mutating func append(template: PathTemplate<T>) {
        let current = currentIndex
        for info in template.pathComponents {
            append(path: info.representable, indexOverride: current + info.index, includesSlash: info.includesSlash)
        }

        for (index, keyPathComponent, includesSlash) in template.keyPathComponents {
            append(keyPath: keyPathComponent, indexOverride: current + index, includesSlash: includesSlash)
        }
    }

    private static func normalizedPath(_ value: String) -> String {
        return value.components(separatedBy: "%").enumerated().map { index, part in
            let encoded = part.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            guard index > 0 else { return encoded }

            let digits = part.unicodeScalars.prefix(2)
            let validEscape = digits.count == 2 && digits.allSatisfy(percentEscapeHexDigits.contains)
            return (validEscape ? "%" : "%25") + encoded
        }.joined()
    }

    /// Returns the percent-encoded path with each placeholder replaced by the matching property of `value`.
    public func path(with value: T) -> String {
        let values = keyPathComponents.map { (index, path, includesSlash) -> RepresentableInfo in
            return RepresentableInfo(index: index, representable: value[keyPath: path] as! PathRepresentable, includesSlash: includesSlash)
        }

        var allComponents = pathComponents + values
        allComponents.sort(by: { (first, second) -> Bool in
            return first.index < second.index
        })

        var fullString = ""
        let previousComponents: [RepresentableInfo?] = [nil] + Array(allComponents.dropFirst())
        for (previous, component) in zip(previousComponents, allComponents) {
            let insertion = Self.normalizedPath(component.representable.pathSafe)

            if let previous = previous, component.includesSlash && !previous.includesSlash, fullString.last != "/", insertion.first != "/" {
                fullString.append("/")
            } else if !component.includesSlash, fullString.last == "/" {
                fullString.removeLast()
            }

            // if the last insertion is empty, then remove any trailing last '/'
            guard !insertion.isEmpty else {
                if fullString.last == "/", component == allComponents.last {
                    fullString.removeLast()
                }

                continue
            }

            fullString.append(insertion)

            if component.includesSlash, insertion.last != "/", component != allComponents.last {
                fullString.append("/")
            }
        }

        // remove all duplicate '//'
        while fullString.contains("//") {
            fullString = fullString.replacingOccurrences(of: "//", with: "/")
        }

        return fullString
    }
}

extension PathTemplate: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral: String) {
        append(path: stringLiteral)
    }
}

extension PathTemplate: ExpressibleByStringInterpolation {

    public init(stringInterpolation: StringInterpolation) {
        append(template: stringInterpolation.path)
    }

    public struct StringInterpolation: StringInterpolationProtocol {

        fileprivate var path: PathTemplate<T>

        public init(literalCapacity: Int, interpolationCount: Int) {
            path = PathTemplate<T>()
        }

        mutating public func appendLiteral(_ literal: String) {
            guard !literal.isEmpty else { return }
            path.append(path: literal)
        }

        mutating public func appendInterpolation<U: PathRepresentable>(path value: KeyPath<T, U> & Sendable, includesSlash: Bool = true) {
            path.append(keyPath: value, includesSlash: includesSlash)
        }
    }
}

// PathRepresentable + KeyPath
public func +<T, U: PathRepresentable, V: PathRepresentable>(lhs: U, rhs: KeyPath<T, V> & Sendable) -> PathTemplate<T> {
    var template = PathTemplate<T>()
    template.append(path: lhs)
    template.append(keyPath: rhs)
    return template
}

// KeyPath + PathRepresentable
public func +<T, U: PathRepresentable, V: PathRepresentable>(lhs: KeyPath<T, V> & Sendable, rhs: U) -> PathTemplate<T> {
    var template = PathTemplate<T>()
    template.append(keyPath: lhs)
    template.append(path: rhs)
    return template
}

// Template + KeyPath
public func +<T, U: PathRepresentable>(lhs: PathTemplate<T>, rhs: KeyPath<T, U> & Sendable) -> PathTemplate<T> {
    var template = lhs
    template.append(keyPath: rhs)
    return template
}

// Template + PathRepresentable
public func +<T, U: PathRepresentable>(lhs: PathTemplate<T>, rhs: U) -> PathTemplate<T> {
    var template = lhs
    template.append(path: rhs)
    return template
}
