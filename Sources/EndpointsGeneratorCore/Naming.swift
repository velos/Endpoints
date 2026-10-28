#if OpenAPIGenerator
import Foundation
import EndpointsGeneratorConfig

public typealias AccessLevel = EndpointsGeneratorConfig.AccessLevel
typealias HTTPMethod = EndpointsGeneratorConfig.HTTPMethod

extension AccessLevel {
    var prefix: String { self == .internal ? "" : rawValue + " " }
}

struct NameAllocation {
    let name: String
    let original: String
    let hint: String
    let target: NameTarget?
    let pointer: String?
    init(
        name: String, original: String, hint: String, target: NameTarget? = nil,
        pointer: String? = nil
    ) {
        self.name = name
        self.original = original
        self.hint = hint
        self.target = target
        self.pointer = pointer
    }
}

struct NameAllocator {
    let reserved: Set<String>
    private struct AllocatedName {
        let swift: String
        let original: String
        let hint: String
    }
    private var used: [AllocatedName] = []
    let candidates: [NameAllocation]
    init(reserved: Set<String>, candidates: [NameAllocation] = []) {
        self.reserved = reserved
        self.candidates = candidates
    }
    mutating func claim(_ name: String, original: String, hint: String, target: NameTarget? = nil)
        throws
    {
        let bare = name.replacingOccurrences(of: "`", with: "")
        func failure(_ message: String) -> any Error {
            if let target, let pointer = candidates.first(where: { $0.target == target })?.pointer {
                return NameResolutionFailure(message: message, pointer: pointer)
            }
            return NameError(message)
        }
        guard !reserved.contains(bare) else {
            throw failure("Reserved name '\(bare)' for '\(original)'; use \(hint)")
        }
        if used.contains(where: { $0.swift == bare }) {
            let group = candidates.filter {
                $0.name.replacingOccurrences(of: "`", with: "") == bare
            }
            let details: String
            if group.count > 1 {
                details = group.map { "'" + $0.original + "' (" + $0.hint + ")" }.joined(
                    separator: " and ")
            } else {
                details =
                    (used.filter { $0.swift == bare }.map {
                        "'" + $0.original + "' (" + $0.hint + ")"
                    }
                    + ["'" + original + "' (" + hint + ")"]).joined(separator: " and ")
            }
            throw failure("Name collision '\(bare)' between " + details)
        }
        used.append(AllocatedName(swift: bare, original: original, hint: hint))
    }
}
#endif
