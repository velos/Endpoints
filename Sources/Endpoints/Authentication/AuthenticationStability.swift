import Foundation

#if DEBUG

/// Debug-only check that an endpoint's ``Endpoint/auth`` yields one shared instance.
///
/// Stateful methods such as ``JWTAuth`` keep their tokens and in-flight refresh on the
/// instance, so every request has to see the same one. `static let auth = JWTAuth(...)`
/// does that. A computed `static var auth: JWTAuth { JWTAuth(...) }` creates a new
/// actor on every access, which loses tokens and starts a separate refresh per request,
/// without any error.
///
/// This check catches that during development. It runs once per endpoint type and
/// isn't compiled into release builds.
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
            `static let` so every request shares one instance. A stateful authentication \
            method can't keep credentials or combine refreshes otherwise.
            """
        )
    }
}

#endif
