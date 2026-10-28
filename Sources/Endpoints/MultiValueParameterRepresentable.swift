/// A query or form parameter that sends repeated keys in value order.
///
/// Arrays drop nil elements; an empty array of values is omitted. If a type also conforms to
/// ``ParameterRepresentable``, its single-value representation takes precedence.
public protocol MultiValueParameterRepresentable {
    /// The values to send under repeated keys, in order. An empty array omits the parameter.
    var parameterValues: [String] { get }
}

extension Array: MultiValueParameterRepresentable where Element: ParameterRepresentable {
    /// Returns each element's parameter value in array order, dropping nil values.
    ///
    /// An empty result omits the parameter. A ``ParameterRepresentable`` conformance
    /// on the array takes precedence over this repeated-key representation.
    public var parameterValues: [String] { compactMap(\.parameterValue) }
}

extension Optional: MultiValueParameterRepresentable
where Wrapped: MultiValueParameterRepresentable {
    /// Returns the wrapped parameter values in order, or an empty array for `nil`.
    ///
    /// An empty result omits the parameter. A ``ParameterRepresentable`` conformance
    /// takes precedence over this repeated-key representation.
    public var parameterValues: [String] { self?.parameterValues ?? [] }
}
