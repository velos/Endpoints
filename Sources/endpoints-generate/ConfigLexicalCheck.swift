#if OpenAPIGenerator
import EndpointsGeneratorConfig
import Foundation

struct ConfigIssue: Error, Equatable {
    let line: Int
    let column: Int
    let message: String
    func formatted(path: String) -> String { "\(path):\(line):\(column): error: \(message)" }
}

/// Byte lexer: literals/comments are opaque, interpolation resumes the code lexer.
enum ConfigLexicalCheck {
    struct Token {
        let value: String
        let line: Int
        let column: Int
        let depth: Int
    }
    static func entrySymbol(stem: String) -> String {
        (Naming.camel(stem, upper: false) ?? stem) + "Configuration"
    }
    static func entryMessage(stem: String) -> String {
        "configuration must declare exactly one 'let \(entrySymbol(stem: stem)): EndpointsConfiguration'"
    }
    static func check(_ data: Data, stem: String) -> [ConfigIssue] {
        analyze(data, stem: stem).issues
    }
    static func analyze(_ data: Data, stem: String)
        -> (issues: [ConfigIssue], entryLine: Int, entryColumn: Int)
    {
        var lexer = Lexer(bytes: Array(data))
        lexer.code()
        var issues = lexer.issues
        let text = String(decoding: data, as: UTF8.self)
        let first =
            text.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init)
            ?? ""
        if first.trimmingCharacters(in: .whitespacesAndNewlines)
            != "// endpoints-configuration-version: 1"
            || !first.hasPrefix("// endpoints-configuration-version: 1")
        {
            issues.insert(
                ConfigIssue(
                    line: 1, column: 1,
                    message: "first line must be '// endpoints-configuration-version: 1'"), at: 0)
        }
        if Array(text.utf8) != Array(data) {
            issues.append(
                ConfigIssue(line: 1, column: 1, message: "configuration file must be UTF-8"))
        }
        let tokens = lexer.tokens
        for (i, token) in tokens.enumerated() where token.value == "@" {
            var next = i + 1
            if next < tokens.count && tokens[next].value == "`" { next += 1 }
            if next < tokens.count && tokens[next].value.hasPrefix("_") {
                issues.append(
                    ConfigIssue(
                        line: token.line, column: token.column,
                        message: "underscored attributes are not allowed in configuration files"))
            }
            if next < tokens.count && tokens[next].value == "unchecked" {
                issues.append(
                    ConfigIssue(
                        line: token.line, column: token.column,
                        message: "unchecked conformances are not allowed in configuration files"))
            }
        }
        let kinds = ["typealias", "struct", "class", "enum", "protocol", "let", "var", "func"]
        for (i, token) in tokens.enumerated() where token.value == "import" {
            var next = i + 1
            if next < tokens.count && kinds.contains(tokens[next].value) { next += 1 }
            if next >= tokens.count || tokens[next].value != "EndpointsGeneratorConfig"
                || (next + 1 < tokens.count && tokens[next + 1].value == ".")
            {
                issues.append(
                    ConfigIssue(
                        line: token.line, column: token.column,
                        message: "configuration files may only import EndpointsGeneratorConfig"))
            }
        }
        for (i, token) in tokens.enumerated() {
            let following = tokens.dropFirst(i + 1).lazy.filter { $0.value != "`" }
            let preceding = tokens[..<i].last { $0.value != "`" }?.value
            if ["class", "actor"].contains(token.value),
                !["for", "case", ".", "let", "var"].contains(preceding),
                let next = following.first,
                let byte = next.value.utf8.first,
                ASCII.isAlnum(byte) || byte == 95 || byte >= 128
            {
                issues.append(ConfigIssue(
                    line: token.line, column: token.column,
                    message: "reference-type declarations are not allowed in configuration files"))
            }
            if token.value == "hash", following.prefix(3).map(\.value) == ["(", "into", ":"] {
                issues.append(ConfigIssue(
                    line: token.line, column: token.column,
                    message: "'hash(into:)' is not allowed in configuration files"))
            }
        }
        let symbol = entrySymbol(stem: stem)
        let declarations = tokens.indices.filter { i in
            tokens[i].depth == 0 && ["let", "var"].contains(tokens[i].value)
                && i + 1 < tokens.count && tokens[i + 1].value == symbol
        }
        let message = entryMessage(stem: stem)
        if declarations.isEmpty { issues.append(ConfigIssue(line: 1, column: 1, message: message)) }
        for index in declarations where tokens[index].value != "let" || declarations.count > 1 {
            issues.append(
                ConfigIssue(
                    line: tokens[index].line, column: tokens[index].column, message: message))
        }
        return (
            issues.sorted { ($0.line, $0.column, $0.message) < ($1.line, $1.column, $1.message) },
            declarations.first.map { tokens[$0].line } ?? 1,
            declarations.first.map { tokens[$0].column } ?? 1
        )
    }

    private struct Lexer {
        let bytes: [UInt8]
        var index = 0
        var line = 1
        var column = 1
        var depth = 0
        var tokens: [Token] = []
        var issues: [ConfigIssue] = []
        func has(_ chars: [UInt8]) -> Bool { bytes[index...].starts(with: chars) }
        mutating func advance(_ count: Int = 1) {
            for _ in 0..<count where index < bytes.count {
                if bytes[index] == 10 {
                    line += 1
                    column = 1
                } else {
                    column += 1
                }
                index += 1
            }
        }
        func identifier(_ byte: UInt8) -> Bool { ASCII.isAlnum(byte) || byte == 95 || byte >= 128 }
        mutating func word() -> String {
            let start = index
            while index < bytes.count && identifier(bytes[index]) { advance() }
            return String(decoding: bytes[start..<index], as: UTF8.self)
        }
        mutating func code(interpolation: Bool = false) {
            var parens = interpolation ? 1 : 0
            while index < bytes.count {
                if has([47, 47]) {
                    while index < bytes.count && bytes[index] != 10 { advance() }
                    continue
                }
                if has([47, 42]) {
                    advance(2)
                    var level = 1
                    while index < bytes.count && level > 0 {
                        if has([47, 42]) {
                            level += 1
                            advance(2)
                        } else if has([42, 47]) {
                            level -= 1
                            advance(2)
                        } else {
                            advance()
                        }
                    }
                    continue
                }
                if bytes[index] == 47, index + 1 < bytes.count {
                    func whitespace(_ byte: UInt8) -> Bool { [9, 10, 11, 12, 13, 32].contains(byte) }
                    let assignment = has([47, 61]) && index + 2 < bytes.count
                        && whitespace(bytes[index + 2])
                    if !whitespace(bytes[index + 1]) && !assignment {
                        issues.append(ConfigIssue(
                            line: line, column: column,
                            message: "regex literals are not allowed in configuration files; "
                                + "put spaces around '/' for division"))
                        // This line is already invalid. Do not interpret regex quotes or
                        // comment-looking contents as strings/comments in subsequent lines.
                        while index < bytes.count && bytes[index] != 10 { advance() }
                        continue
                    }
                }
                if bytes[index] == 92 {
                    issues.append(ConfigIssue(
                        line: line, column: column,
                        message: "key-path expressions are not allowed in configuration files"))
                    advance()
                    continue
                }
                if has([61, 61, 61]) || has([33, 61, 61]) {
                    issues.append(ConfigIssue(
                        line: line, column: column,
                        message: "identity operators are not allowed in configuration files"))
                    advance(3)
                    continue
                }
                if bytes[index] == 34 {
                    literal(hashes: 0)
                    continue
                }
                if bytes[index] == 35 {
                    var end = index
                    while end < bytes.count && bytes[end] == 35 { end += 1 }
                    if end < bytes.count && bytes[end] == 34 {
                        let count = end - index
                        advance(count)
                        literal(hashes: count)
                        continue
                    }
                    let position = (line, column)
                    advance()
                    let name = word()
                    let conditional = ["if", "elseif", "else", "endif"].contains(name)
                    issues.append(
                        ConfigIssue(
                            line: position.0, column: position.1,
                            message: conditional
                                ? "conditional compilation is not allowed in configuration files"
                                : "# directives and literals are not allowed in configuration files"
                        ))
                    continue
                }
                if bytes[index] == 64 {
                    tokens.append(Token(value: "@", line: line, column: column, depth: depth))
                    advance()
                    continue
                }
                if identifier(bytes[index]) {
                    let position = (line, column)
                    let name = word()
                    let attribute =
                        tokens.last?.value == "@"
                        || (tokens.last?.value == "`" && tokens.dropLast().last?.value == "@")
                    let implementationHook = name.hasPrefix("_") && name != "_" && !attribute
                    tokens.append(
                        Token(value: name, line: position.0, column: position.1, depth: depth))
                    if [
                        "unsafe", "objectidentifier", "random", "shuffle", "memorylayout", "commandline",
                        "readline",
                        "clock", "task", "async", "await",
                        "unmanaged", "pointer", "address", "withcstring", "withutf8",
                        "withcontiguous", "withvalist", "getvalist", "mirror",
                    ].contains(where: { ASCII.lower(name).contains($0) }) || implementationHook
                        || ["ObjectIdentifier", "Unmanaged", "MemoryLayout", "Mirror", "Hasher",
                            "hashValue", "CommandLine"].contains(name)
                        || ["unsafe", "Unsafe", "withUnsafe"].contains(where: name.hasPrefix)
                    {
                        issues.append(
                            ConfigIssue(
                                line: position.0, column: position.1,
                                message: "'\(name)' is not allowed in configuration files"))
                    }
                    continue
                }
                let byte = bytes[index]
                if interpolation {
                    if byte == 40 { parens += 1 }
                    if byte == 41 {
                        parens -= 1
                        if parens == 0 {
                            advance()
                            return
                        }
                    }
                }
                if byte == 123 { depth += 1 }
                if byte == 125 { depth = max(0, depth - 1) }
                if [46, 59, 61, 58, 96, 40, 41, 123, 125, 44].contains(byte) {
                    tokens.append(
                        Token(
                            value: String(UnicodeScalar(byte)), line: line, column: column,
                            depth: depth))
                }
                advance()
            }
        }
        mutating func literal(hashes: Int) {
            let quotes = has([34, 34, 34]) ? 3 : 1
            advance(quotes)
            let end =
                Array(repeating: UInt8(34), count: quotes)
                + Array(repeating: UInt8(35), count: hashes)
            let escape = [UInt8(92)] + Array(repeating: UInt8(35), count: hashes)
            while index < bytes.count {
                if has(end) {
                    advance(end.count)
                    return
                }
                if has(escape) {
                    advance(escape.count)
                    if index < bytes.count && bytes[index] == 40 {
                        advance()
                        code(interpolation: true)
                    } else {
                        advance()
                    }
                } else {
                    advance()
                }
            }
        }
    }
}
#endif
