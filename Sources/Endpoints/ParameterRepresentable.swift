//
//  ParameterRepresentable.swift
//  Endpoints
//
//  Created by Zac White on 2/1/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

/// A type that can be sent as a query or form parameter value.
public protocol ParameterRepresentable {
    /// The value to send, or `nil` to leave the parameter out.
    var parameterValue: String? { get }
}

extension String: ParameterRepresentable {

    /// Returns the string.
    public var parameterValue: String? {
        return self
    }
}

extension Double: ParameterRepresentable {

    /// Returns the value as a string.
    public var parameterValue: String? {
        return "\(self)"
    }
}

extension Int: ParameterRepresentable {

    /// Returns the value as a string.
    public var parameterValue: String? {
        return "\(self)"
    }
}

extension Bool: ParameterRepresentable {

    /// Returns `"true"` or `"false"`.
    public var parameterValue: String? {
        return self ? "true" : "false"
    }
}

extension Date: ParameterRepresentable {

    /// Returns the date in ISO 8601 format.
    public var parameterValue: String? {
        return ISO8601DateFormatter.string(from: self,
                                           timeZone: Calendar.current.timeZone,
                                           formatOptions: [.withDay, .withMonth, .withYear, .withDashSeparatorInDate])
    }
}

extension TimeZone: ParameterRepresentable {

    /// Returns the time zone's identifier.
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
