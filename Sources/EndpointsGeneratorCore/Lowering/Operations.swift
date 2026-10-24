#if OpenAPIGenerator
import OpenAPIKit

extension Lowering {
    struct ResponseInput {
        let status: String
        let response: Either<OpenAPI.Reference<OpenAPI.Response>, OpenAPI.Response>
    }

    mutating func parameterType(
        _ originalSchema: JSONSchema, suggested: String, path: String, owner: String,
        pointer: String, nested: inout [TypeDecl]
    ) throws -> TypeRef {
        let schema = try lookup.schema(originalSchema)
        if schema.allowedValues?.isEmpty == false {
            return try type(
                originalSchema, suggested: suggested, path: path, owner: owner,
                pointer: pointer, nested: &nested)
        }
        switch schema.value {
        case .string:
            if ["date", "date-time", "uri"].contains(schema.formatString ?? "") { return .string }
        case .integer, .number, .boolean: break
        case .array(_, let array):
            guard let items = array.items, array.prefixItems == nil else {
                throw unsupported("parameter arrays require one items schema", pointer)
            }
            let element = try parameterType(
                items, suggested: suggested + "Item", path: path, owner: owner,
                pointer: pointer + "/items", nested: &nested)
            return .array(nullable(items) ? .optional(element) : element)
        default: throw unsupported("object or composite parameter", pointer)
        }
        return try type(
            schema, suggested: suggested, path: path, owner: owner, pointer: pointer,
            nested: &nested)
    }

    func responseType(_ outcomes: [StatusOutcome], name: String, path: String) -> TypeRef {
        outcomes.count == 1 ? outcomes[0].payload ?? .void : .named(path + "." + name)
    }

    mutating func responseOutcomes(
        _ inputs: [ResponseInput], name: String, method: HTTPMethod, path: String,
        owner: String, pointer: String, nested: inout [TypeDecl]
    ) throws -> [StatusOutcome] {
        var outcomes: [StatusOutcome] = []
        var unionChildren: [TypeDecl] = []
        var names = NameAllocator(reserved: ["init", "hashValue", "DiscriminatorKeys"])
        for (index, input) in inputs.enumerated() {
            let located = try lookup.resolve(input.response, at: pointer + "/" + input.status)
            let match: StatusMatch
            switch input.status {
            case "2XX": match = .range(2)
            case "4XX": match = .range(4)
            case "5XX": match = .range(5)
            case "default": match = .fallback
            default:
                guard let code = Int(input.status) else {
                    throw unsupported("response status '\(input.status)'", located.pointer)
                }
                match = .code(code)
            }
            let caseName = statusCaseName(match)
            try names.claim(caseName, original: input.status, hint: "distinct response statuses")
            var outcome = StatusOutcome(
                name: caseName, match: match,
                docs: ["`\(input.status)`: " + (located.value.description ?? "")])
            if input.status != "204", method != .head,
                let media = try selectedMedia(
                    located.value.content, pointer: located.pointer + "/content")
            {
                if isJSON(media.name) {
                    guard let schema = media.value.schema else {
                        throw unsupported("JSON responses require a schema", media.pointer)
                    }
                    if inputs.count == 1 {
                        outcome.payload = try payload(
                            schema, name: name, path: path, owner: owner,
                            pointer: media.pointer + "/schema", nested: &nested)
                    } else {
                        // Inline union members live inside the union, as in §5.6.
                        outcome.payload = try payload(
                            schema, name: "Option\(index + 1)", path: path + "." + name,
                            owner: owner, pointer: media.pointer + "/schema", nested: &unionChildren
                        )
                    }
                } else {
                    outcome.payload = .data
                    outcome.rawBody = true
                }
            }
            if inputs.count > 1, outcome.payload == nil {
                // Body-less union cases ignore any bytes, just like a Void response.
                outcome.rawBody = true
            }
            outcomes.append(outcome)
        }
        if inputs.count > 1 {
            var union = TypeDecl(name: name, kind: .statusUnion, outcomes: outcomes)
            union.nested = unionChildren.sorted { utf8Less($0.name, $1.name) }
            var allocator = NameAllocator(
                reserved: Naming.namespaceReserved.union([namespace, name]))
            for child in union.nested {
                try allocator.claim(
                    child.name, original: child.name, hint: renameHint(.operations, owner))
            }
            nested.append(union)
        }
        return outcomes
    }
}

/// Frozen reason-phrase spellings from the IANA HTTP status code registry.
/// https://www.iana.org/assignments/http-status-codes (2025-09-15 registry revision).
/// Unknown or unassigned statuses retain their numeric identity.
func statusCaseName(_ match: StatusMatch) -> String {
    switch match {
    case .fallback: return "defaultResponse"
    case .range(2): return "success"
    case .range(4): return "clientError"
    case .range(5): return "serverError"
    case .range(let hundreds): return "status\(hundreds)XX"
    case .code(let code):
        switch code {
        case 200: return "ok"
        case 201: return "created"
        case 202: return "accepted"
        case 203: return "nonAuthoritativeInformation"
        case 204: return "noContent"
        case 205: return "resetContent"
        case 206: return "partialContent"
        case 207: return "multiStatus"
        case 208: return "alreadyReported"
        case 226: return "imUsed"
        case 400: return "badRequest"
        case 401: return "unauthorized"
        case 402: return "paymentRequired"
        case 403: return "forbidden"
        case 404: return "notFound"
        case 405: return "methodNotAllowed"
        case 406: return "notAcceptable"
        case 407: return "proxyAuthenticationRequired"
        case 408: return "requestTimeout"
        case 409: return "conflict"
        case 410: return "gone"
        case 411: return "lengthRequired"
        case 412: return "preconditionFailed"
        case 413: return "contentTooLarge"
        case 414: return "uriTooLong"
        case 415: return "unsupportedMediaType"
        case 416: return "rangeNotSatisfiable"
        case 417: return "expectationFailed"
        case 421: return "misdirectedRequest"
        case 422: return "unprocessableContent"
        case 423: return "locked"
        case 424: return "failedDependency"
        case 425: return "tooEarly"
        case 426: return "upgradeRequired"
        case 428: return "preconditionRequired"
        case 429: return "tooManyRequests"
        case 431: return "requestHeaderFieldsTooLarge"
        case 451: return "unavailableForLegalReasons"
        case 500: return "internalServerError"
        case 501: return "notImplemented"
        case 502: return "badGateway"
        case 503: return "serviceUnavailable"
        case 504: return "gatewayTimeout"
        case 505: return "httpVersionNotSupported"
        case 506: return "variantAlsoNegotiates"
        case 507: return "insufficientStorage"
        case 508: return "loopDetected"
        case 510: return "notExtended"
        case 511: return "networkAuthenticationRequired"
        default: return "status\(code)"
        }
    }
}
#endif
