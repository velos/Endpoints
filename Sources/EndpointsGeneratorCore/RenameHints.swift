#if OpenAPIGenerator
enum RenameCategory: String {
    case schemas, operations, properties
}

/// A JSON-subscript hint that can be copied even when a wire identity contains
/// punctuation, quotes or control characters. Escape scalars without a serializer.
func renameHint(_ category: RenameCategory, _ original: String) -> String {
    var key = "\""
    for scalar in original.unicodeScalars {
        switch scalar.value {
        case 0x22: key += "\\\""
        case 0x5c: key += "\\\\"
        case 0x08: key += "\\b"
        case 0x0c: key += "\\f"
        case 0x0a: key += "\\n"
        case 0x0d: key += "\\r"
        case 0x09: key += "\\t"
        case 0...0x1f:
            let digits = String(scalar.value, radix: 16)
            key += "\\u" + String(repeating: "0", count: 4 - digits.count) + digits
        default: key.unicodeScalars.append(scalar)
        }
    }
    return "renames." + category.rawValue + "[" + key + "\"]"
}
#endif
