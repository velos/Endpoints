#if OpenAPIGenerator
import EndpointsGeneratorConfig
import Foundation

public enum ServerURLs {
    /// Validate with Foundation, but preserve the input's spelling and escapes.
    public static func normalize(_ input: String) throws -> String {
        guard let components = URLComponents(string: input),
            let scheme = components.scheme, ["http", "https"].contains(Naming.asciiLower(scheme)),
            let host = components.host, !host.isEmpty, components.query == nil,
            components.fragment == nil,
            !input.unicodeScalars.contains(where: {
                $0.value <= UInt32(UInt8(ascii: " ")) || $0.value == 0x7f
            }),
            !input.contains("{"), !input.contains("}")
        else {
            throw NameError(
                "Invalid server URL; expected an absolute HTTP(S) URL without query or fragment"
            )
        }
        // Reject malformed percent escapes instead of relying on OS-specific repair.
        let bytes = Array(input.utf8)
        func isHexDigit(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
        for index in bytes.indices where bytes[index] == UInt8(ascii: "%") {
            guard index + 2 < bytes.count, isHexDigit(bytes[index + 1]),
                isHexDigit(bytes[index + 2])
            else {
                throw NameError("Invalid percent escape in server URL")
            }
        }
        return !components.path.isEmpty && !input.hasSuffix("/") ? input + "/" : input
    }
}
#endif
