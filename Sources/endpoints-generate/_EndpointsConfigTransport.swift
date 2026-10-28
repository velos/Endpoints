#if OpenAPIGenerator || ENDPOINTS_CONFIG_PROGRAM
import EndpointsGeneratorConfig
#if ENDPOINTS_CONFIG_PROGRAM
// Narrow, file-private C ABI declarations avoid importing a platform module into the runner.
// All supported hosts use 64-bit size_t; no C varargs or FILE layout is exposed here.
@_silgen_name("fopen") private func configOpen(
    _ path: UnsafePointer<Int8>, _ mode: UnsafePointer<Int8>
) -> OpaquePointer?
@_silgen_name("fclose") private func configClose(_ file: OpaquePointer) -> Int32
@_silgen_name("fread") private func configRead(
    _ buffer: UnsafeMutableRawPointer?, _ size: Int, _ count: Int, _ file: OpaquePointer
) -> Int
@_silgen_name("fwrite") private func configWrite(
    _ buffer: UnsafeRawPointer?, _ size: Int, _ count: Int, _ file: OpaquePointer
) -> Int
@_silgen_name("ferror") private func configError(_ file: OpaquePointer) -> Int32
@_silgen_name("write") private func configStderr(
    _ fd: Int32, _ bytes: UnsafeRawPointer?, _ count: Int
) -> Int
@_silgen_name("exit") private func configExit(_ status: Int32) -> Never
#endif

/// Private file protocol. Shared source is compiled into the generator and embedded runner.
enum _EndpointsConfigTransport {
    struct Failure: Error { let message: String }
    struct Record {
        let target: NameTarget
        let wire: String
        let spec: String?
        let integer: String?
        let operationID: String?
        let route: String?
    }
    static func field(_ value: String?) -> String {
        guard let value else { return "-" }
        var bytes: [UInt8] = [61]
        for byte in value.utf8 {
            switch byte {
            case 92: bytes += [92, 92]
            case 9: bytes += [92, 116]
            case 10: bytes += [92, 110]
            case 13: bytes += [92, 114]
            default: bytes.append(byte)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
    static func unfield(_ value: Substring) throws -> String? {
        if value == "-" { return nil }
        guard value.first == "=" else { throw Failure(message: "invalid protocol field") }
        var bytes: [UInt8] = []
        var escaped = false
        for byte in value.utf8.dropFirst() {
            if escaped {
                switch byte {
                case 92: bytes.append(92)
                case 116: bytes.append(9)
                case 110: bytes.append(10)
                case 114: bytes.append(13)
                default: throw Failure(message: "invalid protocol escape")
                }
                escaped = false
            } else if byte == 92 {
                escaped = true
            } else {
                bytes.append(byte)
            }
        }
        guard !escaped else { throw Failure(message: "truncated protocol escape") }
        let text = String(decoding: bytes, as: UTF8.self)
        guard Array(text.utf8) == bytes else { throw Failure(message: "protocol is not UTF-8") }
        return text
    }
    static func operation(_ id: OperationID) -> [String] {
        switch id {
        case .id(let name): return ["id", name]
        case .route(let method, let path): return ["route", method.rawValue, path]
        }
    }
    static func type(_ id: TypeID) -> [String] {
        switch id {
        case .component(let name): return ["component", name]
        case .inline(let origin):
            switch origin {
            case .property(let name, let owner): return ["property", name] + type(owner)
            case .items(let owner): return ["items"] + type(owner)
            case .parameter(let name, let location, let id):
                return ["parameter", name, location.rawValue] + operation(id)
            case .body(let id): return ["body"] + operation(id)
            case .response(let id, let status): return ["response", status] + operation(id)
            case .errorResponse(let id, let status):
                return ["errorResponse", status] + operation(id)
            }
        }
    }
    static func target(_ value: NameTarget) -> [String] {
        switch value {
        case .type(let id): return ["type"] + type(id)
        case .property(let name, let id): return ["property", name] + type(id)
        case .enumCase(let name, let id): return ["enumCase", name] + type(id)
        case .parameter(let name, let location, let id):
            return ["parameter", name, location.rawValue] + operation(id)
        case .operation(let id): return ["operation"] + operation(id)
        case .environment(let name): return ["environment", name]
        }
    }
    struct Reader {
        let fields: [String?]
        var index = 0
        mutating func optional() throws -> String? {
            guard index < fields.count else { throw Failure(message: "truncated protocol record") }
            defer { index += 1 }
            return fields[index]
        }
        mutating func next() throws -> String {
            guard let value = try optional() else {
                throw Failure(message: "missing protocol value")
            }
            return value
        }
        mutating func operation() throws -> OperationID {
            switch try next() {
            case "id": return .id(try next())
            case "route":
                guard let method = HTTPMethod(rawValue: try next()) else {
                    throw Failure(message: "invalid method")
                }
                return .route(method: method, path: try next())
            default: throw Failure(message: "invalid operation identity")
            }
        }
        mutating func location() throws -> ParameterLocation {
            guard let value = ParameterLocation(rawValue: try next()) else {
                throw Failure(message: "invalid parameter location")
            }
            return value
        }
        mutating func type(depth: Int = 0) throws -> TypeID {
            guard depth < 256 else { throw Failure(message: "identity nesting exceeds 256") }
            switch try next() {
            case "component": return .component(try next())
            case "property": return .inline(.property(try next(), in: try type(depth: depth + 1)))
            case "items": return .inline(.items(of: try type(depth: depth + 1)))
            case "parameter":
                return .inline(.parameter(try next(), in: try location(), of: try operation()))
            case "body": return .inline(.body(try operation()))
            case "response":
                let status = try next()
                return .inline(.response(try operation(), status: status))
            case "errorResponse":
                let status = try next()
                return .inline(.errorResponse(try operation(), status: status))
            default: throw Failure(message: "invalid type identity")
            }
        }
        mutating func target() throws -> NameTarget {
            switch try next() {
            case "type": return .type(try type())
            case "property": return .property(try next(), in: try type())
            case "enumCase": return .enumCase(try next(), in: try type())
            case "parameter": return .parameter(try next(), in: try location(), of: try operation())
            case "operation": return .operation(try operation())
            case "environment": return .environment(try next())
            default: throw Failure(message: "invalid name target")
            }
        }
    }
    static func request(_ records: [Record]) -> String {
        var lines = ["endpoints-config-request 1"]
        for (i, record) in records.enumerated() {
            let values: [String?] =
                [String(i)] + target(record.target).map(Optional.some)
                + [record.wire, record.spec, record.integer, record.operationID, record.route]
            lines.append(values.map(field).joined(separator: "\t"))
        }
        return (lines + ["end \(records.count)", ""]).joined(separator: "\n")
    }
    static func lines(_ text: String, header: String) throws -> [Substring] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 3, lines.first == Substring(header), lines.last == "" else {
            throw Failure(message: "invalid protocol header or terminator")
        }
        return Array(lines.dropFirst().dropLast())
    }
    static func readRequest(_ text: String) throws -> [Record] {
        var lines = try lines(text, header: "endpoints-config-request 1")
        let trailer = lines.removeLast()
        guard trailer == Substring("end \(lines.count)") else {
            throw Failure(message: "request count mismatch")
        }
        return try lines.enumerated().map { i, line in
            var reader = Reader(
                fields: try line.split(separator: "\t", omittingEmptySubsequences: false).map(
                    unfield))
            guard try reader.next() == String(i) else {
                throw Failure(message: "request id mismatch")
            }
            let record = Record(
                target: try reader.target(), wire: try reader.next(), spec: try reader.optional(),
                integer: try reader.optional(), operationID: try reader.optional(),
                route: try reader.optional())
            guard reader.index == reader.fields.count else {
                throw Failure(message: "extra request fields")
            }
            return record
        }
    }
    static func response(_ names: [String?], json: String, fingerprint: String) -> String {
        let lines =
            ["endpoints-config-response 1 \(fingerprint)", "config\t" + field(json)]
            + names.enumerated().map { "\($0.offset)\t" + field($0.element) }
            + ["end \(names.count)", ""]
        return lines.joined(separator: "\n")
    }
    static func readResponse(_ text: String, count: Int, fingerprint: String) throws -> (
        String, [String?]
    ) {
        var lines = try lines(text, header: "endpoints-config-response 1 \(fingerprint)")
        guard lines.count == count + 2, lines.removeLast() == Substring("end \(count)") else {
            throw Failure(message: "response count mismatch")
        }
        let config = lines.removeFirst().split(separator: "\t", omittingEmptySubsequences: false)
        guard config.count == 2, config[0] == "config", let json = try unfield(config[1]) else {
            throw Failure(message: "missing declarative configuration")
        }
        let names: [String?] = try lines.enumerated().map { i, line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, fields[0] == Substring(String(i)) else {
                throw Failure(message: "response id mismatch")
            }
            return try unfield(fields[1])
        }
        return (json, names)
    }
    static func quote(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 34: out += "\\\""
            case 92: out += "\\\\"
            case 0...31:
                let digits = String(scalar.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - digits.count) + digits
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
    static func operationJSON(_ id: OperationID) -> String {
        switch id {
        case .id(let name): return quote(name)
        case .route(let method, let path):
            return "{\"method\":" + quote(method.rawValue) + ",\"path\":" + quote(path) + "}"
        }
    }
    static func typeJSON(_ id: TypeID) -> String {
        switch id {
        case .component(let name): return quote(name)
        case .inline(let origin):
            switch origin {
            case .property(let name, let owner):
                return "{\"property\":" + quote(name) + ",\"in\":" + typeJSON(owner) + "}"
            case .items(let owner): return "{\"items\":" + typeJSON(owner) + "}"
            case .parameter(let name, let location, let id):
                return "{\"parameter\":" + quote(name) + ",\"location\":" + quote(location.rawValue)
                    + ",\"operation\":" + operationJSON(id) + "}"
            case .body(let id): return "{\"body\":" + operationJSON(id) + "}"
            case .response(let id, let status):
                return "{\"response\":" + operationJSON(id) + ",\"status\":" + quote(status) + "}"
            case .errorResponse(let id, let status):
                return "{\"errorResponse\":" + operationJSON(id) + ",\"status\":" + quote(status)
                    + "}"
            }
        }
    }
    static func targetJSON(_ target: NameTarget) -> String {
        switch target {
        case .type(let id): return "\"type\":" + typeJSON(id)
        case .property(let name, let id):
            return "\"property\":" + quote(name) + ",\"in\":" + typeJSON(id)
        case .enumCase(let name, let id):
            return "\"enumCase\":" + quote(name) + ",\"in\":" + typeJSON(id)
        case .parameter(let name, let location, let id):
            return "\"parameter\":" + quote(name) + ",\"location\":" + quote(location.rawValue)
                + ",\"operation\":" + operationJSON(id)
        case .operation(let id): return "\"operation\":" + operationJSON(id)
        case .environment(let name): return "\"environment\":" + quote(name)
        }
    }
    static func dump(_ c: EndpointsConfiguration) -> String {
        func array(_ values: [String]) -> String {
            "[" + values.map(quote).joined(separator: ",") + "]"
        }
        var fields = [
            "\"version\":1", "\"accessLevel\":" + quote(c.accessLevel.rawValue),
            "\"strict\":" + String(c.strict),
            "\"enums\":" + quote(c.enums == .closed ? "closed" : "open"),
            "\"acronyms\":" + array(c.acronyms),
        ]
        if let namespace = c.namespace { fields.append("\"namespace\":" + quote(namespace)) }
        switch c.server {
        case .fromSpec: break
        case .type(let type): fields.append("\"server\":{\"type\":" + quote(type) + "}")
        case .environments(let environments, let defaultEnvironment):
            let values = environments.sorted {
                $0.key.rawValue.utf8.lexicographicallyPrecedes($1.key.rawValue.utf8)
            }.map { quote($0.key.rawValue) + ":" + quote($0.value) }.joined(separator: ",")
            fields.append(
                "\"server\":{\"environments\":{" + values + "},\"defaultEnvironment\":"
                    + quote(defaultEnvironment.rawValue) + "}")
        }
        fields.append(
            "\"operations\":{\"include\":" + array(c.operations.include) + ",\"exclude\":"
                + array(c.operations.exclude) + "}")
        for (key, strategy) in [
            ("typeNamingStrategy", c.typeNamingStrategy),
            ("propertyNamingStrategy", c.propertyNamingStrategy),
            ("parameterNamingStrategy", c.parameterNamingStrategy),
            ("enumCaseNamingStrategy", c.enumCaseNamingStrategy),
            ("operationNamingStrategy", c.operationNamingStrategy),
            ("environmentNamingStrategy", c.environmentNamingStrategy),
        ] {
            fields.append(quote(key) + ":" + quote(strategy.kind.rawValue))
        }
        let renames = c.renames.map {
            "{" + targetJSON($0.key) + ",\"name\":" + quote($0.value) + "}"
        }.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        fields.append("\"renames\":[" + renames.joined(separator: ",") + "]")
        return "{" + fields.joined(separator: ",") + "}"
    }
    static func matches(_ pattern: String, _ value: String) -> Bool {
        let p = Array(pattern.utf8)
        let v = Array(value.utf8)
        var i = 0
        var j = 0
        var star: Int?
        var retry = 0
        while j < v.count {
            if i < p.count && p[i] != 42 && p[i] == v[j] {
                i += 1
                j += 1
            } else if i < p.count && p[i] == 42 {
                star = i
                i += 1
                retry = j
            } else if let s = star {
                retry += 1
                j = retry
                i = s + 1
            } else {
                return false
            }
        }
        while i < p.count && p[i] == 42 { i += 1 }
        return i == p.count
    }
    static func resolve(_ records: [Record], configuration c: EndpointsConfiguration) -> [String?] {
        records.map { r in
            if case .environment = r.target {
                if case .fromSpec = c.server {} else { return nil }
            }
            if let route = r.route {
                let match: (String) -> Bool = {
                    matches($0, r.operationID ?? "") || matches($0, route)
                }
                if !c.operations.include.contains(where: match)
                    || c.operations.exclude.contains(where: match)
                {
                    return nil
                }
            }
            var context = NameContext(
                target: r.target, wireName: r.wire, specName: r.spec, acronyms: c.acronyms)
            if r.spec == nil, let integer = r.integer {
                context = NameContext(
                    target: r.target, wireName: r.wire, specName: nil, acronyms: c.acronyms,
                    camelCased: integer, upperCamelCased: integer, verbatim: integer)
            }
            return c.strategy(for: r.target).name(for: context)
        }
    }
    #if ENDPOINTS_CONFIG_PROGRAM
    private static func read(_ path: String) throws -> String {
        guard let file = path.withCString({ path in "rb".withCString { configOpen(path, $0) } })
        else { throw Failure(message: "cannot open request") }
        defer { _ = configClose(file) }
        var all: [UInt8] = []
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = buffer.withUnsafeMutableBytes {
                configRead($0.baseAddress, 1, $0.count, file)
            }
            if count == 0 { break }
            all += buffer.prefix(count)
        }
        guard configError(file) == 0 else { throw Failure(message: "cannot read request") }
        let text = String(decoding: all, as: UTF8.self)
        guard Array(text.utf8) == all else { throw Failure(message: "request is not UTF-8") }
        return text
    }
    static func main(configuration: EndpointsConfiguration, fingerprint: String) {
        do {
            guard CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "resolve" else {
                throw Failure(message: "invalid runner arguments")
            }
            try run(
                configuration: configuration, request: CommandLine.arguments[2],
                response: CommandLine.arguments[3], fingerprint: fingerprint)
        } catch {
            let message = Array("configuration transport failed: \(error)\n".utf8)
            message.withUnsafeBytes { _ = configStderr(2, $0.baseAddress, $0.count) }
            configExit(70)
        }
    }
    private static func run(
        configuration: EndpointsConfiguration, request: String, response: String,
        fingerprint: String
    ) throws {
        let records = try readRequest(read(request))
        let output = self.response(
            resolve(records, configuration: configuration), json: dump(configuration),
            fingerprint: fingerprint)
        guard let file = response.withCString({ path in "wb".withCString { configOpen(path, $0) } })
        else { throw Failure(message: "cannot open response") }
        let bytes = Array(output.utf8)
        let written = bytes.withUnsafeBytes { configWrite($0.baseAddress, 1, $0.count, file) }
        let closed = configClose(file)
        guard written == bytes.count && closed == 0 else {
            throw Failure(message: "cannot write response")
        }
    }
    #endif
}
#endif
