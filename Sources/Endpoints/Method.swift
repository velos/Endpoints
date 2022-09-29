//
//  File.swift
//  
//
//  Created by Zac White on 3/6/21.
//

import Foundation

/// The HTTP Method
public enum Method {
    case options
    case get
    case head
    case post
    case put
    case patch
    case delete
    case trace
    case connect

    public var methodString: String {
        switch self {
        case .options: return "OPTIONS"
        case .get: return "GET"
        case .head: return "HEAD"
        case .post: return "POST"
        case .put: return "PUT"
        case .patch: return "PATCH"
        case .delete: return "DELETE"
        case .trace: return "TRACE"
        case .connect: return "CONNECT"
        }
    }
}
