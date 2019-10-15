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
    public var parameterValue: String? {
        return self
    }
}

extension Double: ParameterRepresentable {
    public var parameterValue: String? {
        return "\(self)"
    }
}

extension Int: ParameterRepresentable {
    public var parameterValue: String? {
        return "\(self)"
    }
}

extension Bool: ParameterRepresentable {
    public var parameterValue: String? {
        return self ? "true" : "false"
    }
}

extension Date: ParameterRepresentable {
    public var parameterValue: String? {
        return ISO8601DateFormatter.string(from: self,
                                           timeZone: Calendar.current.timeZone,
                                           formatOptions: [.withDay, .withMonth, .withYear, .withDashSeparatorInDate])
    }
}

extension TimeZone: ParameterRepresentable {
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
