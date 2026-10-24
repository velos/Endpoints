import Foundation

extension ParameterRepresentable where Self: RawRepresentable, RawValue: ParameterRepresentable {
    /// Returns the raw value's parameter value.
    public var parameterValue: String? { rawValue.parameterValue }
}

extension PathRepresentable where Self: RawRepresentable, RawValue: PathRepresentable {
    /// Returns the raw value's path-safe representation.
    public var pathSafe: String { rawValue.pathSafe }
}

extension Int32: ParameterRepresentable {
    /// Returns the value as a string.
    public var parameterValue: String? { String(self) }
}

extension Int32: PathRepresentable {
    /// Returns the value as a string.
    public var pathSafe: String { String(self) }
}

extension Int64: ParameterRepresentable {
    /// Returns the value as a string.
    public var parameterValue: String? { String(self) }
}

extension Int64: PathRepresentable {
    /// Returns the value as a string.
    public var pathSafe: String { String(self) }
}

extension UUID: ParameterRepresentable {
    /// Returns the UUID string.
    public var parameterValue: String? { uuidString }
}

extension UUID: PathRepresentable {
    /// Returns the UUID string.
    public var pathSafe: String { uuidString }
}
