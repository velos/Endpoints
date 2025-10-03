import Foundation

public func wait<R: Sendable>(_ body: (CheckedContinuation<R, any Error>) throws -> Void) async throws -> R {
    return try await withCheckedThrowingContinuation { continuation in
        do {
            try body(continuation)
        } catch {
            continuation.resume(throwing: error)
        }
    }
}
