#if OpenAPIGenerator
import Dispatch
import EndpointsGeneratorConfig
import EndpointsGeneratorCore
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

struct ConfigProgramFailure: Error {
    let diagnostics: [String]
}

/// The only child-process interface. Files, never pipes; completion has a bounded wait.
struct ConfigProcessRunner: Sendable {
    struct Result {
        let status: Int32
        let signalled: Bool
        let timedOut: Bool
        let stdout: URL
        let stderr: URL
        func text(_ url: URL, limit: Int = 65_536) -> String {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
            defer { try? handle.close() }
            // The package's macOS floor is 10.15; the throwing FileHandle API needs 10.15.4.
            if #available(macOS 10.15.4, *) {
                let size = (try? handle.seekToEnd()) ?? 0
                try? handle.seek(toOffset: size > UInt64(limit) ? size - UInt64(limit) : 0)
                return String(decoding: (try? handle.read(upToCount: limit)) ?? Data(), as: UTF8.self)
            } else {
                let size = handle.seekToEndOfFile()
                handle.seek(toFileOffset: size > UInt64(limit) ? size - UInt64(limit) : 0)
                return String(decoding: handle.readData(ofLength: limit), as: UTF8.self)
            }
        }
        var tail: String { text(stderr).split(separator: "\n").suffix(20).joined(separator: "\n") }
    }
    func run(
        _ executable: URL, arguments: [String], directory: URL,
        environment: [String: String]? = nil, timeout: TimeInterval = 60
    ) throws -> Result {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stdout = directory.appendingPathComponent("stdout.log")
        let stderr = directory.appendingPathComponent("stderr.log")
        guard FileManager.default.createFile(atPath: stdout.path, contents: nil),
            FileManager.default.createFile(atPath: stderr.path, contents: nil)
        else {
            throw ConfigProgramFailure(diagnostics: ["cannot prepare config program I/O"])
        }
        let input = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/null"))
        let output = try FileHandle(forWritingTo: stdout)
        let error = try FileHandle(forWritingTo: stderr)
        defer {
            try? input.close()
            try? output.close()
            try? error.close()
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment ?? ProcessInfo.processInfo.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.currentDirectoryURL = directory
        let terminated = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminated.signal() }
        try process.run()
        let timedOut = terminated.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            // Foundation creates a process group for the child on both hosts.
            // Kill its descendants too, including swiftc's frontend jobs.
            if kill(-process.processIdentifier, SIGKILL) != 0 {
                _ = kill(process.processIdentifier, SIGKILL)
            }
            // Never call waitUntilExit: a broken Foundation completion path must remain bounded.
            if terminated.wait(timeout: .now() + 2) == .timedOut {
                return Result(
                    status: -1, signalled: false, timedOut: true, stdout: stdout, stderr: stderr)
            }
        }
        return Result(
            status: process.terminationStatus,
            signalled: process.terminationReason == .uncaughtSignal,
            timedOut: timedOut, stdout: stdout, stderr: stderr)
    }
}

final class ConfigFileLock {
    let descriptor: Int32
    init(_ url: URL, operation: Int32 = LOCK_EX) throws {
        let opened = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600))
        guard opened >= 0 else {
            throw ConfigProgramFailure(diagnostics: [
                "cannot open configuration cache lock: \(String(cString: strerror(errno)))"
            ])
        }
        while flock(opened, operation) != 0 {
            if errno == EINTR { continue }
            let failure = errno
            _ = close(opened)
            throw ConfigProgramFailure(diagnostics: [
                "cannot acquire configuration cache lock: \(String(cString: strerror(failure)))"
            ])
        }
        descriptor = opened
    }
    deinit {
        _ = flock(descriptor, LOCK_UN)
        _ = close(descriptor)
    }
}

struct ConfigCacheInputs {
    var config: Data
    var header: String
    var dsl: String
    var transport: String
    var main: String
    var stem: String
    var entrySymbol: String
    var flags: [String]
    var compiler: String
    var sdk: String
    var generator: String
    var key: String {
        ConfigProgram.identity(
            [config]
                + [
                    header, dsl, transport, main, stem, entrySymbol,
                    flags.joined(separator: "\u{0}"), compiler, sdk, generator,
                ].map { Data($0.utf8) })
    }
}

/// Host compiler/SDK identities and all nondeterministic cache bookkeeping stay here.
final class ConfigProgram {
    let path: URL
    let diagnosticPath: String
    let stem: String
    let source: Data
    let entryLine: Int
    let entryColumn: Int
    let cache: URL
    let runner = ConfigProcessRunner()
    let compiler: URL
    let sdkFlags: [String]
    let compilerIdentity: String
    let sdkIdentity: String
    let fingerprint: String
    let mainSource: String
    let key: String
    private(set) var compilerDiagnostics: [String] = []
    private(set) var cacheHit = false
    private(set) var compileDuration: TimeInterval = 0
    private(set) var runDurations: [TimeInterval] = []
    var runDuration: TimeInterval { runDurations.reduce(0, +) }

    static func temporary(_ parent: URL, prefix: String) throws -> URL {
        let url = parent.appendingPathComponent(prefix + "-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func identity(_ components: [Data]) -> String {
        var bytes: [UInt8] = []
        for part in components { bytes += Array(String(part.count).utf8) + [58] + Array(part) }
        return SHA256.hex(bytes)
    }
    static func executableOnPath(_ name: String) -> URL? {
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin").split(
            separator: ":")
        {
            let url = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
    init(
        path: URL, stem: String, swiftc: URL?, cache: URL, diagnosticPath: String? = nil
    ) throws {
        let diagnosticPath = diagnosticPath ?? path.path
        self.diagnosticPath = diagnosticPath
        self.path = path.standardizedFileURL
        self.stem = stem
        self.source = try Data(contentsOf: path)
        guard Naming.isIdentifier(stem), !Naming.keywords.contains(stem) else {
            throw ConfigProgramFailure(diagnostics: [
                "\(diagnosticPath):1:1: error: stem must be a non-keyword ASCII Swift identifier"
            ])
        }
        self.cache = cache.standardizedFileURL
        let checkedSource = ConfigLexicalCheck.analyze(source, stem: stem)
        entryLine = checkedSource.entryLine
        entryColumn = checkedSource.entryColumn
        let issues = checkedSource.issues
        guard issues.isEmpty else {
            throw ConfigProgramFailure(diagnostics: issues.map { $0.formatted(path: diagnosticPath) })
        }
        try FileManager.default.createDirectory(at: self.cache, withIntermediateDirectories: true)
        let probe = try Self.temporary(
            self.cache.appendingPathComponent("runs"), prefix: "identity")
        defer { try? FileManager.default.removeItem(at: probe) }
        let runner = ConfigProcessRunner()
        func command(_ executable: URL, _ arguments: [String], _ label: String) throws -> String {
            let logs = try Self.temporary(probe, prefix: label)
            let result = try runner.run(
                executable, arguments: arguments, directory: logs, timeout: 30)
            guard result.status == 0 && !result.timedOut else {
                throw ConfigProgramFailure(diagnostics: [
                    "\(diagnosticPath):1:1: error: cannot determine \(label)\n" + result.tail
                ])
            }
            return result.text(result.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var selected = swiftc
        #if !os(Linux)
        if selected == nil {
            let found = try? command(
                URL(fileURLWithPath: "/usr/bin/xcrun"), ["--find", "swiftc"], "swiftc")
            selected = found.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        }
        #endif
        guard let selected = selected ?? Self.executableOnPath("swiftc"),
            FileManager.default.isExecutableFile(atPath: selected.path)
        else {
            throw ConfigProgramFailure(diagnostics: [
                "\(diagnosticPath):1:1: error: cannot find host swiftc; pass --swiftc <path>"
            ])
        }
        compiler = selected.standardizedFileURL
        let identity = try ConfigToolchainIdentity.load(
            compiler: compiler, cache: self.cache,
            developerDirectory: ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
            command: command)
        compilerIdentity = identity.compilerVersion + "\n"
            + compiler.resolvingSymlinksInPath().path + "\n" + compiler.path
        #if os(Linux)
        sdkFlags = []
        sdkIdentity = compiler.resolvingSymlinksInPath().deletingLastPathComponent().path
        #else
        sdkFlags = ["-sdk", identity.sdkPath!]
        sdkIdentity = identity.sdkPath! + "\n" + identity.sdkBuild!
        #endif
        fingerprint = String(
            Self.identity([
                Data(Embedded.dsl.utf8), Data(Embedded.transport.utf8), Data("protocol-1".utf8),
            ]).prefix(16))
        let symbol = ConfigLexicalCheck.entrySymbol(stem: stem)
        mainSource = """
            import EndpointsGeneratorConfig
            _EndpointsConfigTransport.main(configuration: \(symbol), fingerprint: "\(fingerprint)")
            """
        let flags =
            Self.commonFlags + sdkFlags + Self.libraryFlags + Self.programFlags + Self.linkFlags
            + [
                "-module-cache-path", "<cache>/ModuleCache", "-emit-module-path",
                "<entry>/EndpointsGeneratorConfig.swiftmodule",
                "-o", "<entry>/libEndpointsGeneratorConfig.a",
                "<entry>/EndpointsGeneratorConfig.swift",
                "-o", "<entry>/config", "<user-config>", "<entry>/_EndpointsConfigTransport.swift",
                "<entry>/main.swift",
            ]
        key =
            ConfigCacheInputs(
                config: source, header: "1", dsl: Embedded.dsl, transport: Embedded.transport,
                main: mainSource, stem: stem, entrySymbol: symbol, flags: flags,
                compiler: compilerIdentity, sdk: sdkIdentity, generator: GeneratorVersion.current
            ).key
    }
    static let commonFlags = [
        "-swift-version", "6", "-package-name", "EndpointsConfigProgram", "-Onone",
    ]
    // Paths are normalized placeholders in the key so copying an entry to another scratch root can hit.
    static let libraryFlags = [
        "-parse-as-library", "-emit-library", "-static", "-emit-module", "-module-name",
        "EndpointsGeneratorConfig", "-warnings-as-errors",
    ]
    static let programFlags = [
        "-D", "ENDPOINTS_CONFIG_PROGRAM", "-I", "<entry>", "-L", "<entry>",
        "-lEndpointsGeneratorConfig", "-module-name", "EndpointsConfigProgram",
    ]

    static var linkFlags: [String] {
        #if os(Linux)
        ["-Xlinker", "--gc-sections", "-Xlinker", "-s"]
        #else
        [
            "-Xlinker", "-dead_strip", "-Xlinker", "-x", "-Xlinker", "-exported_symbol", "-Xlinker",
            "_main",
        ]
        #endif
    }

    func checked(
        _ executable: URL, _ arguments: [String], logs: URL, purpose: String, timeout: TimeInterval
    ) throws -> ConfigProcessRunner.Result {
        let result: ConfigProcessRunner.Result
        do {
            result = try runner.run(
                executable, arguments: arguments, directory: logs, timeout: timeout)
        } catch {
            throw ConfigProgramFailure(diagnostics: [
                "\(diagnosticPath):1:1: error: cannot launch \(purpose): \(error)"
            ])
        }
        let blocks = CompilerDiagnosticBlock.parse(result.text(result.stderr))
        let forwarded = blocks.filter { isConfigurationPath($0.path) }
        if result.timedOut || result.signalled || result.status != 0 {
            var messages = forwarded.map(configurationDiagnostic)
            var locatedError = forwarded.contains { $0.severity == "error" }
            if !locatedError, blocks.contains(where: { $0.severity == "error" }) {
                messages.insert(
                    "\(diagnosticPath):\(entryLine):\(entryColumn): error: "
                        + ConfigLexicalCheck.entryMessage(stem: stem), at: 0)
                locatedError = true
            }
            if !locatedError {
                let reason = result.timedOut
                    ? "timed out after \(Int(timeout)) s"
                    : result.signalled
                        ? "was terminated by signal \(result.status)"
                        : "exited with status \(result.status)"
                messages.insert("\(diagnosticPath):1:1: error: \(purpose) \(reason)", at: 0)
                if blocks.isEmpty { messages += stderrNotes(result.tail) }
            }
            throw ConfigProgramFailure(diagnostics: compilerDiagnostics + messages)
        }
        for block in forwarded {
            let diagnostic = configurationDiagnostic(block)
            if !compilerDiagnostics.contains(diagnostic) {
                compilerDiagnostics.append(diagnostic)
            }
        }
        return result
    }
    private func configurationDiagnostic(_ block: CompilerDiagnosticBlock) -> String {
        diagnosticPath + block.text.dropFirst(block.path.count)
    }
    private func isConfigurationPath(_ candidate: String) -> Bool {
        URL(fileURLWithPath: candidate).standardizedFileURL.resolvingSymlinksInPath()
            == path.standardizedFileURL.resolvingSymlinksInPath()
    }
    private func stderrNotes(_ tail: String) -> [String] {
        tail.split(separator: "\n").map { "\(diagnosticPath):1:1: note: " + $0 }
    }
    func valid(_ entry: URL) -> Bool {
        guard
            let manifest = try? String(
                contentsOf: entry.appendingPathComponent("manifest"), encoding: .utf8),
            let data = try? Data(contentsOf: entry.appendingPathComponent("config")),
            FileManager.default.fileExists(atPath: entry.appendingPathComponent("lease").path),
            FileManager.default.isExecutableFile(
                atPath: entry.appendingPathComponent("config").path)
        else { return false }
        guard let diagnostics = try? Data(
            contentsOf: entry.appendingPathComponent("diagnostics.json")),
            (try? JSONDecoder().decode([String].self, from: diagnostics)) != nil
        else { return false }
        return manifest == key + "\n" + SHA256.hex(Array(data)) + "\n"
    }
    private func prepareModuleCache() throws {
        let marker = cache.appendingPathComponent("ModuleCache.identity")
        let identity =
            cache.path + "\n" + compilerIdentity + "\n" + sdkIdentity + "\n"
            + fingerprint + "\n" + Self.commonFlags.joined(separator: " ")
        if (try? String(contentsOf: marker, encoding: .utf8)) != identity {
            try? FileManager.default.removeItem(at: cache.appendingPathComponent("ModuleCache"))
            try Data(identity.utf8).write(to: marker, options: .atomic)
        }
    }
    private func compile(_ entry: URL) throws {
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            compileDuration =
                TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        }
        let manager = FileManager.default
        let temporary = try Self.temporary(
            cache.appendingPathComponent("entries"), prefix: ".tmp-" + key)
        defer { try? manager.removeItem(at: temporary) }
        let dsl = temporary.appendingPathComponent("EndpointsGeneratorConfig.swift")
        let transport = temporary.appendingPathComponent("_EndpointsConfigTransport.swift")
        let main = temporary.appendingPathComponent("main.swift")
        try Data(Embedded.dsl.utf8).write(to: dsl)
        try Data(Embedded.transport.utf8).write(to: transport)
        try Data(mainSource.utf8).write(to: main)
        let common =
            Self.commonFlags + sdkFlags + [
                "-module-cache-path", cache.appendingPathComponent("ModuleCache").path,
            ]
        _ = try checked(
            compiler,
            common + Self.libraryFlags + [
                "-emit-module-path",
                temporary.appendingPathComponent("EndpointsGeneratorConfig.swiftmodule").path, "-o",
                temporary.appendingPathComponent("libEndpointsGeneratorConfig.a").path, dsl.path,
            ], logs: temporary.appendingPathComponent("library-logs"),
            purpose: "configuration library compiler", timeout: 300)
        let imports = try checked(
            compiler,
            ["-frontend", "-emit-imported-modules"] + common + ["-I", temporary.path, path.path],
            logs: temporary.appendingPathComponent("import-logs"),
            purpose: "configuration import check", timeout: 300)
        let modules = imports.text(imports.stdout).split(whereSeparator: \.isWhitespace).map(
            String.init)
        if modules.contains(where: { !["Swift", "EndpointsGeneratorConfig"].contains($0) }) {
            throw ConfigProgramFailure(diagnostics: [
                "\(diagnosticPath):1:1: error: configuration files may only import EndpointsGeneratorConfig"
            ])
        }
        _ = try checked(
            compiler,
            common + Self.linkFlags + [
                "-D", "ENDPOINTS_CONFIG_PROGRAM", "-I", temporary.path, "-L", temporary.path,
                "-lEndpointsGeneratorConfig", "-module-name", "EndpointsConfigProgram", "-o",
                temporary.appendingPathComponent("config").path, path.path, transport.path,
                main.path,
            ], logs: temporary.appendingPathComponent("program-logs"),
            purpose: "configuration compiler", timeout: 300)
        // The config was compiled in place; avoid publishing if it changed during compilation.
        guard try Data(contentsOf: path) == source else {
            throw ConfigProgramFailure(diagnostics: [
                "\(diagnosticPath):1:1: error: configuration changed during compilation; build again"
            ])
        }
        let binary = try Data(contentsOf: temporary.appendingPathComponent("config"))
        try Data((key + "\n" + SHA256.hex(Array(binary)) + "\n").utf8).write(
            to: temporary.appendingPathComponent("manifest"))
        let cachedDiagnostics = compilerDiagnostics.map { diagnostic in
            guard let block = CompilerDiagnosticBlock.parse(diagnostic).first else {
                return diagnostic
            }
            return "<configuration>" + diagnostic.dropFirst(block.path.count)
        }
        try JSONEncoder().encode(cachedDiagnostics).write(
            to: temporary.appendingPathComponent("diagnostics.json"))
        try Data().write(to: temporary.appendingPathComponent("lease"))
        // Intermediate modules and archives are unnecessary after the static link.
        for file in try manager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
        where !["config", "manifest", "lease", "diagnostics.json"].contains(file.lastPathComponent) {
            try manager.removeItem(at: file)
        }
        try manager.moveItem(at: temporary, to: entry)
    }
    private func evict(protecting key: String) {
        let manager = FileManager.default
        let entries = cache.appendingPathComponent("entries")
        let candidates =
            ((try? manager.contentsOfDirectory(at: entries, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
        func accessed(_ url: URL) -> Date {
            let usage = cache.appendingPathComponent("usage").appendingPathComponent(
                url.lastPathComponent)
            return
                ((try? manager.attributesOfItem(atPath: usage.path))?[.modificationDate] as? Date)
                ?? .distantPast
        }
        let newest = candidates.sorted { accessed($0) > accessed($1) }
        let stale = Date().addingTimeInterval(-3600)
        for directory in [cache.appendingPathComponent("runs"), entries] {
            for item
                in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
                ?? []
            {
                guard
                    directory.lastPathComponent == "runs"
                        || item.lastPathComponent.hasPrefix(".tmp-")
                        || item.lastPathComponent.hasPrefix(".trash-")
                else { continue }
                if let modified = (try? manager.attributesOfItem(atPath: item.path))?[
                    .modificationDate]
                    as? Date, modified < stale
                {
                    try? manager.removeItem(at: item)
                }
            }
        }
        let recent = Date().addingTimeInterval(-600)
        func bytes(in directory: URL) -> Int {
            guard
                let files = manager.enumerator(
                    at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
            else { return 0 }
            return files.reduce(0) { total, item in
                guard let url = item as? URL,
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]
                    ),
                    values.isRegularFile == true
                else { return total }
                return total + (values.fileSize ?? 0)
            }
        }
        // The ten-minute grace period yields to the persistent-cache budget. The newest
        // two and all leased entries remain protected even if a large config exceeds it.
        var retainedBytes =
            bytes(in: entries) + bytes(in: cache.appendingPathComponent("ModuleCache"))
        for entry in newest.dropFirst(2).reversed() where entry.lastPathComponent != key {
            guard accessed(entry) < recent || retainedBytes > 2_000_000 else { continue }
            guard
                let lease = try? ConfigFileLock(
                    entry.appendingPathComponent("lease"), operation: LOCK_EX | LOCK_NB)
            else { continue }
            withExtendedLifetime(lease) {
                let size = bytes(in: entry)
                let trash = entries.appendingPathComponent(".trash-" + UUID().uuidString)
                if (try? manager.moveItem(at: entry, to: trash)) != nil {
                    retainedBytes -= size
                    try? manager.removeItem(at: trash)
                }
                try? manager.removeItem(
                    at: cache.appendingPathComponent("usage").appendingPathComponent(
                        entry.lastPathComponent))
            }
        }
    }
    func evaluate(_ requests: [NameRequest]) throws -> EvaluatedSwiftConfiguration {
        guard try Data(contentsOf: path) == source else {
            throw ConfigProgramFailure(diagnostics: [
                "\(diagnosticPath):1:1: error: configuration changed during generation; build again"
            ])
        }
        let manager = FileManager.default
        let entries = cache.appendingPathComponent("entries")
        try manager.createDirectory(at: entries, withIntermediateDirectories: true)
        let entry = entries.appendingPathComponent(key)
        let lease: ConfigFileLock
        do {
            let lock = try ConfigFileLock(cache.appendingPathComponent("lock"))
            lease = try withExtendedLifetime(lock) {
                try prepareModuleCache()
                if valid(entry) {
                    cacheHit = true
                    let data = try Data(contentsOf: entry.appendingPathComponent("diagnostics.json"))
                    let cached = try JSONDecoder().decode([String].self, from: data).map {
                        $0.hasPrefix("<configuration>:")
                            ? path.path + ":" + $0.dropFirst("<configuration>:".count) : $0
                    }
                    // Also sanitize restored metadata produced before config-only filtering.
                    compilerDiagnostics = cached.flatMap(CompilerDiagnosticBlock.parse)
                        .filter { isConfigurationPath($0.path) }
                        .map(configurationDiagnostic)
                } else {
                    if manager.fileExists(atPath: entry.path) {
                        let repairing = try ConfigFileLock(
                            entry.appendingPathComponent("lease"), operation: LOCK_EX)
                        try withExtendedLifetime(repairing) { try manager.removeItem(at: entry) }
                    }
                    try compile(entry)
                }
                let lease = try ConfigFileLock(
                    entry.appendingPathComponent("lease"), operation: LOCK_SH)
                let usage = cache.appendingPathComponent("usage")
                try manager.createDirectory(at: usage, withIntermediateDirectories: true)
                try Data().write(to: usage.appendingPathComponent(key), options: .atomic)
                evict(protecting: key)
                return lease
            }
        }
        runDurations = []
        return try withExtendedLifetime(lease) {
            let records = requests.map {
                _EndpointsConfigTransport.Record(
                    target: $0.target, wire: $0.wireName, spec: $0.specName,
                    integer: $0.integerName,
                    operationID: $0.operationID, route: $0.route)
            }
            let request = Data(_EndpointsConfigTransport.request(records).utf8)
            let first = try execute(entry, requestBytes: request, count: requests.count)
            let second = try execute(entry, requestBytes: request, count: requests.count)
            guard first.bytes == second.bytes else {
                let differing = requests.indices.first { index in
                    first.configuration.names[index].map { Data($0.utf8) }
                        != second.configuration.names[index].map { Data($0.utf8) }
                }
                let detail = differing.map {
                    "first differing entry: " + targetSwift(requests[$0].target)
                } ?? "declarative configuration differs between runs"
                throw ConfigProgramFailure(diagnostics: [
                    "\(diagnosticPath):\(entryLine):\(entryColumn): error: "
                        + "configuration program is not deterministic: "
                        + "two runs produced different results",
                    "\(diagnosticPath):\(entryLine):\(entryColumn): note: " + detail,
                ] + compilerDiagnostics)
            }
            return first.configuration
        }
    }

    private struct Execution {
        let bytes: Data
        let configuration: EvaluatedSwiftConfiguration
    }

    private func execute(_ entry: URL, requestBytes: Data, count: Int) throws -> Execution {
        let manager = FileManager.default
        let run = try Self.temporary(cache.appendingPathComponent("runs"), prefix: stem)
        defer { try? manager.removeItem(at: run) }
        let request = run.appendingPathComponent("request.txt")
        let response = run.appendingPathComponent("response.txt")
        try requestBytes.write(to: request)
        let start = DispatchTime.now().uptimeNanoseconds
        let result = try runner.run(
            entry.appendingPathComponent("config"),
            arguments: ["resolve", request.path, response.path], directory: run,
            environment: ["SWIFT_DETERMINISTIC_HASHING": "1"], timeout: 60)
        runDurations.append(
            TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000)
        if result.timedOut || result.signalled || result.status != 0 {
            let reason =
                result.timedOut
                ? "timed out after 60 s"
                : result.signalled
                    ? "was terminated by signal \(result.status)"
                    : "exited with status \(result.status)"
            throw ConfigProgramFailure(
                diagnostics: [
                    "\(diagnosticPath):1:1: error: configuration program \(reason)"
                ] + compilerDiagnostics + stderrNotes(result.tail))
        }
        guard let data = try? Data(contentsOf: response) else {
            throw ConfigProgramFailure(diagnostics: [
                "\(diagnosticPath):1:1: error: configuration program did not write a response"
            ])
        }
        let text = String(decoding: data, as: UTF8.self)
        guard Array(text.utf8) == Array(data) else {
            throw ConfigProgramFailure(diagnostics: [
                "\(diagnosticPath):1:1: error: configuration response is not UTF-8"
            ])
        }
        do {
            let (json, names) = try _EndpointsConfigTransport.readResponse(
                text, count: count, fingerprint: fingerprint)
            return Execution(
                bytes: data,
                configuration: EvaluatedSwiftConfiguration(
                    declarativeJSON: Data(json.utf8), names: names))
        } catch {
            throw ConfigProgramFailure(diagnostics: [
                "\(diagnosticPath):1:1: error: invalid configuration response: \(error)"
            ])
        }
    }
}
#endif
