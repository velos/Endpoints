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

public struct PathTemplate<T>: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String
    private var pathComponents: [(Int, PathRepresentable)] = []
    private var keyPathComponents: [(Int, PartialKeyPath<T>)] = []

    private var currentIndex: Int = 0

    public init() { }

    public init(stringLiteral: String) {
        append(path: stringLiteral)
    }

    mutating func append(path: PathRepresentable) {
        // blah
        pathComponents.append((currentIndex, path))
        currentIndex += 1
    }

    mutating func append(keyPath: PartialKeyPath<T>) {
        // blah
        keyPathComponents.append((currentIndex, keyPath))
        currentIndex += 1
    }

    mutating func append(template: PathTemplate<T>) {
        pathComponents.append(contentsOf: template.pathComponents)
        keyPathComponents.append(contentsOf: template.keyPathComponents)
    }

    func path(with value: T) -> String {
        let values = keyPathComponents.map { (index, path) -> (Int, PathRepresentable) in
            guard let safe = value[keyPath: path] as? PathRepresentable else {
                fatalError("should be a PathRepresentable")
            }

            return (index, safe)
        }

        var allComponents = pathComponents + values
        allComponents.sort(by:  { (first, second) -> Bool in
            return first.0 < second.0
        })

        return NSString.path(withComponents: allComponents.map { $0.1.pathSafe })
    }
}

// PathRepresentable + KeyPath
func +<T, U: PathRepresentable, V: PathRepresentable>(lhs: U, rhs: KeyPath<T, V>) -> PathTemplate<T> {
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

// Template + Template
public func +<T>(lhs: PathTemplate<T>, rhs: PathTemplate<T>) -> PathTemplate<T> {
    var template = lhs
    template.append(template: rhs)
    return template
}

// KeyPath + Template
public func +<T, U: PathRepresentable>(lhs: KeyPath<T, U>, rhs: PathTemplate<T>) -> PathTemplate<T> {
    var template = PathTemplate<T>()
    template.append(keyPath: lhs)
    template.append(template: rhs)
    return template
}

// PathRepresentable + Template
public func +<T, U: PathRepresentable>(lhs: U, rhs: PathTemplate<T>) -> PathTemplate<T> {
    var template = PathTemplate<T>()
    template.append(path: lhs)
    template.append(template: rhs)
    return template
}
