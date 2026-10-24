#if OpenAPIGenerator
import Foundation
import Yams

public struct Diagnostic: Equatable, Sendable {
    public enum Severity: String, Sendable { case error, warning, note }
    public let path: String
    public let line: Int
    public let column: Int
    public let pointer: String
    public let severity: Severity
    public let message: String
    public var formatted: String {
        let singleLine =
            message
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\(path):\(line):\(column): \(severity.rawValue): \(singleLine) [#\(pointer)]"
    }
    static func less(_ lhs: Self, _ rhs: Self) -> Bool {
        if !wireEqual(lhs.path, rhs.path) { return utf8Less(lhs.path, rhs.path) }
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        if lhs.column != rhs.column { return lhs.column < rhs.column }
        if !wireEqual(lhs.pointer, rhs.pointer) { return utf8Less(lhs.pointer, rhs.pointer) }
        if !wireEqual(lhs.message, rhs.message) { return utf8Less(lhs.message, rhs.message) }
        return utf8Less(lhs.severity.rawValue, rhs.severity.rawValue)
    }
}

func pointerPart(_ value: String) -> String {
    value.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
}

struct Source {
    let path: String
    let root: Node?
    func node(at pointer: String) -> Node? {
        var node = root
        for part in pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst() {
            let key = String(part).replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
            if let mapping = node?.mapping {
                node =
                    mapping.first(where: { $0.key.string.map { wireEqual($0, key) } == true })?
                    .value
            } else if let sequence = node?.sequence, let index = Int(key), index >= 0,
                index < sequence.count
            {
                node = sequence[index]
            } else {
                return nil
            }
        }
        return node
    }
    /// The pointer identifies a value, but the source diagnostic belongs on its
    /// authored mapping key. For a missing field, fall back to the closest parent.
    private func keyNode(at pointer: String) -> Node? {
        guard let separator = pointer.lastIndex(of: "/") else { return root }
        let parent = String(pointer[..<separator])
        let escaped = String(pointer[pointer.index(after: separator)...])
        let key = escaped.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(
            of: "~0", with: "~")
        if let mapping = node(at: parent)?.mapping,
            let pair = mapping.first(where: { $0.key.string.map { wireEqual($0, key) } == true }
            )
        {
            return pair.key
        }
        return node(at: pointer) ?? keyNode(at: parent)
    }

    func diagnostic(
        _ message: String, _ pointer: String = "", _ severity: Diagnostic.Severity = .error
    ) -> Diagnostic {
        let mark = keyNode(at: pointer)?.mark ?? node(at: pointer)?.mark
        return Diagnostic(
            path: path, line: mark?.line ?? 1, column: mark?.column ?? 1, pointer: pointer,
            severity: severity, message: message)
    }
}

func yamlFailure(_ error: Error, path: String, message: String) -> Diagnostic {
    let mark: Mark?
    switch error as? YamlError {
    case .scanner(_, _, let position, _), .parser(_, _, let position, _),
        .composer(_, _, let position, _):
        mark = position
    case .duplicatedKeysInMapping(_, let context): mark = context.mark
    default: mark = nil
    }
    return Diagnostic(
        path: path, line: mark?.line ?? 1, column: mark?.column ?? 1, pointer: "",
        severity: .error, message: message)
}
#endif
