#if OpenAPIGenerator
import Foundation

/// A compiler header and its unchanged source excerpts, fix-its, and continuation lines.
struct CompilerDiagnosticBlock {
    let path: String
    let severity: String
    let text: String

    static func parse(_ text: String) -> [Self] {
        let expression = try! NSRegularExpression(
            pattern: #"^(.+):([0-9]+):([0-9]+): (error|warning|note|remark):"#,
            options: .anchorsMatchLines)
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.enumerated().map { index, match in
            let start = Range(match.range, in: text)!.lowerBound
            let end = index + 1 < matches.count
                ? Range(matches[index + 1].range, in: text)!.lowerBound : text.endIndex
            return Self(
                path: String(text[Range(match.range(at: 1), in: text)!]),
                severity: String(text[Range(match.range(at: 4), in: text)!]),
                text: String(text[start..<end]))
        }
    }
}
#endif
