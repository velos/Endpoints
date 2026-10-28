#if OpenAPIGenerator
extension Rendering {
    func statusUnion(_ declaration: TypeDecl, _ writer: inout CodeWriter) {
        writer.line("\(access)enum \(declaration.name): Decodable, Hashable, Sendable {")
        writer.indent()
        for outcome in declaration.outcomes {
            docs(outcome.docs, &writer)
            let payload = outcome.payload.map { "(" + $0.swift + ")" } ?? ""
            writer.line("case \(outcome.name)\(payload)")
        }
        for child in declaration.nested {
            writer.line()
            render(child, &writer)
        }
        writer.line()
        writer.line("\(access)init(from decoder: any Decoder) throws {")
        writer.indent()
        writer.line("guard let statusCode = decoder.userInfo[.httpStatusCode] as? Int else {")
        writer.indent()
        decodingError(
            "\(namespace) response requires the HTTP status code; decode with `HTTPResponseJSONDecoder.decode(_:from:response:)`.",
            &writer)
        writer.outdent()
        writer.line("}")
        writer.line("switch statusCode {")
        for outcome in dispatchOrder(declaration.outcomes) {
            writer.line(
                "\(outcome.match == .fallback ? "default" : "case " + outcome.match.pattern):")
            writer.indent()
            let payload =
                outcome.payload.map {
                    "(try decoder.singleValueContainer().decode(" + $0.swift + ".self))"
                } ?? ""
            writer.line("self = .\(outcome.name)\(payload)")
            writer.outdent()
        }
        if !declaration.outcomes.contains(where: { $0.match == .fallback }) {
            writer.line("default:")
            writer.indent()
            decodingError("Unexpected status code \\(statusCode).", &writer, interpolation: true)
            writer.outdent()
        }
        writer.line("}")
        writer.outdent()
        writer.line("}")
        writer.outdent()
        writer.line("}")
    }

    private func decodingError(
        _ message: String, _ writer: inout CodeWriter, interpolation: Bool = false
    ) {
        writer.line("throw DecodingError.dataCorrupted(DecodingError.Context(")
        writer.indent()
        writer.line("codingPath: decoder.codingPath,")
        let literal = interpolation ? "\"" + message + "\"" : swiftLiteral(message)
        writer.line("debugDescription: \(literal)")
        writer.outdent()
        writer.line("))")
    }

    /// Match exact codes before ranges, then default, regardless of authored order.
    /// Enum members themselves retain authored response order.
    private func dispatchOrder(_ outcomes: [StatusOutcome]) -> [StatusOutcome] {
        func priority(_ match: StatusMatch) -> Int {
            switch match {
            case .code: return 0
            case .range: return 1
            case .fallback: return 2
            }
        }
        return outcomes.enumerated().sorted {
            let lhs = priority($0.element.match)
            let rhs = priority($1.element.match)
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
    }

    /// Remove redundant arms, treating 204 as don't-care because its body is discarded.
    /// Exact exceptions to ranges survive; ranges inherit the default result.
    private func rawStatusSelection(_ outcomes: [StatusOutcome]) -> RawStatusSelection {
        let ordered = dispatchOrder(outcomes)
        // Unmatched union statuses ignore the body so dispatch can report the status code.
        let defaultValue = ordered.first { $0.match == .fallback }?.rawBody ?? (outcomes.count > 1)
        let arms = ordered.filter { outcome in
            switch outcome.match {
            case .code(204):
                // Definition.responseWithMetadata discards every 204 body before decoding.
                return false
            case .code(let status):
                let range = ordered.first {
                    if case .range(let hundreds) = $0.match {
                        return status / 100 == hundreds
                    }
                    return false
                }
                return outcome.rawBody != (range?.rawBody ?? defaultValue)
            case .range: return outcome.rawBody != defaultValue
            case .fallback: return false
            }
        }
        return RawStatusSelection(arms: arms, defaultValue: defaultValue)
    }

    private struct RawStatusSelection {
        let arms: [StatusOutcome]
        let defaultValue: Bool

        var predicate: String? {
            guard
                arms.allSatisfy({ outcome in
                    if case .code = outcome.match { return true }
                    return false
                })
            else {
                return nil
            }
            guard !arms.isEmpty else { return "_ in " + String(defaultValue) }
            let comparisons = arms.map { "$0 " + (defaultValue ? "!= " : "== ") + $0.match.pattern }
            return comparisons.joined(separator: defaultValue ? " && " : " || ")
        }
    }

    func decoderOverride(
        _ name: String, outcomes: [StatusOutcome], _ writer: inout CodeWriter
    ) {
        let selection = rawStatusSelection(outcomes)
        if selection.arms.isEmpty && !selection.defaultValue {
            writer.line(
                "\(access)static var \(name): HTTPResponseJSONDecoder { \(namespace).JSONCoding.makeDecoder() }"
            )
            return
        }
        writer.line("\(access)static var \(name): HTTPResponseJSONDecoder {")
        writer.indent()
        if let predicate = selection.predicate {
            writer.line("\(namespace).JSONCoding.makeDecoder(isRawDataStatus: { \(predicate) })")
        } else {
            writer.line("\(namespace).JSONCoding.makeDecoder(isRawDataStatus: { statusCode in")
            writer.indent()
            writer.line("switch statusCode {")
            for outcome in selection.arms {
                writer.line("case \(outcome.match.pattern):")
                writer.indent()
                writer.line("return \(outcome.rawBody)")
                writer.outdent()
            }
            writer.line("default:")
            writer.indent()
            writer.line("return \(selection.defaultValue)")
            writer.outdent()
            writer.line("}")
            writer.outdent()
            writer.line("})")
        }
        writer.outdent()
        writer.line("}")
    }
}
#endif
