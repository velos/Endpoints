#if OpenAPIGenerator
import EndpointsGeneratorConfig
import OpenAPIKit

extension Lowering {
    private struct SecurityAdvice {
        let summary: String
        let expression: String?
    }

    func securityDocumentation() throws -> [String] {
        let schemes = document.components.securitySchemes.sorted {
            utf8Less($0.key.rawValue, $1.key.rawValue)
        }
        guard !schemes.isEmpty else { return [] }
        // A security requirement is a dictionary (AND); choose its first scheme
        // by byte order. Requirements themselves are an ordered OR array.
        let requirementName = document.security.first?.keys.compactMap(\.name).sorted(
            by: utf8Less
        ).first
        let selected =
            schemes.first { entry in
                requirementName.map { wireEqual(entry.key.rawValue, $0) } == true
            } ?? schemes[0]
        let selectedScheme = try lookup.resolve(
            selected.value,
            at: "/components/securitySchemes/" + pointerPart(selected.key.rawValue))
        let advice = securityAdvice(selectedScheme.value)
        let exampleLine =
            advice.expression.map { config.access + "static let auth = " + $0 }
            ?? "// " + advice.summary
        let example = """
                extension \(namespace).Server {
                    \(exampleLine)
                }
            """
        let list = try schemes.map { entry in
            let located = try lookup.resolve(
                entry.value,
                at: "/components/securitySchemes/" + pointerPart(entry.key.rawValue))
            return "- `\(entry.key.rawValue)`: " + securityAdvice(located.value).summary
        }.joined(separator: "\n")
        return [
            "Security schemes declared by the spec. Credentials are runtime state, so attach them\nin your own file in this module:",
            example,
            list,
        ]
    }

    private func securityAdvice(_ scheme: OpenAPI.SecurityScheme) -> SecurityAdvice {
        switch scheme.type {
        case .apiKey(let name, let location):
            switch location {
            case .header:
                return SecurityAdvice(
                    summary: "apiKey in header `\(name)` (`HeaderKeyAuth`)",
                    expression:
                        "HeaderKeyAuth(key: apiKey, header: \(swiftLiteral(name)), prefix: nil)"
                )
            case .cookie:
                return SecurityAdvice(
                    summary: "apiKey in cookie `\(name)` (`CookieAuth`)",
                    expression: "CookieAuth(name: \(swiftLiteral(name)), value: apiKey)"
                )
            case .query:
                return SecurityAdvice(
                    summary:
                        "apiKey in query `\(name)` is not supported by Auth; use `requestProcessor`",
                    expression: nil
                )
            }
        case .http(let scheme, _):
            switch Naming.asciiLower(scheme) {
            case "bearer":
                return SecurityAdvice(
                    summary: "http bearer (`HeaderKeyAuth` or `JWTAuth`)",
                    expression: "HeaderKeyAuth(key: token)"
                )
            case "basic":
                return SecurityAdvice(
                    summary: "http basic (`BasicAuth`)",
                    expression: "BasicAuth(username: username, password: password)"
                )
            default:
                return SecurityAdvice(
                    summary:
                        "http `\(scheme)` requires a custom authentication method or `requestProcessor`",
                    expression: nil
                )
            }
        case .oauth2:
            return SecurityAdvice(
                summary: "oauth2 (`JWTAuth`)",
                expression: "JWTAuth(initialTokens: tokens, refreshHandler: refreshTokens)"
            )
        case .openIdConnect:
            return SecurityAdvice(
                summary: "openIdConnect (`JWTAuth`)",
                expression: "JWTAuth(initialTokens: tokens, refreshHandler: refreshTokens)"
            )
        case .mutualTLS:
            return SecurityAdvice(
                summary: "mutualTLS; configure the session’s client certificate",
                expression: nil
            )
        }
    }
}
#endif
