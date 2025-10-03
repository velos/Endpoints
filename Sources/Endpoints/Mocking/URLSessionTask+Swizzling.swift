//
//  URLSessionTask+Swizzling.swift
//  Endpoints
//
//  Created by Zac White on 12/4/24.
//

import Foundation

#if DEBUG
nonisolated(unsafe) private var resumeOverrideKey: UInt8 = 0
extension URLSessionTask {
    var resumeOverride: (() -> Void)? {
        get {
            return (objc_getAssociatedObject(self, &resumeOverrideKey) as? () -> Void) ?? nil
        }
        set {
            objc_setAssociatedObject(self, &resumeOverrideKey, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    static let classInit: Void = {
        guard let originalMethod = class_getInstanceMethod(URLSessionTask.self, #selector(resume)),
              let swizzledMethod = class_getInstanceMethod(URLSessionTask.self, #selector(swizzled_resume)) else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    @objc func swizzled_resume() {
        if let resumeOverride {
            resumeOverride()
        } else {
            swizzled_resume()
        }
    }
}
#endif
