//
//  URLSessionTask+Swizzling.swift
//  Endpoints
//
//  Created by Zac White on 12/4/24.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if DEBUG && (os(macOS) || os(iOS) || os(tvOS) || os(watchOS))
/// Storage key for the resume override closure.
nonisolated(unsafe) private var resumeOverrideKey: UInt8 = 0

extension URLSessionTask {
    /// A closure that overrides the default resume behavior.
    /// When set, this closure is called instead of the actual network request.
    var resumeOverride: (() -> Void)? {
        get {
            return (objc_getAssociatedObject(self, &resumeOverrideKey) as? () -> Void) ?? nil
        }
        set {
            objc_setAssociatedObject(self, &resumeOverrideKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    /// One-time initialization that swizzles the resume method.
    /// This is called automatically when the mocking system is first used.
    static let classInit: Void = {
        guard let originalMethod = class_getInstanceMethod(URLSessionTask.self, #selector(resume)),
              let swizzledMethod = class_getInstanceMethod(URLSessionTask.self, #selector(swizzled_resume)) else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    /// The swizzled implementation of resume that checks for an override.
    @objc func swizzled_resume() {
        if let resumeOverride {
            resumeOverride()
        } else {
            swizzled_resume()
        }
    }
}
#endif
