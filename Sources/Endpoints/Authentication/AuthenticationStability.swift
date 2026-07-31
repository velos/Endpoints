import Foundation

#if DEBUG

/// Debug-only check that an endpoint's ``Endpoint/auth`` yields one shared instance.
///
/// Stateful methods such as ``JWTAuth`` keep their tokens and in-flight refresh on the
/// instance, so they only work when every request sees the *same* one. Declaring
/// `static let auth = JWTAuth(...)` does that; a computed `static var auth: JWTAuth
/// { JWTAuth(...) }` silently hands out a fresh actor per access, which loses tokens
/// and turns refresh coalescing into a refresh storm — with no error to point at.
///
/// This catches that during development. It runs once per endpoint type and compiles
/// out of release builds entirely.
enum AuthenticationStability {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var verified: Set<ObjectIdentifier> = []

    static func verifySharedInstance<T: Endpoint>(for endpointType: T.Type) {
        // Value-type methods are stateless in practice, so a fresh copy is harmless.
        guard T.Auth.self is AnyObject.Type else { return }

        let key = ObjectIdentifier(T.self)

        lock.lock()
        let alreadyVerified = verified.contains(key)
        if !alreadyVerified {
            verified.insert(key)
        }
        lock.unlock()

        guard !alreadyVerified else { return }

        let first = T.auth as AnyObject
        let second = T.auth as AnyObject

        assert(
            first === second,
            """
            \(T.self).auth returns a new \(T.Auth.self) on each access. Declare it as a \
            `static let` so every request shares one instance — a stateful authentication \
            method cannot retain credentials or coalesce refreshes otherwise.
            """
        )
    }
}

#endif
