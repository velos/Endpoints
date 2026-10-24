#if OpenAPIGenerator
import Foundation
import OpenAPIKit

private struct Unsupported: Error {
    let message: String
    let pointer: String
}

struct Lowering {
    let document: OpenAPI.Document
    let source: Source
    let configSource: Source
    let config: Configuration
    let namespace: String
    var diagnostics: [Diagnostic] = []
    struct ComponentName {
        let original: String
        let swift: String
    }
    var componentNames: [ComponentName] = []
    var componentGraph: ComponentGraph?
    var lookup: ComponentLookup { ComponentLookup(components: document.components) }

    mutating func report(_ error: Error, at pointer: String) {
        if let error = error as? Unsupported {
            diagnostics.append(
                source.diagnostic(
                    "Unsupported: " + error.message, error.pointer,
                    config.strict ? .error : .warning))
        } else if let error = error as? NameError {
            diagnostics.append(source.diagnostic(error.description, pointer))
        } else {
            diagnostics.append(source.diagnostic("Cannot resolve local reference", pointer))
        }
    }
    private func unsupported(_ message: String, _ pointer: String) -> Unsupported {
        Unsupported(message: message, pointer: pointer)
    }
    func rename(_ original: String, in renames: [Rename]) -> String? {
        renames.first { wireEqual($0.original, original) }?.replacement
    }
    func docs(_ schema: JSONSchema) -> [String] {
        [schema.title, schema.description].compactMap { $0 }.filter { !$0.isEmpty }
    }

    private func claimDeprecatedBackingStorage(
        for property: Property, using allocator: inout NameAllocator, hint: String
    ) throws {
        guard property.deprecated else { return }
        try allocator.claim(
            property.storageName, original: property.wire + " backing storage", hint: hint)
    }

    mutating func lower() -> Module {
        componentGraph = ComponentGraph(schemas: document.components.schemas)
        let customServerRoot = config.serverType?.split(separator: ".").first.map(String.init)
        let reservedNames = Naming.namespaceReserved.union([namespace])
            .union(customServerRoot.map { [$0] } ?? [])
        var names = NameAllocator(reserved: reservedNames)
        var server = ServerDecl()
        do { server = try lowerServer() } catch { report(error, at: "/servers") }
        var module = Module(
            namespace: namespace, access: config.accessLevel,
            title: "\(document.info.title) (\(document.info.version))", server: server)
        for (key, _) in document.components.schemas {
            let original = key.rawValue
            let sourcePointer = "/components/schemas/" + pointerPart(original)
            do {
                let name = try Naming.name(
                    original, style: .type, rename: rename(original, in: config.schemaRenames))
                try names.claim(name, original: original, hint: renameHint(.schemas, original))
                componentNames.append(ComponentName(original: original, swift: name))
            } catch { report(error, at: sourcePointer) }
        }
        for (key, schema) in document.components.schemas {
            let original = key.rawValue
            let sourcePointer = "/components/schemas/" + pointerPart(key.rawValue)
            guard
                let name = componentNames.first(where: { wireEqual($0.original, original) })?
                    .swift
            else { continue }
            do {
                var declaration = try declaration(
                    schema, name: name, path: namespace + "." + name, owner: original,
                    pointer: sourcePointer)
                if case .alias = declaration.kind {
                    for child in declaration.nested {
                        try names.claim(
                            child.name, original: original + " inline item",
                            hint: renameHint(.schemas, original))
                        module.schemas.append(child)
                    }
                    declaration.nested = []
                }
                module.schemas.append(declaration)
            } catch { report(error, at: sourcePointer) }
        }
        for (path, itemReference) in document.paths {
            let sourcePointer = "/paths/" + pointerPart(path.rawValue)
            do {
                let locatedItem = try lookup.resolve(itemReference, at: sourcePointer)
                let item = locatedItem.value
                for endpoint in item.endpoints {
                    let rawMethod = Naming.asciiLower(endpoint.method.rawValue)
                    guard let method = HTTPMethod(rawValue: rawMethod) else {
                        throw unsupported(
                            "HTTP method '\(rawMethod)'", sourcePointer + "/" + rawMethod)
                    }
                    let operationValue = endpoint.operation
                    let operationPointer = locatedItem.pointer + "/" + method.rawValue
                    let identity = operationIdentity(method: method, path: path.rawValue)
                    let matches = { (pattern: String) in
                        matchesGlob(pattern, operationValue.operationId ?? "")
                            || matchesGlob(pattern, identity)
                    }
                    guard config.include.contains(where: matches),
                        !config.exclude.contains(where: matches)
                    else { continue }
                    do {
                        module.endpoints.append(
                            try operation(
                                operationValue, item: item, method: method, path: path.rawValue,
                                pointer: operationPointer, itemPointer: locatedItem.pointer,
                                identity: identity, names: &names))
                    } catch { report(error, at: operationPointer) }
                }
            } catch { report(error, at: sourcePointer) }
        }
        // Lenient skipping must never leave references to declarations that were skipped.
        // Remove dependents to a fixed point; required wire fields are never silently
        // substituted with a different type.
        var removed = true
        while removed {
            removed = false
            let available = module.schemas.map { namespace + "." + $0.name }
            let endpointNames = module.endpoints.map { namespace + "." + $0.name }
            func missing(_ type: TypeRef) -> Bool {
                switch type {
                case .array(let propertyType), .optional(let propertyType):
                    return missing(propertyType)
                case .named(let typeName):
                    guard typeName.hasPrefix(namespace + ".") else { return false }
                    let component = typeName.split(separator: ".").prefix(2).joined(
                        separator: ".")
                    return !available.contains(component) && !endpointNames.contains(component)
                default: return false
                }
            }
            func invalid(_ declaration: TypeDecl) -> Bool {
                if case .alias(let propertyType) = declaration.kind, missing(propertyType) {
                    return true
                }
                return declaration.properties.contains { missing($0.type) }
                    || declaration.nested.contains(where: invalid)
            }
            module.schemas.removeAll { declaration in
                if invalid(declaration) {
                    diagnostics.append(
                        source.diagnostic(
                            "Unsupported: schema '\(declaration.name)' depends on a skipped schema",
                            declaration.pointer, config.strict ? .error : .warning))
                    removed = true
                    return true
                }
                return false
            }
            module.endpoints.removeAll { operation in
                if missing(operation.response) || operation.errorResponse.map(missing) == true
                    || operation.body.map(missing) == true
                    || operation.nested.contains(where: invalid)
                {
                    diagnostics.append(
                        source.diagnostic(
                            "Unsupported: operation '\(operation.name)' depends on a skipped schema",
                            operation.pointer, config.strict ? .error : .warning))
                    return true
                }
                return false
            }
        }
        module.schemas.sort { utf8Less($0.name, $1.name) }
        module.endpoints.sort { utf8Less($0.name, $1.name) }
        module.resolveDateUsage()
        return module
    }

    mutating func lowerServer() throws -> ServerDecl {
        var server = ServerDecl(customType: config.serverType, typical: config.hasEnvironments)
        if config.serverType != nil { return server }
        if config.hasEnvironments {
            for environment in config.environments {
                let name = environment.name
                let url = environment.url
                do {
                    server.environments.append(
                        EnvironmentDecl(
                            name: name, url: try ServerURLs.normalize(url), docs: [url]))
                } catch let error as NameError {
                    diagnostics.append(
                        configSource.diagnostic(
                            error.description, "/server/environments/" + name))
                }
            }
            server.defaultEnvironment = config.defaultEnvironment ?? "production"
        } else {
            var allocator = NameAllocator(reserved: ["rawValue", "allCases", "hashValue"])
            for (index, specServer) in document.servers.enumerated() {
                let sourcePointer = "/servers/\(index)"
                do {
                    let name = try Naming.name(
                        specServer.description ?? "server\(index + 1)", style: .member)
                    try allocator.claim(
                        name, original: specServer.description ?? "server\(index + 1)",
                        hint: "a unique servers[].description")
                    // OpenAPIKit's URLTemplate stores the unnormalised input string.
                    var url = specServer.urlTemplate.rawValue
                    for (key, variable) in specServer.variables {
                        url = url.replacingOccurrences(of: "{\(key)}", with: variable.default)
                        let choices =
                            variable.enum.map {
                                "; alternatives: " + $0.joined(separator: ", ")
                            } ?? ""
                        diagnostics.append(
                            source.diagnostic(
                                "Server variable '\(key)' uses default '\(variable.default)'\(choices)",
                                sourcePointer + "/variables/" + pointerPart(key), .note))
                    }
                    let normalized = try ServerURLs.normalize(url)
                    server.environments.append(
                        EnvironmentDecl(
                            name: name, url: normalized,
                            docs: [url, specServer.description].compactMap { $0 }))
                } catch { report(error, at: sourcePointer) }
            }
            server.defaultEnvironment =
                config.defaultEnvironment ?? server.environments.first?.name
                .replacingOccurrences(of: "`", with: "") ?? ""
        }
        if server.environments.isEmpty {
            diagnostics.append(
                source.diagnostic(
                    "At least one absolute server URL is required; configure server.type or server.environments",
                    "/servers"))
        } else if !server.environments.contains(where: {
            $0.name.replacingOccurrences(of: "`", with: "") == server.defaultEnvironment
        }) {
            diagnostics.append(
                configSource.diagnostic(
                    "defaultEnvironment has no URL", "/server/defaultEnvironment"))
        }
        server.securityDocs = try securityDocumentation()
        return server
    }

    func nullable(_ schema: JSONSchema, visited: [String] = []) -> Bool {
        if schema.nullable { return true }
        switch schema.value {
        case .reference(let reference, _):
            guard let name = reference.name, !visited.contains(where: { wireEqual($0, name) }),
                let target = try? lookup.schema(named: name)
            else { return false }
            return nullable(target, visited: visited + [name])
        case .one(let members, _), .any(let members, _):
            return members.contains {
                if case .null = $0.value { return true }
                return false
            }
        default: return false
        }
    }

    func directional(_ schema: JSONSchema, visited: [String] = []) -> Bool {
        if schema.readOnly || schema.writeOnly { return true }
        if case .reference(let reference, _) = schema.value,
            let name = reference.name, !visited.contains(where: { wireEqual($0, name) }),
            let target = try? lookup.schema(named: name)
        {
            return directional(target, visited: visited + [name])
        }
        return false
    }

    mutating func type(
        _ schema: JSONSchema, suggested: String, path: String, owner: String, pointer: String,
        nested: inout [TypeDecl]
    ) throws -> TypeRef {
        if let values = schema.allowedValues, !values.isEmpty {
            guard case .string = schema.value else {
                throw unsupported("only string enums are supported in this slice", pointer)
            }
            let name = try Naming.name(suggested, style: .type)
            nested.append(
                try declaration(
                    schema, name: name, path: path + "." + name, owner: owner, pointer: pointer)
            )
            return .named(path + "." + name)
        }
        switch schema.value {
        case .string:
            switch schema.formatString {
            case "date-time": return .date
            case "uuid": return .uuid
            case "uri": return .url
            case "byte", "binary": return .data
            default: return .string
            }
        case .integer:
            switch schema.formatString {
            case "int32": return .int32
            case "int64": return .int64
            default: return .int
            }
        case .number: return .double
        case .boolean: return .bool
        case .array(_, let array):
            guard let items = array.items, array.prefixItems == nil else {
                throw unsupported("arrays require one items schema", pointer)
            }
            let item = try type(
                items, suggested: suggested + "Item", path: path, owner: owner,
                pointer: pointer + "/items", nested: &nested)
            return .array(nullable(items) ? .optional(item) : item)
        case .object:
            let name = try Naming.name(suggested, style: .type)
            nested.append(
                try declaration(
                    schema, name: name, path: path + "." + name, owner: owner, pointer: pointer)
            )
            return .named(path + "." + name)
        case .reference(let reference, _):
            guard let original = reference.name,
                let name = componentNames.first(where: { wireEqual($0.original, original) })?
                    .swift
            else {
                throw NameError(
                    "Unknown or invalid component reference; use a named schema in components.schemas"
                )
            }
            if componentGraph?.isRecursive(original) == true {
                throw unsupported("recursive schema '\(original)'", pointer)
            }
            return .named(namespace + "." + name)
        case .one(let members, _), .any(let members, _):
            let nonNull = members.filter {
                if case .null = $0.value { return false }
                return true
            }
            if members.count == 2, nonNull.count == 1 {
                return try type(
                    nonNull[0], suggested: suggested, path: path, owner: owner,
                    pointer: pointer, nested: &nested)
            }
            throw unsupported("oneOf/anyOf schemas", pointer)
        case .all: throw unsupported("allOf schemas", pointer)
        default: throw unsupported("schema kind requires a later generator phase", pointer)
        }
    }

    mutating func declaration(
        _ schema: JSONSchema, name: String, path: String, owner: String, pointer: String
    ) throws -> TypeDecl {
        var declaration = TypeDecl(
            name: name, kind: .structure, pointer: pointer, renameKey: owner, docs: docs(schema),
            deprecated: schema.deprecated)
        if let allowed = schema.allowedValues, !allowed.isEmpty {
            guard case .string = schema.value else {
                throw unsupported("only string enums are supported in this slice", pointer)
            }
            var allocator = NameAllocator(reserved: Naming.structReserved)
            declaration.kind = config.closedEnums ? .closedEnum : .openEnum
            for raw in allowed {
                // Null is represented by the property's presence, never an enum case.
                if raw.value is NSNull || raw.value is Void { continue }
                guard let value = raw.value as? String else {
                    throw unsupported("non-string enum value", pointer + "/enum")
                }
                let member = value.isEmpty ? "empty" : try Naming.name(value, style: .member)
                try allocator.claim(member, original: value, hint: "distinct enum wire values")
                declaration.values.append(EnumValue(name: member, raw: value))
            }
            guard !declaration.values.isEmpty else {
                throw unsupported("enum with no non-null values", pointer)
            }
            return declaration
        }
        if case .object(_, let object) = schema.value {
            if object.additionalProperties != nil {
                throw unsupported("additionalProperties", pointer + "/additionalProperties")
            }
            if object.properties.isEmpty && source.node(at: pointer + "/properties") == nil {
                throw unsupported("free-form object schemas", pointer)
            }
            var allocator = NameAllocator(reserved: Naming.structReserved)
            for (wire, property) in object.properties {
                let sourcePointer = pointer + "/properties/" + pointerPart(wire)
                do {
                    let member = try Naming.name(
                        wire, style: .member,
                        rename: rename(owner + "." + wire, in: config.propertyRenames))
                    try allocator.claim(
                        member, original: wire, hint: renameHint(.properties, owner + "." + wire))
                    var nested: [TypeDecl] = []
                    let propertyType = try type(
                        property, suggested: member.replacingOccurrences(of: "`", with: ""),
                        path: path, owner: owner + "." + wire, pointer: sourcePointer,
                        nested: &nested)
                    let presence: Presence =
                        !property.required || directional(property)
                        ? .optional : nullable(property) ? .requiredNullable : .required
                    let loweredProperty = Property(
                        name: member, wire: wire,
                        type: presence == .required ? propertyType : .optional(propertyType),
                        presence: presence, docs: docs(property), deprecated: property.deprecated)
                    try claimDeprecatedBackingStorage(
                        for: loweredProperty, using: &allocator,
                        hint: renameHint(.properties, owner + "." + wire))
                    declaration.properties.append(loweredProperty)
                    declaration.nested += nested
                } catch { report(error, at: sourcePointer) }
            }
            var nestedNames = NameAllocator(
                reserved: Naming.namespaceReserved.union(Naming.structReserved).union([
                    namespace
                ]))
            for nested in declaration.nested {
                try nestedNames.claim(
                    nested.name, original: nested.name,
                    hint: renameHint(.properties, nested.renameKey))
            }
            declaration.nested.sort { utf8Less($0.name, $1.name) }
            return declaration
        }
        var nested: [TypeDecl] = []
        declaration.kind = .alias(
            try type(
                schema, suggested: name,
                path: path.split(separator: ".").dropLast().joined(separator: "."),
                owner: owner, pointer: pointer, nested: &nested))
        declaration.nested = nested
        return declaration
    }

    mutating func operation(
        _ operation: OpenAPI.Operation, item: OpenAPI.PathItem, method: HTTPMethod,
        path: String, pointer: String, itemPointer: String,
        identity: String, names: inout NameAllocator
    ) throws -> EndpointDecl {
        guard method.isSupported else {
            throw unsupported("HTTP method '\(method.rawValue)'", pointer)
        }
        guard operation.servers == nil && item.servers == nil else {
            throw unsupported("operation or path-level servers", pointer)
        }
        let original = operation.operationId ?? identity
        let derivedName =
            operation.operationId ?? fallbackOperationName(method: method, path: path)
        let renamed = rename(original, in: config.operationRenames)
        let name = try Naming.name(derivedName, style: .type, rename: renamed) + "Endpoint"
        try names.claim(name, original: original, hint: renameHint(.operations, original))
        let operationPath = namespace + "." + name
        var result = EndpointDecl(name: name, method: method, pointer: pointer)
        result.docs =
            [operation.summary, operation.description].compactMap { $0 } + [
                "`\(identity)`"
            ]
        if let tags = operation.tags, !tags.isEmpty {
            result.docs.append("Tags: " + tags.joined(separator: ", "))
        }
        result.deprecated = operation.deprecated
        result.noAuth = operation.security?.isEmpty == true
        if let security = operation.security, !security.isEmpty, security != document.security {
            diagnostics.append(
                source.diagnostic(
                    "Operation security differs from the document; the endpoint inherits server authentication",
                    pointer + "/security", .note))
        }
        struct LocatedParameter {
            let value: OpenAPI.Parameter
            let pointer: String
        }
        var parameters: [LocatedParameter] = []
        for (index, value) in item.parameters.enumerated() {
            let located = try lookup.resolve(value, at: itemPointer + "/parameters/\(index)")
            parameters.append(LocatedParameter(value: located.value, pointer: located.pointer))
        }
        for (index, value) in operation.parameters.enumerated() {
            let located = try lookup.resolve(value, at: pointer + "/parameters/\(index)")
            let parameter = located.value
            parameters.removeAll {
                wireEqual($0.value.name, parameter.name)
                    && $0.value.location == parameter.location
            }
            parameters.append(LocatedParameter(value: parameter, pointer: located.pointer))
        }
        var pathNames = NameAllocator(reserved: Naming.structReserved.union(["_endpointPath"]))
        var queryNames = NameAllocator(reserved: Naming.structReserved)
        var headerNames = NameAllocator(reserved: Naming.structReserved)
        for located in parameters {
            let parameter = located.value
            let sourcePointer = located.pointer
            do {
                guard case .a(let context) = parameter.schemaOrContent else {
                    throw unsupported("parameter content", sourcePointer)
                }
                let locatedSchema = try lookup.resolve(
                    context.schema, at: sourcePointer + "/schema")
                let schema = try lookup.schema(locatedSchema.value)
                // Format date/date-time/uri query values as strings. No date arithmetic
                // or enum/runtime conformances are needed at the request boundary.
                let propertyType: TypeRef
                if case .string = schema.value, schema.allowedValues == nil,
                    ["date", "date-time", "uri"].contains(schema.formatString ?? "")
                {
                    propertyType = .string
                } else {
                    var ignored: [TypeDecl] = []
                    propertyType = try type(
                        schema, suggested: parameter.name, path: operationPath, owner: original,
                        pointer: sourcePointer + "/schema", nested: &ignored)
                    if !ignored.isEmpty {
                        throw unsupported("enum or object parameter", sourcePointer)
                    }
                }
                let member = try Naming.name(parameter.name, style: .member)
                var property = Property(
                    name: member, wire: parameter.name, type: propertyType, presence: .required,
                    docs: parameter.description.map { [$0] } ?? [],
                    deprecated: parameter.deprecated)
                switch parameter.location {
                case .path:
                    guard propertyType == .string || propertyType == .int, !nullable(schema)
                    else {
                        throw unsupported(
                            "path parameters must be non-nullable String or Int", sourcePointer)
                    }
                    try pathNames.claim(
                        member, original: parameter.name, hint: "a distinct parameter name")
                    try claimDeprecatedBackingStorage(
                        for: property, using: &pathNames, hint: "a distinct parameter name")
                    result.pathParams.append(property)
                case .query:
                    guard [.string, .int, .double, .bool].contains(propertyType),
                        !nullable(schema)
                    else {
                        throw unsupported(
                            "query parameters must be non-nullable String, Int, Double, or Bool scalars",
                            sourcePointer)
                    }
                    guard context.style == .form, !context.allowReserved else {
                        throw unsupported(
                            "non-default scalar query serialization", sourcePointer)
                    }
                    try queryNames.claim(
                        member, original: parameter.name, hint: "a distinct parameter name")
                    try claimDeprecatedBackingStorage(
                        for: property, using: &queryNames, hint: "a distinct parameter name")
                    if !parameter.required {
                        property.type = .optional(propertyType)
                        property.presence = .optional
                    }
                    result.queryParams.append(property)
                case .header:
                    guard propertyType == .string, parameter.required, !nullable(schema) else {
                        throw unsupported(
                            "headers must be required String parameters", sourcePointer)
                    }
                    try headerNames.claim(
                        member, original: parameter.name, hint: "a distinct parameter name")
                    try claimDeprecatedBackingStorage(
                        for: property, using: &headerNames, hint: "a distinct parameter name")
                    result.headerParams.append(property)
                default: throw unsupported("cookie or querystring parameters", sourcePointer)
                }
            } catch let error as Unsupported {
                // A missing path value makes the entire operation unusable.
                if parameter.location == .path { throw error }
                report(error, at: sourcePointer)
            }
        }
        result.path = try pathSegments(path, properties: result.pathParams)
        if let request = operation.requestBody {
            let locatedBody = try lookup.resolve(request, at: pointer + "/requestBody")
            let body = locatedBody.value
            guard body.required else {
                throw unsupported("optional request body", locatedBody.pointer)
            }
            guard
                let media = try selectedMedia(
                    body.content, pointer: locatedBody.pointer + "/content"),
                isJSON(media.name), let schema = media.value.schema
            else {
                throw unsupported(
                    "only JSON request bodies are supported", locatedBody.pointer + "/content")
            }
            let sourcePointer = media.pointer + "/schema"
            result.body = try payload(
                schema, name: "Body", path: operationPath, owner: original,
                pointer: sourcePointer, nested: &result.nested)
            if media.name != "application/json" {
                if result.headerParams.contains(where: {
                    Naming.asciiLower($0.wire) == "content-type"
                }) {
                    throw NameError(
                        "Content-Type header collides with the selected request media type; remove the header parameter"
                    )
                }
                result.fixedHeaders.append(FixedHeader(name: "Content-Type", value: media.name))
            }
        }
        let outcomes = Array(operation.responses)
        var success = outcomes.filter { $0.key.isSuccess }
        let defaults = outcomes.filter { $0.key.rawValue == "default" }
        if success.isEmpty { success = defaults }
        let errors =
            outcomes.filter { $0.key.rawValue.hasPrefix("4") || $0.key.rawValue.hasPrefix("5") }
            + (outcomes.contains { $0.key.isSuccess } ? defaults : [])
        guard success.count == 1 else {
            throw unsupported(
                "exactly one success outcome is required; status-tagged unions need runtime support",
                pointer + "/responses")
        }
        guard errors.count <= 1 else {
            throw unsupported(
                "multiple error outcomes require status-tagged unions", pointer + "/responses")
        }
        func responsePointer(_ code: String) -> String { pointer + "/responses/" + code }
        let locatedSuccess = try lookup.resolve(
            success[0].value, at: responsePointer(success[0].key.rawValue))
        let successBody = locatedSuccess.value
        if success[0].key.rawValue == "204" || successBody.content.isEmpty {
            result.response = .void
        } else if let media = try selectedMedia(
            successBody.content, pointer: locatedSuccess.pointer + "/content")
        {
            if isJSON(media.name) {
                guard let schema = media.value.schema else {
                    throw unsupported("JSON success responses require a schema", media.pointer)
                }
                result.response = try payload(
                    schema, name: "Response", path: operationPath, owner: original,
                    pointer: media.pointer + "/schema", nested: &result.nested)
            } else {
                result.response = .data
            }
        }
        if let error = errors.first {
            let locatedError = try lookup.resolve(
                error.value, at: responsePointer(error.key.rawValue))
            let body = locatedError.value
            if !body.content.isEmpty {
                guard
                    let media = try selectedMedia(
                        body.content, pointer: locatedError.pointer + "/content"),
                    isJSON(media.name), let schema = media.value.schema
                else {
                    throw unsupported(
                        "typed errors require a JSON schema", locatedError.pointer + "/content")
                }
                result.errorResponse = try payload(
                    schema, name: "ErrorResponse", path: operationPath, owner: original,
                    pointer: media.pointer + "/schema", nested: &result.nested)
            }
        }
        var nestedNames = NameAllocator(
            reserved: Naming.namespaceReserved.union(Naming.endpointReserved)
                .subtracting(["Body", "Response", "ErrorResponse"]).union([namespace]))
        for nested in result.nested {
            try nestedNames.claim(
                nested.name, original: nested.name, hint: renameHint(.operations, original))
        }
        result.nested.sort { utf8Less($0.name, $1.name) }
        return result
    }

    mutating func payload(
        _ schema: JSONSchema, name: String, path: String, owner: String, pointer: String,
        nested: inout [TypeDecl]
    ) throws -> TypeRef {
        if case .object = schema.value {
            nested.append(
                try declaration(
                    schema, name: name, path: path + "." + name, owner: owner, pointer: pointer)
            )
            return .named(path + "." + name)
        }
        return try type(
            schema, suggested: name, path: path, owner: owner, pointer: pointer, nested: &nested
        )
    }
}

func isJSON(_ media: String) -> Bool { media == "application/json" || media.hasSuffix("+json") }
extension Lowering {
    struct SelectedMedia {
        let name: String
        let value: OpenAPI.Content
        let pointer: String
    }

    func selectedMedia(_ content: OpenAPI.Content.Map, pointer: String) throws -> SelectedMedia? {
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
}

func operationIdentity(method: HTTPMethod, path: String) -> String {
    method.uppercase + " " + path
}

func fallbackOperationName(method: HTTPMethod, path: String) -> String {
    method.rawValue + " "
        + path.replacingOccurrences(of: "{", with: " By ").replacingOccurrences(
            of: "}", with: " ")
}
func pathSegments(_ path: String, properties: [Property]) throws -> EndpointPath {
    let text = String(path.drop(while: { $0 == "/" }))
    var result: [PathSegment] = []
    var literal = ""
    var parameter: String?
    for character in text {
        if character == "{" {
            guard parameter == nil else { throw NameError("Malformed path template") }
            if !literal.isEmpty {
                result.append(.literal(literal))
                literal = ""
            }
            parameter = ""
        } else if character == "}" {
            guard let wire = parameter,
                let property = properties.first(where: { wireEqual($0.wire, wire) })
            else { throw NameError("Path placeholder has no matching path parameter") }
            result.append(.parameter(property.storageName))
            parameter = nil
        } else if parameter != nil {
            parameter?.append(character)
        } else {
            literal.append(character)
        }
    }
    guard parameter == nil else { throw NameError("Malformed path template") }
    if !literal.isEmpty { result.append(.literal(literal)) }
    let embedded = result.indices.contains { index in
        guard case .parameter = result[index] else { return false }
        let startsSegment: Bool
        if index == 0 {
            startsSegment = true
        } else if case .literal(let prefix) = result[index - 1] {
            startsSegment = prefix.hasSuffix("/")
        } else {
            startsSegment = false
        }
        let endsSegment: Bool
        if index + 1 == result.count {
            endsSegment = true
        } else if case .literal(let suffix) = result[index + 1] {
            endsSegment = suffix.hasPrefix("/")
        } else {
            endsSegment = false
        }
        return !startsSegment || !endsSegment
    }
    return embedded ? .computed(result) : .template(result)
}
#endif
