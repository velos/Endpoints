//
//  ParameterRepresentable.swift
//  Endpoints
//
//  Created by Zac White on 2/1/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

/// A type that can be converted for use on the value of a Parameter
public protocol ParameterRepresentable {
    /// Returns a path safe version for use in query parameters
    var parameterValue: String? { get }
}

extension String: ParameterRepresentable {

    /// Returns `self` as the parameter representable version.
    public var parameterValue: String? {
        return self
    }
}

extension Double: ParameterRepresentable {

    /// Returns a string representation of the `Double` value.
    public var parameterValue: String? {
        return "\(self)"
    }
}

extension Int: ParameterRepresentable {

    /// Returns a string representation of the `Int` value.
    public var parameterValue: String? {
        return "\(self)"
    }
}

extension Bool: ParameterRepresentable {

    /// Returns "true" and "false" based on the value of `self`.
    public var parameterValue: String? {
        return self ? "true" : "false"
    }
}

extension Date: ParameterRepresentable {

    /// Returns an ISO8601 formatted string for the value of `self`.
    public var parameterValue: String? {
        return ISO8601DateFormatter.string(from: self,
                                           timeZone: Calendar.current.timeZone,
                                           formatOptions: [.withDay, .withMonth, .withYear, .withDashSeparatorInDate])
    }
}

extension TimeZone: ParameterRepresentable {

    /// Returns the `identifier` string of this `TimeZone`.
    public var parameterValue: String? {
        return self.identifier
    }
}

extension Optional: ParameterRepresentable where Wrapped: ParameterRepresentable {
    public var parameterValue: String? {
        switch self {
        case .some(let value):
            return value.parameterValue
        case .none:
            return nil
        }
    }
}
