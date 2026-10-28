#if OpenAPIGenerator
import Foundation

struct Rendering {
    let module: Module
    let header: String
    var access: String { module.access.prefix }
    var namespace: String { module.namespace }

    private struct InitializerArgument {
        let name: String
        let type: String
        var defaultValue: String?
        var storageName: String?

        var signature: String {
            name + ": " + type + (defaultValue.map { " = " + $0 } ?? "")
        }
    }

    private struct ComponentGroup {
        let typeName: String
        let propertyName: String
        let properties: [Property]
    }

    private struct RenderedHeader {
        let name: String
        let expression: String
    }

    func file(_ body: (inout CodeWriter) -> Void) -> Data {
        var writer = CodeWriter()
        writer.line(header)
        writer.line()
        writer.line("import Endpoints")
        writer.line("import Foundation")
        writer.line()
        body(&writer)
        return Data(writer.finish().utf8)
    }

    func docs(_ paragraphs: [String], _ writer: inout CodeWriter) {
        for (index, paragraph) in paragraphs.enumerated() {
            if index > 0 { writer.line("///") }
            // Normalize authored line separators, then prefix every line so raw
            // specification text cannot inject Swift declarations.
            let normalized =
                paragraph
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\u{85}", with: "\n")
                .replacingOccurrences(of: "\u{2028}", with: "\n")
                .replacingOccurrences(of: "\u{2029}", with: "\n")
            for line in normalized.components(separatedBy: "\n") {
                let sanitized = line.replacingOccurrences(of: "\t", with: "    ")
                    .replacingOccurrences(of: "\u{feff}", with: "")
                writer.line(sanitized.isEmpty ? "///" : "/// " + sanitized)
            }
        }
    }

    func server() -> Data {
        file { writer in
            docs([module.title], &writer)
            writer.line("\(access)enum \(namespace) {")
            writer.indent()
            if let custom = module.server.customType {
                writer.line("\(access)typealias Server = \(custom)")
            } else {
                serverDeclaration(&writer)
                if !module.server.typical {
                    writer.line()
                    writer.line(
                        "\(access)enum Environment: String, Hashable, Sendable, CaseIterable {")
                    writer.indent()
                    for environment in module.server.environments {
                        docs(environment.docs, &writer)
                        writer.line("case \(environment.name)")
                    }
                    writer.outdent()
                    writer.line("}")
                }
            }
            writer.outdent()
            writer.line("}")
        }
    }

    private func serverDeclaration(_ writer: inout CodeWriter) {
        docs(module.server.securityDocs, &writer)
        writer.line("\(access)struct Server: ServerDefinition {")
        writer.indent()
        let environments =
            module.server.typical ? "TypicalEnvironments" : namespace + ".Environment"
        writer.line("\(access)typealias Environments = \(environments)")
        writer.line()
        writer.line("\(access)init() {}")
        writer.line()
        writer.line("\(access)var baseUrls: [Environments: URL] {")
        writer.indent()
        writer.line("[")
        writer.indent()
        for (index, environment) in module.server.environments.enumerated() {
            let comma = index == module.server.environments.count - 1 ? "" : ","
            writer.line(
                ".\(environment.name): URL(string: \(swiftLiteral(environment.url)))!\(comma)")
        }
        writer.outdent()
        writer.line("]")
        writer.outdent()
        writer.line("}")
        let defaultName =
            module.server.environments.first {
                $0.name.replacingOccurrences(of: "`", with: "")
                    == module.server.defaultEnvironment
            }?.name ?? module.server.defaultEnvironment
        writer.line()
        writer.line("\(access)static var defaultEnvironment: Environments { .\(defaultName) }")
        writer.outdent()
        writer.line("}")
    }

    func schemas() -> Data {
        file { writer in
            guard !module.schemas.isEmpty else {
                writer.line("// No component schemas.")
                return
            }
            writer.line("extension \(namespace) {")
            writer.indent()
            for (index, declaration) in module.schemas.enumerated() {
                if index > 0 { writer.line() }
                render(declaration, &writer)
            }
            writer.outdent()
            writer.line("}")
        }
    }

    func render(_ declaration: TypeDecl, _ writer: inout CodeWriter) {
        let documentation =
            declaration.docs
            + (declaration.deprecated
                ? ["- Important: Deprecated by the OpenAPI document."] : [])
        docs(documentation, &writer)
        switch declaration.kind {
        case .alias(let type):
            writer.line("\(access)typealias \(declaration.name) = \(type.swift)")
        case .structure:
            structure(declaration, &writer)
        case .statusUnion:
            statusUnion(declaration, &writer)
        case .closedEnum:
            writer.line(
                "\(access)enum \(declaration.name): \(declaration.enumRawType.swift), Codable, Hashable, Sendable, CaseIterable {"
            )
            writer.indent()
            for value in declaration.values {
                let identifier = value.name.replacingOccurrences(of: "`", with: "")
                let rawValue =
                    declaration.enumRawType == .string && wireEqual(identifier, value.raw)
                    ? "" : " = " + enumLiteral(value, in: declaration)
                writer.line("case \(value.name)\(rawValue)")
            }
            writer.outdent()
            writer.line("}")
        case .openEnum:
            writer.line(
                "\(access)struct \(declaration.name): RawRepresentable, Codable, Hashable, Sendable {"
            )
            writer.indent()
            writer.line("\(access)let rawValue: \(declaration.enumRawType.swift)")
            writer.line()
            initializer(
                [InitializerArgument(name: "rawValue", type: declaration.enumRawType.swift)],
                &writer)
            writer.line()
            for value in declaration.values {
                writer.line(
                    "\(access)static let \(value.name) = \(declaration.name)(rawValue: \(enumLiteral(value, in: declaration)))"
                )
            }
            let knownValues = declaration.values.map { "." + $0.name }.joined(separator: ", ")
            writer.line(
                "\(access)static let knownValues: [\(declaration.name)] = [\(knownValues)]")
            // RawRepresentable's Codable defaults use a single scalar container.
            writer.outdent()
            writer.line("}")
        }
    }

    private func enumLiteral(_ value: EnumValue, in declaration: TypeDecl) -> String {
        declaration.enumRawType == .string ? swiftLiteral(value.raw) : value.raw
    }

    private func structure(_ declaration: TypeDecl, _ writer: inout CodeWriter) {
        writer.line("\(access)struct \(declaration.name): Codable, Hashable, Sendable {")
        writer.indent()
        properties(declaration.properties, &writer)
        for child in declaration.nested {
            writer.line()
            render(child, &writer)
        }
        writer.line()
        let arguments = declaration.properties.map {
            InitializerArgument(
                name: $0.name, type: $0.type.swift,
                defaultValue: $0.presence == .optional ? "nil" : nil, storageName: $0.storageName)
        }
        initializer(arguments, &writer)
        let customCoding = declaration.properties.contains {
            $0.presence == .requiredNullable || $0.deprecated
        }
        if customCoding
            || declaration.properties.contains(where: {
                !wireEqual($0.name.replacingOccurrences(of: "`", with: ""), $0.wire)
            })
        {
            writer.line()
            writer.line("private enum CodingKeys: String, CodingKey {")
            writer.indent()
            for property in declaration.properties {
                let identifier = property.name.replacingOccurrences(of: "`", with: "")
                let rawValue =
                    wireEqual(identifier, property.wire)
                    ? "" : " = " + swiftLiteral(property.wire)
                writer.line("case \(property.name)\(rawValue)")
            }
            writer.outdent()
            writer.line("}")
        }
        if customCoding { codable(declaration.properties, &writer) }
        writer.outdent()
        writer.line("}")
    }

    private func codable(_ properties: [Property], _ writer: inout CodeWriter) {
        writer.line()
        writer.line("\(access)init(from decoder: any Decoder) throws {")
        writer.indent()
        writer.line("let container = try decoder.container(keyedBy: CodingKeys.self)")
        for property in properties {
            let type = property.presence == .optional ? property.type.unwrapped : property.type
            let method = property.presence == .optional ? "decodeIfPresent" : "decode"
            writer.line(
                "self.\(property.storageName) = try container.\(method)(\(type.swift).self, forKey: .\(property.name))"
            )
        }
        writer.outdent()
        writer.line("}")
        writer.line()
        writer.line("\(access)func encode(to encoder: any Encoder) throws {")
        writer.indent()
        writer.line("var container = encoder.container(keyedBy: CodingKeys.self)")
        for property in properties {
            let method = property.presence == .optional ? "encodeIfPresent" : "encode"
            writer.line(
                "try container.\(method)(\(property.storageName), forKey: .\(property.name))")
        }
        writer.outdent()
        writer.line("}")
    }

    private func properties(
        _ properties: [Property], _ writer: inout CodeWriter, storageAccess: String = "private"
    ) {
        for property in properties {
            if property.deprecated {
                writer.line("\(storageAccess) var \(property.storageName): \(property.type.swift)")
            }
            docs(property.docs, &writer)
            if property.deprecated {
                writer.line("@available(*, deprecated)")
                writer.line("\(access)var \(property.name): \(property.type.swift) {")
                writer.indent()
                writer.line("get { \(property.storageName) }")
                writer.line("set { \(property.storageName) = newValue }")
                writer.outdent()
                writer.line("}")
            } else {
                writer.line("\(access)var \(property.name): \(property.type.swift)")
            }
        }
    }

    private func initializer(_ arguments: [InitializerArgument], _ writer: inout CodeWriter) {
        guard !arguments.isEmpty else {
            writer.line("\(access)init() {}")
            return
        }
        let signature =
            access + "init(" + arguments.map(\.signature).joined(separator: ", ") + ") {"
        // Names and type spellings are ASCII. Counting UTF-8 bytes makes this
        // threshold independent of locale and includes the actual indentation.
        if writer.indentationWidth + signature.utf8.count <= 100 {
            writer.line(signature)
        } else {
            writer.line("\(access)init(")
            writer.indent()
            for (index, argument) in arguments.enumerated() {
                writer.line(argument.signature + (index == arguments.count - 1 ? "" : ","))
            }
            writer.outdent()
            writer.line(") {")
        }
        writer.indent()
        for argument in arguments {
            writer.line("self.\(argument.storageName ?? argument.name) = \(argument.name)")
        }
        writer.outdent()
        writer.line("}")
    }

    func endpoints() -> Data {
        file { writer in
            guard !module.endpoints.isEmpty else {
                writer.line("// No operations.")
                return
            }
            writer.line("extension \(namespace) {")
            writer.indent()
            for (index, endpoint) in module.endpoints.enumerated() {
                if index > 0 { writer.line() }
                render(endpoint, &writer)
            }
            writer.outdent()
            writer.line("}")
            for conformance in module.parameterConformances {
                writer.line()
                if conformance.deprecated { writer.line("@available(*, deprecated)") }
                writer.line(
                    "extension \(conformance.typeName): PathRepresentable, ParameterRepresentable {}"
                )
            }
        }
    }

    private func render(_ endpoint: EndpointDecl, _ writer: inout CodeWriter) {
        docs(endpoint.docs, &writer)
        if endpoint.deprecated { writer.line("@available(*, deprecated)") }
        writer.line("\(access)struct \(endpoint.name): Endpoint {")
        writer.indent()
        writer.line("\(access)typealias Server = \(namespace).Server")
        let base = namespace + "." + endpoint.name + "."
        func typealiasIfNeeded(_ name: String, _ type: TypeRef?) {
            if let type, type != .named(base + name) {
                writer.line("\(access)typealias \(name) = \(type.swift)")
            }
        }
        typealiasIfNeeded("Response", endpoint.response)
        typealiasIfNeeded("ErrorResponse", endpoint.errorResponse)
        typealiasIfNeeded("Body", endpoint.body)
        if endpoint.noAuth {
            writer.line()
            writer.line("\(access)static var auth: NoAuth { NoAuth() }")
        }
        definition(endpoint, &writer)
        let groups = [
            ComponentGroup(
                typeName: "PathComponents", propertyName: "pathComponents",
                properties: endpoint.pathParams),
            ComponentGroup(
                typeName: "ParameterComponents", propertyName: "parameterComponents",
                properties: endpoint.queryParams),
            ComponentGroup(
                typeName: "HeaderComponents", propertyName: "headerComponents",
                properties: endpoint.headerParams),
        ].filter { !$0.properties.isEmpty }
        for group in groups {
            writer.line()
            writer.line("\(access)struct \(group.typeName): Sendable {")
            writer.indent()
            properties(group.properties, &writer, storageAccess: "fileprivate")
            writer.line()
            initializer(
                group.properties.map {
                    InitializerArgument(
                        name: $0.name, type: $0.type.swift,
                        defaultValue: $0.presence == .optional ? "nil" : nil,
                        storageName: $0.storageName)
                }, &writer)
            if group.typeName == "PathComponents", case .computed(let segments) = endpoint.path {
                writer.line()
                writer.line("fileprivate var _endpointPath: \(namespace).EncodedPath {")
                writer.indent()
                writer.line(".init(pathSafe: \(pathLiteral(segments, computed: true)))")
                writer.outdent()
                writer.line("}")
            }
            writer.outdent()
            writer.line("}")
        }
        for declaration in endpoint.nested {
            writer.line()
            render(declaration, &writer)
        }
        var arguments = groups.map { group in
            InitializerArgument(
                name: group.propertyName,
                type: group.typeName,
                defaultValue: group.properties.allSatisfy { $0.presence == .optional }
                    ? group.typeName + "()" : nil
            )
        }
        if endpoint.body != nil {
            arguments.append(InitializerArgument(name: "body", type: "Body"))
        }
        if !arguments.isEmpty { writer.line() }
        for argument in arguments {
            writer.line("\(access)let \(argument.name): \(argument.type)")
        }
        writer.line()
        initializer(arguments, &writer)
        let responseNeedsDecoder = endpoint.responseUsesDate || endpoint.responseOutcomes.count > 1
        let errorNeedsDecoder =
            endpoint.errorUsesDate || endpoint.errorOutcomes.count > 1
            || endpoint.errorOutcomes.contains(where: \.rawBody)
        if endpoint.bodyUsesDate || responseNeedsDecoder || errorNeedsDecoder {
            writer.line()
            if endpoint.bodyUsesDate {
                writer.line(
                    "\(access)static var bodyEncoder: JSONEncoder { \(namespace).JSONCoding.makeEncoder() }"
                )
            }
            if responseNeedsDecoder {
                decoderOverride("responseDecoder", outcomes: endpoint.responseOutcomes, &writer)
            }
            if errorNeedsDecoder {
                decoderOverride("errorDecoder", outcomes: endpoint.errorOutcomes, &writer)
            }
        }
        writer.outdent()
        writer.line("}")
    }

    private func pathLiteral(_ segments: [PathSegment], computed: Bool = false) -> String {
        var result = "\""
        for segment in segments {
            switch segment {
            case .literal(let literal): result += swiftLiteral(literal).dropFirst().dropLast()
            case .parameter(let parameter):
                result += computed ? "\\(\(parameter).pathSafe)" : "\\(path: \\.\(parameter))"
            }
        }
        return result + "\""
    }

    private func definition(_ endpoint: EndpointDecl, _ writer: inout CodeWriter) {
        writer.line()
        writer.line(
            "\(access)static let definition: Definition<\(endpoint.name)> = Definition(")
        writer.indent()
        writer.line("method: .\(endpoint.method.rawValue),")
        let path: String
        switch endpoint.path {
        case .template(let segments): path = pathLiteral(segments)
        case .computed: path = "\"\\(path: \\._endpointPath)\""
        }
        let headers =
            (endpoint.headerParams.map {
                RenderedHeader(name: $0.wire, expression: ".field(path: \\.\($0.storageName))")
            }
            + endpoint.fixedHeaders.map {
                RenderedHeader(
                    name: $0.name, expression: ".fieldValue(value: \(swiftLiteral($0.value)))")
            }).sorted { utf8Less($0.name, $1.name) }
        writer.line(
            "path: \(path)\(endpoint.queryParams.isEmpty && headers.isEmpty ? "" : ",")")
        if !endpoint.queryParams.isEmpty {
            writer.line("parameters: [")
            writer.indent()
            for (index, property) in endpoint.queryParams.enumerated() {
                let comma = index == endpoint.queryParams.count - 1 ? "" : ","
                writer.line(
                    ".query(\(swiftLiteral(property.wire)), path: \\.\(property.storageName))\(comma)"
                )
            }
            writer.outdent()
            writer.line("]\(headers.isEmpty ? "" : ",")")
        }
        if !headers.isEmpty {
            writer.line("headers: [")
            writer.indent()
            for (index, header) in headers.enumerated() {
                let comma = index == headers.count - 1 ? "" : ","
                writer.line("\(swiftLiteral(header.name)): \(header.expression)\(comma)")
            }
            writer.outdent()
            writer.line("]")
        }
        writer.outdent()
        writer.line(")")
    }

    func support() -> Data {
        file { writer in
            writer.line("extension \(namespace) {")
            writer.indent()
            if module.endpoints.contains(where: {
                if case .computed = $0.path { return true }
                return false
            }) {
                writer.line(
                    "/// A path assembled from literal text and individually encoded parameter values."
                )
                writer.line("struct EncodedPath: PathRepresentable {")
                writer.indent()
                writer.line("let pathSafe: String")
                writer.outdent()
                writer.line("}")
                writer.line()
            }
            writer.line("enum JSONCoding {")
            writer.indent()
            writer.line("static func makeDecoder(")
            writer.indent()
            writer.line(
                "isRawDataStatus: @Sendable @escaping (_ statusCode: Int) -> Bool = { _ in false }")
            writer.outdent()
            writer.line(") -> HTTPResponseJSONDecoder {")
            writer.indent()
            if module.usesDate {
                writer.line(
                    "HTTPResponseJSONDecoder(isRawDataStatus: isRawDataStatus) { decoder in")
                writer.indent()
                dateDecoding(&writer)
                writer.outdent()
                writer.line("}")
            } else {
                writer.line("HTTPResponseJSONDecoder(isRawDataStatus: isRawDataStatus)")
            }
            writer.outdent()
            writer.line("}")
            writer.line()
            writer.line("static func makeEncoder() -> JSONEncoder {")
            writer.indent()
            writer.line("let encoder = JSONEncoder()")
            writer.line("encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]")
            if module.usesDate { dateEncoding(&writer) }
            writer.line("return encoder")
            writer.outdent()
            writer.line("}")
            writer.outdent()
            writer.line("}")
            if module.usesDate {
                writer.line()
                writer.line(Self.rfc3339Source)
            }
            writer.outdent()
            writer.line("}")
        }
    }

    private func dateDecoding(_ writer: inout CodeWriter) {
        writer.line("decoder.dateDecodingStrategy = .custom { decoder in")
        writer.indent()
        writer.line("let container = try decoder.singleValueContainer()")
        writer.line("let string = try container.decode(String.self)")
        writer.line("guard let date = RFC3339.parse(string) else {")
        writer.indent()
        writer.line("throw DecodingError.dataCorruptedError(")
        writer.indent()
        writer.line("in: container,")
        writer.line("debugDescription: \"Expected an RFC 3339 date-time.\"")
        writer.outdent()
        writer.line(")")
        writer.outdent()
        writer.line("}")
        writer.line("return date")
        writer.outdent()
        writer.line("}")
    }

    private func dateEncoding(_ writer: inout CodeWriter) {
        writer.line("encoder.dateEncodingStrategy = .custom { date, encoder in")
        writer.indent()
        writer.line("let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()")
        writer.line("guard milliseconds.isFinite,")
        writer.indent()
        writer.line("milliseconds >= -62_167_219_200_000,")
        writer.line("milliseconds < 253_402_300_800_000")
        writer.outdent()
        writer.line("else {")
        writer.indent()
        // Use seconds: describing a non-finite Date traps on Linux.
        writer.line("// Use seconds: describing a non-finite Date traps on Linux.")
        writer.line("throw EncodingError.invalidValue(")
        writer.indent()
        writer.line("date.timeIntervalSince1970,")
        writer.line("EncodingError.Context(")
        writer.indent()
        writer.line("codingPath: encoder.codingPath,")
        writer.line("debugDescription: \"Expected a finite date-time in years 0000 through 9999.\"")
        writer.outdent()
        writer.line(")")
        writer.outdent()
        writer.line(")")
        writer.outdent()
        writer.line("}")
        writer.line("var container = encoder.singleValueContainer()")
        writer.line("try container.encode(RFC3339.format(date))")
        writer.outdent()
        writer.line("}")
    }
}
#endif
