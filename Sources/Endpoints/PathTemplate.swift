//
//  PathTemplate.swift
//  Endpoints
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

public protocol PathRepresentable {
    var pathSafe: String { get }
}

extension String: PathRepresentable {
    public var pathSafe: String {
        return self.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
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

public struct PathTemplate<T> {

    private struct RepresentableInfo: Equatable {
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
    private var keyPathComponents: [(Int, PartialKeyPath<T>, Bool)] = []

    private var currentIndex: Int = 0

    public init() { }

    mutating func append(path: PathRepresentable, indexOverride: Int? = nil, includesSlash: Bool = true) {
        if let index = indexOverride {
            pathComponents.append(RepresentableInfo(index: index, representable: path, includesSlash: includesSlash))
            currentIndex = index
        } else {
            pathComponents.append(RepresentableInfo(index: currentIndex, representable: path, includesSlash: includesSlash))
            currentIndex += 1
        }
    }

    mutating func append(keyPath: PartialKeyPath<T>, indexOverride: Int? = nil, includesSlash: Bool = true) {
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
            let insertion = component.representable.pathSafe

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

        mutating public func appendInterpolation<U: PathRepresentable>(path value: KeyPath<T, U>, includesSlash: Bool = true) {
            path.append(keyPath: value, includesSlash: includesSlash)
        }
    }
}

// PathRepresentable + KeyPath
public func +<T, U: PathRepresentable, V: PathRepresentable>(lhs: U, rhs: KeyPath<T, V>) -> PathTemplate<T> {
    var template = PathTemplate<T>()
    template.append(path: lhs)
    template.append(keyPath: rhs)
    return template
}

// KeyPath + PathRepresentable
public func +<T, U: PathRepresentable, V: PathRepresentable>(lhs: KeyPath<T, V>, rhs: U) -> PathTemplate<T> {
    var template = PathTemplate<T>()
    template.append(keyPath: lhs)
    template.append(path: rhs)
    return template
}

// Template + KeyPath
public func +<T, U: PathRepresentable>(lhs: PathTemplate<T>, rhs: KeyPath<T, U>) -> PathTemplate<T> {
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
