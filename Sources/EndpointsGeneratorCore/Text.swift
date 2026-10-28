#if OpenAPIGenerator
import Foundation

/// Ordering for all declarations and diagnostic tie breakers. Never locale dependent.
func utf8Less(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
}

/// Wire identities compare bytes rather than Unicode canonical equivalence.
func wireEqual(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.elementsEqual(rhs.utf8)
}

/// A Swift string literal, including quotes; interpolation and control scalars are escaped.
func swiftLiteral(_ value: String) -> String {
    var result = "\""
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x22: result += "\\\""
        case 0x5c: result += "\\\\"
        case 0x0a: result += "\\n"
        case 0x0d: result += "\\r"
        case 0x09: result += "\\t"
        case 0...0x1f, 0x7f, 0x85, 0x2028, 0x2029, 0xfeff:
            result += "\\u{\(String(scalar.value, radix: 16))}"
        default: result.unicodeScalars.append(scalar)
        }
    }
    return result + "\""
}

public struct CodeWriter {
    private var lines: [String] = []
    private var depth = 0
    public init() {}

    public mutating func line(_ text: String = "") {
        for part in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
            of: "\r", with: "\n"
        ).components(separatedBy: "\n") {
            let trimmed = String(
                part.reversed().drop(while: { $0 == " " || $0 == "\t" }).reversed())
            if trimmed.isEmpty {
                if lines.last != "", !lines.isEmpty { lines.append("") }
            } else {
                precondition(!trimmed.contains("\t") && !trimmed.contains("\u{feff}"))
                lines.append(String(repeating: " ", count: depth * 4) + trimmed)
            }
        }
    }

    var indentationWidth: Int { depth * 4 }

    public mutating func indent() { depth += 1 }
    public mutating func outdent() {
        precondition(depth > 0)
        depth -= 1
    }
    public func finish() -> String {
        precondition(depth == 0)
        let result =
            lines.reversed().drop(while: { $0.isEmpty }).reversed().joined(separator: "\n")
            + "\n"
        assert(!result.contains("\r") && !result.contains("\n\n\n") && !result.contains(" \n"))
        return result
    }
}
#endif
