#if OpenAPIGenerator
import Foundation
import OpenAPIKit
import EndpointsGeneratorConfig

struct NameRequest {
    let target: NameTarget
    let wireName: String
    let specName: String?
    let pointer: String
    var aliases: [NameTarget] = []
    var integerName: String? = nil
}

extension NameRequest {
    fileprivate var diagnosticIdentity: String {
        if case .operation(.route(let method, let path)) = target {
            return operationIdentity(method: method, path: path)
        }
        return wireName
    }
}

struct NameResolutionFailure: Error {
    let message: String
    let pointer: String
}

enum Resolution: Equatable {
    case name(String)
    case unresolved(String)
}

protocol NameResolver {
    func resolve(_ requests: [NameRequest], config: Configuration, source: Source)
        -> NameResolutions
}
struct NameResolutions {
    var values: [NameTarget: Resolution] = [:]
    var pointers: [NameTarget: String] = [:]
    var diagnostics: [Diagnostic] = []
    var allocationsByScope: [AllocationScope: [NameAllocation]] = [:]
    func name(_ target: NameTarget) throws -> String {
        switch values[target] {
        case .name(let value): return value
        case .unresolved(let reason):
            throw NameResolutionFailure(
                message: reason, pointer: pointers[target] ?? "")
        case nil: throw NameError("Missing name inventory entry for " + targetSwift(target))
        }
    }
}
struct DeclarativeNameResolver: NameResolver {
    func resolve(_ requests: [NameRequest], config: Configuration, source: Source)
        -> NameResolutions
    {
        var result = NameResolutions()
        var operationAliases: [OperationID: OperationID] = [:]
        for request in requests {
            if case .operation(let canonical) = request.target {
                for alias in request.aliases {
                    if case .operation(let operation) = alias {
                        operationAliases[operation] = canonical
                    }
                }
            }
        }
        var renames: [NameTarget: [Rename]] = [:]
        for rename in config.renames {
            renames[canonicalTarget(rename.target, operations: operationAliases), default: []]
                .append(rename)
        }
        var used: Set<NameTarget> = []
        for request in requests {
            result.pointers[request.target] = request.pointer
            let matches = renames[request.target] ?? []
            for match in matches { used.insert(match.target) }
            if matches.count > 1 {
                let identities = matches.map { targetSwift($0.target) }.sorted(by: utf8Less)
                    .joined(separator: " and ")
                result.diagnostics.append(
                    source.diagnostic("Ambiguous rename: " + identities, matches.last!.pointer))
            }
            var context = NameContext(
                target: request.target, wireName: request.wireName,
                specName: request.specName, acronyms: config.settings.acronyms)
            if request.specName == nil, let integerName = request.integerName {
                context = NameContext(
                    target: request.target, wireName: request.wireName, specName: nil,
                    acronyms: config.settings.acronyms, camelCased: integerName,
                    upperCamelCased: integerName, verbatim: integerName)
            }
            if let candidate = matches.first?.replacement
                ?? config.settings.strategy(for: request.target).name(for: context)
            {
                do {
                    result.values[request.target] = .name(
                        try Naming.validated(candidate, isType: request.target.isType))
                } catch let failure as NameError {
                    result.values[request.target] = .unresolved(
                        failure.description
                            + (matches.isEmpty ? "; use " + renameHint(request.target) : ""))
                } catch { result.values[request.target] = .unresolved("Invalid name") }
            } else {
                let reason =
                    Naming.tokens(context.specName ?? context.wireName).isEmpty
                    ? "Name '\(request.wireName)' has no ASCII identifier"
                    : "The naming strategy returned no name for '\(request.wireName)'"
                result.values[request.target] = .unresolved(
                    reason + "; use " + renameHint(request.target))
            }
        }
        for request in requests {
            if case .name(let name) = result.values[request.target] {
                result.allocationsByScope[allocationScope(request.target), default: []].append(
                    NameAllocation(
                        name: name + (request.target.isOperation ? "Endpoint" : ""),
                        original: request.diagnosticIdentity, hint: renameHint(request.target),
                        target: request.target,
                        pointer: request.pointer))
            }
        }
        for rename in config.renames where !used.contains(rename.target) {
            result.diagnostics.append(
                source.diagnostic(
                    "Unused rename target " + targetSwift(rename.target), rename.pointer,
                    .warning))
        }
        return result
    }
}

/// Collects names without running strategies, allocating names, or constructing generated types.
struct NameInventory {
    let document: OpenAPI.Document
    let source: Source
    let config: Configuration
    var requests: [NameRequest] = []
    private var targets: Set<NameTarget> = []
    private var invalidSpecNames: Set<[UInt8]> = []
    var diagnostics: [Diagnostic] = []
    init(document: OpenAPI.Document, source: Source, config: Configuration) {
        self.document = document
        self.source = source
        self.config = config
    }
    var lookup: ComponentLookup { ComponentLookup(components: document.components) }

    mutating func specName(at pointer: String) -> String? {
        guard let node = source.node(at: pointer + "/x-swift-name") else { return nil }
        guard node.tag.rawValue == "tag:yaml.org,2002:str", let value = node.string,
            Naming.isIdentifier(value)
        else {
            if invalidSpecNames.insert(Array(pointer.utf8)).inserted {
                diagnostics.append(
                    source.diagnostic(
                        "x-swift-name must be an ASCII identifier", pointer + "/x-swift-name"))
            }
            return nil
        }
        return value
    }
    mutating func add(
        _ target: NameTarget, _ wire: String, _ pointer: String, spec: String? = nil,
        aliases: [NameTarget] = []
    ) {
        guard targets.insert(target).inserted else { return }
        requests.append(
            NameRequest(
                target: target, wireName: wire, specName: spec, pointer: pointer,
                aliases: aliases))
    }
    mutating func collect() {
        if config.serverType == nil && !config.hasEnvironments {
            for (i, server) in document.servers.enumerated() {
                let pointer = "/servers/\(i)"
                let name = server.description ?? "server\(i + 1)"
                add(.environment(name), name, pointer, spec: specName(at: pointer))
            }
        }
        for (key, schema) in document.components.schemas {
            let pointer = "/components/schemas/" + pointerPart(key.rawValue)
            schemaNames(
                schema, id: .component(key.rawValue), suggested: key.rawValue, pointer: pointer,
                declared: true)
        }
        for (path, itemRef) in document.paths {
            guard
                let item = try? lookup.resolve(
                    itemRef, at: "/paths/" + pointerPart(path.rawValue))
            else { continue }
            for endpoint in item.value.endpoints {
                guard
                    let method = HTTPMethod(
                        rawValue: Naming.asciiLower(endpoint.method.rawValue))
                else { continue }
                let route = operationIdentity(method: method, path: path.rawValue)
                let operation = endpoint.operation
                let matches: (String) -> Bool = {
                    matchesGlob($0, operation.operationId ?? "") || matchesGlob($0, route)
                }
                guard config.include.contains(where: matches),
                    !config.exclude.contains(where: matches)
                else { continue }
                let id =
                    operation.operationId.map(OperationID.id)
                    ?? .route(method: method, path: path.rawValue)
                let pointer = item.pointer + "/" + method.rawValue
                let aliases: [NameTarget] =
                    operation.operationId == nil
                    ? [] : [.operation(.route(method: method, path: path.rawValue))]
                add(
                    .operation(id),
                    operation.operationId
                        ?? Naming.fallbackOperationName(method: method, path: path.rawValue),
                    pointer,
                    spec: specName(at: pointer), aliases: aliases)
                let parameters = locatedParameters(
                    item: item.value, operation: operation, itemPointer: item.pointer,
                    pointer: pointer, lookup: lookup)
                for parameter in parameters {
                    guard
                        let place = supportedParameterLocation(parameter.value.location)
                    else { continue }
                    let target = NameTarget.parameter(parameter.value.name, in: place, of: id)
                    let routeAlias: [NameTarget] =
                        operation.operationId == nil
                        ? []
                        : [
                            .parameter(
                                parameter.value.name, in: place,
                                of: .route(method: method, path: path.rawValue))
                        ]
                    add(
                        target, parameter.value.name, parameter.pointer,
                        spec: specName(at: parameter.pointer), aliases: routeAlias)
                    if case .a(let context) = parameter.value.schemaOrContent {
                        switch context.schema {
                        case .a: break  // References retain the component's identity.
                        case .b(let schema):
                            schemaNames(
                                schema,
                                id: .inline(
                                    .parameter(parameter.value.name, in: place, of: id)),
                                suggested: parameter.value.name,
                                pointer: parameter.pointer + "/schema")
                        }
                    }
                }
                if let request = operation.requestBody,
                    let body = try? lookup.resolve(request, at: pointer + "/requestBody"),
                    let input = try? jsonRequestBody(body, lookup: lookup)
                {
                    schemaNames(
                        input.schema, id: .inline(.body(id)), suggested: "Body",
                        pointer: input.media.pointer + "/schema")
                }
                let groups = groupedResponses(operation, id: id)
                for group in [groups.successes, groups.errors] {
                    for input in group where input.hasBody(method: method) {
                        guard
                            let located = try? lookup.resolve(
                                input.response, at: pointer + "/responses/" + input.status),
                            let media = try? selectedMedia(
                                located.value.content, pointer: located.pointer + "/content",
                                lookup: lookup),
                            isJSON(media.name), let schema = media.value.schema
                        else { continue }
                        schemaNames(
                            schema, id: input.typeID, suggested: input.suggestedName,
                            pointer: media.pointer + "/schema")
                    }
                }
            }
        }
    }
    mutating func schemaNames(
        _ schema: JSONSchema, id: TypeID, suggested: String, pointer: String,
        declared: Bool = false
    ) {
        let isEnum = schema.allowedValues?.isEmpty == false
        let isObject: Bool
        if case .object = schema.value { isObject = true } else { isObject = false }
        let extensionName = specName(at: pointer)
        if declared || isEnum || isObject {
            add(.type(id), suggested, pointer, spec: extensionName)
        }
        if let values = schema.allowedValues, !values.isEmpty {
            var names: [String]? = nil
            if let node = source.node(at: pointer + "/x-enum-varnames") {
                if let array = node.sequence, array.count == values.count {
                    var parsed: [String] = []
                    for (i, value) in array.enumerated() {
                        if value.tag.rawValue == "tag:yaml.org,2002:str",
                            let name = value.string, Naming.isIdentifier(name)
                        {
                            parsed.append(name)
                        } else {
                            diagnostics.append(
                                source.diagnostic(
                                    "x-enum-varnames values must be ASCII identifiers",
                                    pointer + "/x-enum-varnames/\(i)"))
                        }
                    }
                    if parsed.count == values.count { names = parsed }
                } else {
                    diagnostics.append(
                        source.diagnostic(
                            "x-enum-varnames must be an array parallel to enum with the same length",
                            pointer + "/x-enum-varnames"))
                }
            }
            for (i, value) in values.enumerated() {
                if value.value is NSNull || value.value is Void { continue }
                let wire: String
                if let string = value.value as? String {
                    wire = string
                } else if let int = value.value as? Int {
                    wire = String(int)
                } else {
                    continue
                }
                add(.enumCase(wire, in: id), wire, pointer + "/enum/\(i)", spec: names?[i])
                if case .integer = schema.value, let integer = value.value as? Int {
                    if let index = requests.firstIndex(where: {
                        $0.target == .enumCase(wire, in: id)
                    }) {
                        requests[index].integerName =
                            integer < 0 ? "valueMinus" + wire.dropFirst() : "value" + wire
                    }
                }
            }
            return
        }
        switch schema.value {
        case .object(_, let object):
            for (wire, property) in object.properties {
                let p = pointer + "/properties/" + pointerPart(wire)
                add(.property(wire, in: id), wire, p, spec: specName(at: p))
                schemaNames(
                    property, id: .inline(.property(wire, in: id)), suggested: wire, pointer: p)
            }
        case .array(_, let array):
            if let items = array.items {
                schemaNames(
                    items, id: .inline(.items(of: id)), suggested: suggested + "Item",
                    pointer: pointer + "/items")
            }
        case .one(let members, _), .any(let members, _):
            let nonNull = members.filter {
                if case .null = $0.value { return false }
                return true
            }
            if members.count == 2, nonNull.count == 1 {
                schemaNames(nonNull[0], id: id, suggested: suggested, pointer: pointer)
            }
        default: break
        }
    }
}

func locatedParameters(
    item: OpenAPI.PathItem, operation: OpenAPI.Operation, itemPointer: String,
    pointer: String, lookup: ComponentLookup
) -> [Located<OpenAPI.Parameter>] {
    var parameters = item.parameters.enumerated().compactMap {
        try? lookup.resolve($0.element, at: itemPointer + "/parameters/\($0.offset)")
    }
    for (i, reference) in operation.parameters.enumerated() {
        guard let parameter = try? lookup.resolve(reference, at: pointer + "/parameters/\(i)")
        else { continue }
        parameters.removeAll {
            let lhs =
                parameter.value.location == .header
                ? Naming.asciiLower($0.value.name) : $0.value.name
            let rhs =
                parameter.value.location == .header
                ? Naming.asciiLower(parameter.value.name) : parameter.value.name
            return wireEqual(lhs, rhs) && $0.value.location == parameter.value.location
        }
        parameters.append(parameter)
    }
    return parameters
}

private func canonicalType(_ type: TypeID, operations: [OperationID: OperationID]) -> TypeID {
    switch type {
    case .component: return type
    case .inline(let origin):
        switch origin {
        case .property(let name, let owner):
            return .inline(.property(name, in: canonicalType(owner, operations: operations)))
        case .items(let owner):
            return .inline(.items(of: canonicalType(owner, operations: operations)))
        case .parameter(let name, let location, let op):
            return .inline(.parameter(name, in: location, of: operations[op] ?? op))
        case .body(let op): return .inline(.body(operations[op] ?? op))
        case .response(let op, let status):
            return .inline(.response(operations[op] ?? op, status: status))
        case .errorResponse(let op, let status):
            return .inline(.errorResponse(operations[op] ?? op, status: status))
        }
    }
}
private func canonicalTarget(_ target: NameTarget, operations: [OperationID: OperationID])
    -> NameTarget
{
    switch target {
    case .type(let type): return .type(canonicalType(type, operations: operations))
    case .property(let wire, let owner):
        return .property(wire, in: canonicalType(owner, operations: operations))
    case .enumCase(let wire, let owner):
        return .enumCase(wire, in: canonicalType(owner, operations: operations))
    case .parameter(let wire, let location, let op):
        return .parameter(wire, in: location, of: operations[op] ?? op)
    case .operation(let op): return .operation(operations[op] ?? op)
    case .environment: return target
    }
}

extension NameResolutions {
    func allocations(in scope: AllocationScope) -> [NameAllocation] {
        allocationsByScope[scope] ?? []
    }
}
extension NameTarget {
    fileprivate var isOperation: Bool {
        if case .operation = self { return true }
        return false
    }
}
enum AllocationScope: Hashable {
    case namespace, environments
    case properties(TypeID)
    case enumCases(TypeID)
    case parameters(ParameterLocation, OperationID)
    case inline(TypeID)
}
func allocationScope(_ target: NameTarget) -> AllocationScope {
    switch target {
    case .type(.component), .operation: return .namespace
    case .property(_, let owner): return .properties(owner)
    case .enumCase(_, let owner): return .enumCases(owner)
    case .parameter(_, let location, let operation): return .parameters(location, operation)
    case .environment: return .environments
    case .type(let type): return .inline(type)
    }
}
#endif
