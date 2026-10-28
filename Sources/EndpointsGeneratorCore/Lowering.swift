#if OpenAPIGenerator
import Foundation
import OpenAPIKit
import EndpointsGeneratorConfig

struct Unsupported: Error {
    let message: String
    let pointer: String
}

struct Lowering {
    let document: OpenAPI.Document
    let source: Source
    let configSource: Source
    let config: Configuration
    let namespace: String
    let resolutions: NameResolutions
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
        } else if let error = error as? NameResolutionFailure {
            diagnostics.append(source.diagnostic(error.message, error.pointer))
        } else if let error = error as? NameError {
            diagnostics.append(source.diagnostic(error.description, pointer))
        } else {
            diagnostics.append(source.diagnostic("Cannot resolve local reference", pointer))
        }
    }
    func unsupported(_ message: String, _ pointer: String) -> Unsupported {
        Unsupported(message: message, pointer: pointer)
    }
    func docs(_ schema: JSONSchema) -> [String] {
        [schema.title, schema.description].compactMap { $0 }.filter { !$0.isEmpty }
    }

    private func claimDeprecatedBackingStorage(
        for property: Property, using allocator: inout NameAllocator, hint: String,
        target: NameTarget
    ) throws {
        guard property.deprecated else { return }
        try allocator.claim(
            property.storageName, original: property.wire + " backing storage", hint: hint,
            target: target)
    }

    mutating func lower() -> Module {
        componentGraph = ComponentGraph(schemas: document.components.schemas)
        let customServerRoot = config.serverType?.split(separator: ".").first.map(String.init)
        let reservedNames = Naming.namespaceReserved.union([namespace])
            .union(customServerRoot.map { [$0] } ?? [])
        var names = NameAllocator(
            reserved: reservedNames, candidates: resolutions.allocations(in: .namespace))
        var server = ServerDecl()
        do { server = try lowerServer() } catch { report(error, at: "/servers") }
        var module = Module(
            namespace: namespace, access: config.accessLevel,
            title: "\(document.info.title) (\(document.info.version))", server: server)
        for (key, _) in document.components.schemas {
            let original = key.rawValue
            let sourcePointer = "/components/schemas/" + pointerPart(original)
            do {
                let name = try resolutions.name(.type(.component(original)))
                try names.claim(
                    name, original: original, hint: renameHint(.type(.component(original))),
                    target: .type(.component(original)))
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
                    schema, name: name, path: namespace + "." + name,
                    typeID: .component(original),
                    pointer: sourcePointer)
                if case .alias = declaration.kind {
                    for child in declaration.nested {
                        try names.claim(
                            child.name, original: original + " inline item",
                            hint: renameHint(child.namingTarget ?? .type(.component(original))),
                            target: child.namingTarget ?? .type(.component(original)))
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
                return declaration.outcomes.contains { $0.payload.map(missing) ?? false }
                    || declaration.properties.contains { missing($0.type) }
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
        var hadNamingFailure = false
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
            var allocator = NameAllocator(
                reserved: ["rawValue", "allCases", "hashValue"],
                candidates: resolutions.allocations(in: .environments))
            for (index, specServer) in document.servers.enumerated() {
                let sourcePointer = "/servers/\(index)"
                let target = NameTarget.environment(specServer.description ?? "server\(index + 1)")
                let name: String
                do {
                    name = try resolutions.name(target)
                    try allocator.claim(
                        name, original: specServer.description ?? "server\(index + 1)",
                        hint: renameHint(target), target: target)
                } catch {
                    hadNamingFailure = true
                    report(error, at: sourcePointer)
                    continue
                }
                do {
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
            if !hadNamingFailure {
                diagnostics.append(
                    source.diagnostic(
                        "At least one absolute server URL is required; configure server: .type(...) or .environments(...)",
                        "/servers"))
            }
        } else if !server.environments.contains(where: {
            $0.name.replacingOccurrences(of: "`", with: "") == server.defaultEnvironment
        }) {
            diagnostics.append(
                configSource.diagnostic(
                    "The default server environment has no URL; configure server: .environments(_:default:)",
                    "/server/defaultEnvironment"))
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
        _ schema: JSONSchema, path: String, typeID: TypeID,
        pointer: String,
        nested: inout [TypeDecl]
    ) throws -> TypeRef {
        if let values = schema.allowedValues, !values.isEmpty {
            switch schema.value {
            case .string, .integer: break
            default: throw unsupported("only string and integer enums are supported", pointer)
            }
            let name = try resolutions.name(.type(typeID))
            nested.append(
                try declaration(
                    schema, name: name, path: path + "." + name, typeID: typeID,
                    pointer: pointer)
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
                items, path: path,
                typeID: .inline(.items(of: typeID)),
                pointer: pointer + "/items", nested: &nested)
            return .array(nullable(items) ? .optional(item) : item)
        case .object:
            let name = try resolutions.name(.type(typeID))
            nested.append(
                try declaration(
                    schema, name: name, path: path + "." + name, typeID: typeID,
                    pointer: pointer)
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
                    nonNull[0], path: path, typeID: typeID,
                    pointer: pointer, nested: &nested)
            }
            throw unsupported("oneOf/anyOf schemas", pointer)
        case .all: throw unsupported("allOf schemas", pointer)
        default: throw unsupported("schema kind requires a later generator phase", pointer)
        }
    }

    mutating func declaration(
        _ schema: JSONSchema, name: String, path: String, typeID: TypeID,
        pointer: String
    ) throws -> TypeDecl {
        var declaration = TypeDecl(
            name: name, kind: .structure, pointer: pointer, namingTarget: .type(typeID),
            docs: docs(schema),
            deprecated: schema.deprecated)
        if let allowed = schema.allowedValues, !allowed.isEmpty {
            switch schema.value {
            case .string, .integer: break
            default: throw unsupported("only string and integer enums are supported", pointer)
            }
            var allocator = NameAllocator(
                reserved: Naming.structReserved,
                candidates: resolutions.allocations(
                    in: allocationScope(.enumCase("", in: typeID))))
            declaration.kind = config.closedEnums ? .closedEnum : .openEnum
            if case .integer = schema.value {
                switch schema.formatString {
                case "int32": declaration.enumRawType = .int32
                case "int64": declaration.enumRawType = .int64
                default: declaration.enumRawType = .int
                }
            }
            for raw in allowed {
                // Null is represented by the property's presence, never an enum case.
                if raw.value is NSNull || raw.value is Void { continue }
                let value: String
                let member: String
                if declaration.enumRawType == .string, let string = raw.value as? String {
                    value = string
                    member = try resolutions.name(.enumCase(string, in: typeID))
                } else if declaration.enumRawType != .string, let integer = raw.value as? Int {
                    if declaration.enumRawType == .int32, Int32(exactly: integer) == nil {
                        throw unsupported(
                            "enum value is outside the Int32 range", pointer + "/enum")
                    }
                    value = String(integer)
                    member = try resolutions.name(.enumCase(value, in: typeID))
                } else {
                    throw unsupported(
                        "enum value does not match its scalar type", pointer + "/enum")
                }
                try allocator.claim(
                    member, original: value, hint: renameHint(.enumCase(value, in: typeID)),
                    target: .enumCase(value, in: typeID))
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
            var allocator = NameAllocator(
                reserved: Naming.structReserved,
                candidates: resolutions.allocations(
                    in: allocationScope(.property("", in: typeID))))
            for (wire, property) in object.properties {
                let sourcePointer = pointer + "/properties/" + pointerPart(wire)
                do {
                    let member = try resolutions.name(.property(wire, in: typeID))
                    try allocator.claim(
                        member, original: wire, hint: renameHint(.property(wire, in: typeID)),
                        target: .property(wire, in: typeID))
                    var nested: [TypeDecl] = []
                    let propertyType = try type(
                        property,
                        path: path,
                        typeID: .inline(.property(wire, in: typeID)), pointer: sourcePointer,
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
                        hint: renameHint(.property(wire, in: typeID)),
                        target: .property(wire, in: typeID))
                    declaration.properties.append(loweredProperty)
                    declaration.nested += nested
                } catch { report(error, at: sourcePointer) }
            }
            var nestedNames = NameAllocator(
                reserved: Naming.namespaceReserved.union(Naming.structReserved).union([
                    namespace
                ]),
                candidates: declaration.nested.map {
                    NameAllocation(
                        name: $0.name, original: targetSwift($0.namingTarget ?? .type(typeID)),
                        hint: renameHint($0.namingTarget ?? .type(typeID)),
                        target: $0.namingTarget ?? .type(typeID), pointer: $0.pointer)
                })
            for nested in declaration.nested {
                try nestedNames.claim(
                    nested.name, original: nested.name,
                    hint: renameHint(nested.namingTarget ?? .type(typeID)),
                    target: nested.namingTarget ?? .type(typeID))
            }
            declaration.nested.sort { utf8Less($0.name, $1.name) }
            return declaration
        }
        var nested: [TypeDecl] = []
        declaration.kind = .alias(
            try type(
                schema,
                path: path.split(separator: ".").dropLast().joined(separator: "."),
                typeID: typeID, pointer: pointer, nested: &nested))
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
        let operationID =
            operation.operationId.map(OperationID.id) ?? .route(method: method, path: path)
        let name = try resolutions.name(.operation(operationID)) + "Endpoint"
        try names.claim(
            name, original: original, hint: renameHint(.operation(operationID)),
            target: .operation(operationID))
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
        let parameters = locatedParameters(
            item: item, operation: operation, itemPointer: itemPointer, pointer: pointer,
            lookup: lookup)
        var pathNames = NameAllocator(
            reserved: Naming.structReserved.union(["_endpointPath"]),
            candidates: resolutions.allocations(
                in: allocationScope(.parameter("", in: .path, of: operationID))))
        var queryNames = NameAllocator(
            reserved: Naming.structReserved,
            candidates: resolutions.allocations(
                in: allocationScope(.parameter("", in: .query, of: operationID))))
        var headerNames = NameAllocator(
            reserved: Naming.structReserved,
            candidates: resolutions.allocations(
                in: allocationScope(.parameter("", in: .header, of: operationID))))
        for located in parameters {
            let parameter = located.value
            let sourcePointer = located.pointer
            let nestedStart = result.nested.count
            do {
                guard let location = supportedParameterLocation(parameter.location) else {
                    throw unsupported("cookie or querystring parameters", sourcePointer)
                }
                guard case .a(let context) = parameter.schemaOrContent else {
                    throw unsupported("parameter content", sourcePointer)
                }
                let locatedSchema = try lookup.resolve(
                    context.schema, at: sourcePointer + "/schema")
                let schema = try lookup.schema(locatedSchema.value)
                let parameterSchema: JSONSchema
                switch context.schema {
                case .a(let reference): parameterSchema = .reference(reference.jsonReference)
                case .b(let schema): parameterSchema = schema
                }
                let propertyType = try parameterType(
                    parameterSchema, path: operationPath,

                    typeID: .inline(
                        .parameter(
                            parameter.name,
                            in: location, of: operationID)),
                    pointer: sourcePointer + "/schema", nested: &result.nested)
                let isEnum = schema.allowedValues?.isEmpty == false
                let scalarTypes: [TypeRef] = [
                    .string, .int, .int32, .int64, .double, .bool, .uuid,
                ]
                let isScalar = scalarTypes.contains(propertyType) || isEnum
                let parameterTarget = NameTarget.parameter(
                    parameter.name,
                    in: location,
                    of: operationID)
                let member = try resolutions.name(parameterTarget)
                var property = Property(
                    name: member, wire: parameter.name, type: propertyType, presence: .required,
                    docs: parameter.description.map { [$0] } ?? [],
                    deprecated: parameter.deprecated)
                switch location {
                case .path:
                    guard [.string, .int, .int32, .int64, .uuid].contains(propertyType) || isEnum,
                        !nullable(schema), context.style == .simple
                    else {
                        throw unsupported(
                            "path parameters require simple String, integer, UUID, or enum values",
                            sourcePointer)
                    }
                    try pathNames.claim(
                        member, original: parameter.name, hint: renameHint(parameterTarget),
                        target: parameterTarget)
                    try claimDeprecatedBackingStorage(
                        for: property, using: &pathNames, hint: renameHint(parameterTarget),
                        target: parameterTarget)
                    result.pathParams.append(property)
                case .query:
                    let isArray: Bool
                    if case .array(let element) = propertyType {
                        isArray = true
                        let itemSchema: JSONSchema?
                        if case .array(_, let array) = schema.value {
                            itemSchema = array.items
                        } else {
                            itemSchema = nil
                        }
                        let itemIsEnum =
                            try itemSchema.map {
                                try lookup.schema($0).allowedValues?.isEmpty == false
                            } ?? false
                        guard scalarTypes.contains(element.unwrapped) || itemIsEnum else {
                            throw unsupported(
                                "query array elements must be scalar or enum values", sourcePointer)
                        }
                    } else {
                        isArray = false
                        guard isScalar else {
                            throw unsupported(
                                "query parameters must be scalar or array values", sourcePointer)
                        }
                    }
                    guard !nullable(schema), context.style == .form, !context.allowReserved,
                        !isArray || context.explode
                    else {
                        throw unsupported(
                            "query parameters require form serialization with exploded arrays",
                            sourcePointer)
                    }
                    try queryNames.claim(
                        member, original: parameter.name, hint: renameHint(parameterTarget),
                        target: parameterTarget)
                    try claimDeprecatedBackingStorage(
                        for: property, using: &queryNames, hint: renameHint(parameterTarget),
                        target: parameterTarget)
                    if !parameter.required {
                        property.type = .optional(propertyType)
                        property.presence = .optional
                    }
                    result.queryParams.append(property)
                case .header:
                    guard [.string, .int, .int32, .int64, .double, .bool].contains(propertyType),
                        !nullable(schema), context.style == .simple
                    else {
                        throw unsupported(
                            "headers require simple String, integer, Double, or Bool values",
                            sourcePointer)
                    }
                    try headerNames.claim(
                        member, original: parameter.name, hint: renameHint(parameterTarget),
                        target: parameterTarget)
                    try claimDeprecatedBackingStorage(
                        for: property, using: &headerNames, hint: renameHint(parameterTarget),
                        target: parameterTarget)
                    if !parameter.required {
                        property.type = .optional(propertyType)
                        property.presence = .optional
                    }
                    result.headerParams.append(property)
                }
            } catch let error as Unsupported {
                // A missing path value makes the entire operation unusable.
                result.nested.removeSubrange(nestedStart...)
                if parameter.location == .path { throw error }
                report(error, at: sourcePointer)
            }
        }
        result.path = try pathSegments(path, properties: result.pathParams)
        if let request = operation.requestBody {
            let locatedBody = try lookup.resolve(request, at: pointer + "/requestBody")
            let body = try jsonRequestBody(locatedBody, lookup: lookup)
            let media = body.media
            let sourcePointer = media.pointer + "/schema"
            result.body = try type(
                body.schema, path: operationPath,
                typeID: .inline(.body(operationID)),
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
        let groups = groupedResponses(operation, id: operationID)
        for status in groups.ignored {
            diagnostics.append(
                source.diagnostic(
                    "Response status '\(status)' is ignored; only success and error outcomes are generated",
                    pointer + "/responses/" + status, .note))
        }
        let successes = groups.successes
        let errors = groups.errors
        guard !successes.isEmpty else {
            throw unsupported(
                "at least one success or default response is required", pointer + "/responses")
        }
        result.responseOutcomes = try responseOutcomes(
            successes,
            name: "Response", method: method,
            path: operationPath, operationID: operationID,
            pointer: pointer + "/responses",
            nested: &result.nested)
        result.response = responseType(
            result.responseOutcomes, name: "Response", path: operationPath)
        result.errorOutcomes = try responseOutcomes(
            errors,
            name: "ErrorResponse", method: method,
            path: operationPath, operationID: operationID,
            pointer: pointer + "/responses",
            nested: &result.nested)
        if !result.errorOutcomes.isEmpty {
            result.errorResponse =
                result.errorOutcomes.count == 1 && result.errorOutcomes[0].payload == nil
                ? nil
                : responseType(result.errorOutcomes, name: "ErrorResponse", path: operationPath)
        }
        var nestedNames = NameAllocator(
            reserved: Naming.namespaceReserved.union(Naming.endpointReserved)
                .subtracting(["Body", "Response", "ErrorResponse"]).union([namespace]),
            candidates: result.nested.map {
                NameAllocation(
                    name: $0.name,
                    original: targetSwift($0.namingTarget ?? .operation(operationID)),
                    hint: renameHint($0.namingTarget ?? .operation(operationID)),
                    target: $0.namingTarget ?? .operation(operationID),
                    pointer: $0.pointer)
            })
        for nested in result.nested {
            try nestedNames.claim(
                nested.name, original: nested.name,
                hint: renameHint(nested.namingTarget ?? .operation(operationID)),
                target: nested.namingTarget ?? .operation(operationID))
        }
        result.nested.sort { utf8Less($0.name, $1.name) }
        return result
    }

}

func operationIdentity(method: HTTPMethod, path: String) -> String {
    method.uppercase + " " + path
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
    if embedded { return .computed(result) }
    return .template(result)
}
#endif
