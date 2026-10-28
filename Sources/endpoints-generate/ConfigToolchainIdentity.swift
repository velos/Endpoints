#if OpenAPIGenerator
import Foundation

/// Probe results are host bookkeeping, never generated text. Cache them separately
/// from executables so native Xcode's repeated phase does not launch three tools.
struct ConfigToolchainIdentity: Codable {
    let key: String
    let compilerVersion: String
    let sdkPath: String?
    let sdkBuild: String?

    private var usable: Bool {
        #if os(Linux)
        return sdkPath == nil && sdkBuild == nil
        #else
        return sdkPath.map { FileManager.default.fileExists(atPath: $0) } == true
            && sdkBuild?.isEmpty == false
        #endif
    }

    static func load(
        compiler: URL, cache: URL, developerDirectory: String?,
        command: (URL, [String], String) throws -> String
    ) throws -> Self {
        let manager = FileManager.default
        let resolved = compiler.resolvingSymlinksInPath()
        let attributes = try manager.attributesOfItem(atPath: resolved.path)
        let size = (attributes[.size] as? NSNumber)?.stringValue ?? ""
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        var components = [
            "identity-probes-1", compiler.path, resolved.path, size, String(modified.bitPattern),
            developerDirectory ?? "",
        ]
        #if !os(Linux)
        // Also notice xcode-select changes when DEVELOPER_DIR is absent.
        components.append(URL(fileURLWithPath: "/var/db/xcode_select_link")
            .resolvingSymlinksInPath().path)
        // An SDK can be updated independently of swiftc in the selected Xcode.
        if let toolchains = resolved.path.range(of: "/Toolchains/") {
            let directory = URL(fileURLWithPath: String(resolved.path[..<toolchains.lowerBound]))
                .appendingPathComponent("Platforms/MacOSX.platform/Developer/SDKs")
            let stamp = try? manager.attributesOfItem(atPath: directory.path)[.modificationDate]
            components.append(String(((stamp as? Date)?.timeIntervalSince1970 ?? 0).bitPattern))
            components.append(directory.appendingPathComponent("MacOSX.sdk")
                .resolvingSymlinksInPath().path)
        }
        #endif
        let key = ConfigProgram.identity(components.map { Data($0.utf8) })
        let lock = try ConfigFileLock(cache.appendingPathComponent("ToolchainIdentity.lock"))
        return try withExtendedLifetime(lock) {
            let file = cache.appendingPathComponent("ToolchainIdentity.json")
            if let data = try? Data(contentsOf: file),
                let cached = try? JSONDecoder().decode(Self.self, from: data), cached.key == key,
                cached.usable
            {
                return cached
            }
            let version = try command(compiler, ["--version"], "compiler-version")
            #if os(Linux)
            let sdk: String? = nil
            let build: String? = nil
            #else
            let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
            let sdk = try command(xcrun, ["--sdk", "macosx", "--show-sdk-path"], "host-sdk")
            let build = try command(
                xcrun, ["--sdk", "macosx", "--show-sdk-build-version"], "host-sdk-build")
            #endif
            let identity = Self(key: key, compilerVersion: version, sdkPath: sdk, sdkBuild: build)
            try JSONEncoder().encode(identity).write(to: file, options: .atomic)
            return identity
        }
    }
}
#endif
