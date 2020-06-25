//
//  Endpoint.swift
//  Headers
//
//  Created by Zac White on 6/25/20.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

public struct Headers: CustomStringConvertible, Hashable, ExpressibleByStringLiteral {
    public let value: String
    public let category: HeaderCategory
    public var description: String { value }

    public init(value: String, category: HeaderCategory = .general) {
        self.value = value
        self.category = category
    }

    public init(stringLiteral value: StringLiteralType) {
        self.value = value
        self.category = .general
    }
}

public enum HeaderCategory {
    case general
    case request
    case response
    case entity
}

extension Headers {

    // Request Headers
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec5.html#sec5.3
    public static let accept = Headers(value: "Accept", category: .request)
    public static let acceptCharset = Headers(value: "Accept-Charset", category: .request)
    public static let acceptEncoding = Headers(value: "Accept-Encoding", category: .request)
    public static let acceptLanguage = Headers(value: "Accept-Language", category: .request)
    public static let authorization = Headers(value: "Authorization", category: .request)
    public static let expect = Headers(value: "Expect", category: .request)
    public static let from = Headers(value: "From", category: .request)
    public static let host = Headers(value: "Host", category: .request)
    public static let ifMatch = Headers(value: "If-Match", category: .request)
    public static let ifModifiedSince = Headers(value: "If-Modified-Since", category: .request)
    public static let ifNoneMatch = Headers(value: "If-None-Match", category: .request)
    public static let ifRange = Headers(value: "If-Range", category: .request)
    public static let ifUnmodifiedSince = Headers(value: "If-Unmodified-Since", category: .request)
    public static let maxForwards = Headers(value: "Max-Forwards", category: .request)
    public static let proxyAuthorization = Headers(value: "Proxy-Authorization", category: .request)
    public static let range = Headers(value: "Range", category: .request)
    public static let referer = Headers(value: "Referer", category: .request)
    public static let te = Headers(value: "TE", category: .request)
    public static let userAgent = Headers(value: "User-Agent", category: .request)

    // Entity Headers
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec7.html#sec7.1
    public static let allow = Headers(value: "Allow", category: .entity)
    public static let contentEncoding = Headers(value: "Content-Encoding", category: .entity)
    public static let contentLanguage = Headers(value: "Content-Language", category: .entity)
    public static let contentLength = Headers(value: "Content-Length", category: .entity)
    public static let contentLocation = Headers(value: "Content-Location", category: .entity)
    public static let contentMD5 = Headers(value: "Content-MD5", category: .entity)
    public static let contentRange = Headers(value: "Content-Range", category: .entity)
    public static let contentType = Headers(value: "Content-Type", category: .entity)
    public static let expires = Headers(value: "Expires", category: .entity)
    public static let lastModified = Headers(value: "Last-Modified", category: .entity)

    // General Headers
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec4.html#sec4.5
    public static let cacheControl = Headers(value: "Cache-Control", category: .general)
    public static let connection = Headers(value: "Connection", category: .general)
    public static let date = Headers(value: "Date", category: .general)
    public static let pragma = Headers(value: "Pragma", category: .general)
    public static let trailer = Headers(value: "Trailer", category: .general)
    public static let transferEncoding = Headers(value: "Transfer-Encoding", category: .general)
    public static let upgrade = Headers(value: "Upgrade", category: .general)
    public static let via = Headers(value: "Via", category: .general)
    public static let warning = Headers(value: "Warning", category: .general)

    public static let keepAlive = Headers(value: "Keep-Alive", category: .general)
    public static let cookie = Headers(value: "Cookie", category: .general)
    public static let setCookie = Headers(value: "Set-Cookie", category: .general)
    public static let clearSiteData = Headers(value: "Clear-Site-Data", category: .general)

    // response
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec6.html#sec6.2
    public static let acceptRanges = Headers(value: "Accept-Ranges", category: .response)
    public static let age = Headers(value: "Age", category: .response)
    public static let eTag = Headers(value: "ETag", category: .response)
    public static let location = Headers(value: "Location", category: .response)
    public static let proxyAuthenticate = Headers(value: "Proxy-Authenticate", category: .response)
    public static let retryAfter = Headers(value: "Retry-After", category: .response)
    public static let server = Headers(value: "Server", category: .response)
    public static let vary = Headers(value: "Vary", category: .response)
    public static let wwwAuthenticate = Headers(value: "WWW-Authenticate", category: .response)
}
