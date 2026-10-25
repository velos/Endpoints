#if OpenAPIGenerator
import EndpointsGeneratorConfig
import OpenAPIKit

/// Shared by inventory and lowering so unsupported locations never acquire another role.
func supportedParameterLocation(_ location: OpenAPI.Parameter.Context.Location)
    -> ParameterLocation?
{
    switch location {
    case .path: return .path
    case .query: return .query
    case .header: return .header
    case .cookie, .querystring: return nil
    }
}

struct SelectedMedia {
    let name: String
    let value: OpenAPI.Content
    let pointer: String
}

func selectedMedia(_ content: OpenAPI.Content.Map, pointer: String, lookup: ComponentLookup) throws
    -> SelectedMedia?
{
    let items = Array(content)
    guard
        let selected = items.first(where: { $0.key.rawValue == "application/json" })
            ?? items.first(where: { $0.key.rawValue.hasSuffix("+json") }) ?? items.first
    else { return nil }
    let located = try lookup.resolve(
        selected.value, at: pointer + "/" + pointerPart(selected.key.rawValue))
    return SelectedMedia(
        name: selected.key.rawValue, value: located.value, pointer: located.pointer)
}

func isJSON(_ media: String) -> Bool { media == "application/json" || media.hasSuffix("+json") }

struct JSONRequestBody {
    let media: SelectedMedia
    let schema: JSONSchema
}

/// Only bodies that lowering can use contribute inline types to the inventory.
func jsonRequestBody(_ body: Located<OpenAPI.Request>, lookup: ComponentLookup) throws
    -> JSONRequestBody
{
    guard body.value.required else {
        throw Unsupported(message: "optional request body", pointer: body.pointer)
    }
    guard
        let media = try selectedMedia(
            body.value.content, pointer: body.pointer + "/content", lookup: lookup),
        isJSON(media.name), let schema = media.value.schema
    else {
        throw Unsupported(
            message: "only JSON request bodies are supported", pointer: body.pointer + "/content")
    }
    return JSONRequestBody(media: media, schema: schema)
}

struct ResponseInput {
    let status: String
    let response: Either<OpenAPI.Reference<OpenAPI.Response>, OpenAPI.Response>
    let typeID: TypeID
    let suggestedName: String

    func hasBody(method: HTTPMethod) -> Bool { status != "204" && method != .head }
}

struct ResponseGroups {
    let successes: [ResponseInput]
    let errors: [ResponseInput]
    let ignored: [String]
}

/// Keeps partitioning, status identity and inline Option numbering identical in both walks.
func groupedResponses(_ operation: OpenAPI.Operation, id: OperationID) -> ResponseGroups {
    let all = Array(operation.responses)
    let successes = all.filter { $0.key.isSuccess }
    let hasSuccess = !successes.isEmpty
    let selected = hasSuccess ? successes : all.filter { $0.key.rawValue == "default" }
    let errors = all.filter {
        $0.key.rawValue.hasPrefix("4") || $0.key.rawValue.hasPrefix("5")
            || (hasSuccess && $0.key.rawValue == "default")
    }
    func inputs(
        _ items: [(
            key: OpenAPI.Response.StatusCode,
            value: Either<OpenAPI.Reference<OpenAPI.Response>, OpenAPI.Response>
        )], isError: Bool
    ) -> [ResponseInput] {
        items.enumerated().map { index, item in
            ResponseInput(
                status: item.key.rawValue, response: item.value,
                typeID: .inline(
                    isError
                        ? .errorResponse(id, status: item.key.rawValue)
                        : .response(id, status: item.key.rawValue)),
                suggestedName: items.count == 1
                    ? (isError ? "ErrorResponse" : "Response") : "Option\(index + 1)")
        }
    }
    return ResponseGroups(
        successes: inputs(selected, isError: false), errors: inputs(errors, isError: true),
        ignored: all.filter { $0.key.rawValue.hasPrefix("3") || $0.key.rawValue == "1XX" }.map {
            $0.key.rawValue
        })
}
#endif
