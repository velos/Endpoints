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

extension Int: PathRepresentable {
    public var pathSafe: String {
        return "\(self)"
    }
}

public struct PathTemplate<T> {

    private var pathComponents: [(Int, PathRepresentable)] = []
    private var keyPathComponents: [(Int, PartialKeyPath<T>)] = []

    private var currentIndex: Int = 0

    public init() { }

    mutating func append(path: PathRepresentable) {
        pathComponents.append((currentIndex, path))
        currentIndex += 1
    }

    mutating func append(keyPath: PartialKeyPath<T>) {
        keyPathComponents.append((currentIndex, keyPath))
        currentIndex += 1
    }

    mutating func append(template: PathTemplate<T>) {
        for (_, pathComponent) in template.pathComponents {
            append(path: pathComponent)
        }

        for (_, keyPathComponent) in template.keyPathComponents {
            append(keyPath: keyPathComponent)
        }
    }

    public func path(with value: T) -> String {
        let values = keyPathComponents.map { (index, path) -> (Int, PathRepresentable) in
            return (index, value[keyPath: path] as! PathRepresentable)
        }

        var allComponents = pathComponents + values
        allComponents.sort(by: { (first, second) -> Bool in
            return first.0 < second.0
        })

        return NSString.path(withComponents: allComponents.map { $0.1.pathSafe })
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
            path.append(path: literal)
        }

        mutating public func appendInterpolation<U: PathRepresentable>(path value: KeyPath<T, U>) {
            path.append(keyPath: value)
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
