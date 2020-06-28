//
//  Endpoint.swift
//  Headers
//
//  Created by Zac White on 6/25/20.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

/// An HTTP header name and category
public struct Headers: Hashable, ExpressibleByStringLiteral {

    /// The name of the header. Example: "Accept-Language"
    public let name: String

    /// The category of the header.
    /// See: https://www.w3.org/Protocols/rfc2616/rfc2616-sec4.html#sec4.2
    public let category: HeaderCategory

    /// Initializes a Headers instance with the name and a category.
    /// - Parameters:
    ///   - name: The name of the Header. Example: "Accept-Language"
    ///   - category: The category of the header. Defaults to `.general`
    public init(name: String, category: HeaderCategory = .general) {
        self.name = name
        self.category = category
    }

    /// Initializes a Headers instance with the name of the header as a string literal. The category defaults to `.general`
    /// - Parameter value: <#value description#>
    public init(stringLiteral value: StringLiteralType) {
        self.name = value
        self.category = .general
    }
}

/// The Header category.
/// See: https://www.w3.org/Protocols/rfc2616/rfc2616-sec4.html#sec4.2
public enum HeaderCategory {
    case general
    case request
    case response
    case entity
}

extension Headers {

    // Request Headers
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec5.html#sec5.3
    public static let accept = Headers(name: "Accept", category: .request)
    public static let acceptCharset = Headers(name: "Accept-Charset", category: .request)
    public static let acceptEncoding = Headers(name: "Accept-Encoding", category: .request)
    public static let acceptLanguage = Headers(name: "Accept-Language", category: .request)
    public static let authorization = Headers(name: "Authorization", category: .request)
    public static let expect = Headers(name: "Expect", category: .request)
    public static let from = Headers(name: "From", category: .request)
    public static let host = Headers(name: "Host", category: .request)
    public static let ifMatch = Headers(name: "If-Match", category: .request)
    public static let ifModifiedSince = Headers(name: "If-Modified-Since", category: .request)
    public static let ifNoneMatch = Headers(name: "If-None-Match", category: .request)
    public static let ifRange = Headers(name: "If-Range", category: .request)
    public static let ifUnmodifiedSince = Headers(name: "If-Unmodified-Since", category: .request)
    public static let maxForwards = Headers(name: "Max-Forwards", category: .request)
    public static let proxyAuthorization = Headers(name: "Proxy-Authorization", category: .request)
    public static let range = Headers(name: "Range", category: .request)
    public static let referer = Headers(name: "Referer", category: .request)
    public static let te = Headers(name: "TE", category: .request)
    public static let userAgent = Headers(name: "User-Agent", category: .request)

    // Entity Headers
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec7.html#sec7.1
    public static let allow = Headers(name: "Allow", category: .entity)
    public static let contentEncoding = Headers(name: "Content-Encoding", category: .entity)
    public static let contentLanguage = Headers(name: "Content-Language", category: .entity)
    public static let contentLength = Headers(name: "Content-Length", category: .entity)
    public static let contentLocation = Headers(name: "Content-Location", category: .entity)
    public static let contentMD5 = Headers(name: "Content-MD5", category: .entity)
    public static let contentRange = Headers(name: "Content-Range", category: .entity)
    public static let contentType = Headers(name: "Content-Type", category: .entity)
    public static let expires = Headers(name: "Expires", category: .entity)
    public static let lastModified = Headers(name: "Last-Modified", category: .entity)

    // General Headers
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec4.html#sec4.5
    public static let cacheControl = Headers(name: "Cache-Control", category: .general)
    public static let connection = Headers(name: "Connection", category: .general)
    public static let date = Headers(name: "Date", category: .general)
    public static let pragma = Headers(name: "Pragma", category: .general)
    public static let trailer = Headers(name: "Trailer", category: .general)
    public static let transferEncoding = Headers(name: "Transfer-Encoding", category: .general)
    public static let upgrade = Headers(name: "Upgrade", category: .general)
    public static let via = Headers(name: "Via", category: .general)
    public static let warning = Headers(name: "Warning", category: .general)

    public static let keepAlive = Headers(name: "Keep-Alive", category: .general)
    public static let cookie = Headers(name: "Cookie", category: .general)
    public static let setCookie = Headers(name: "Set-Cookie", category: .general)
    public static let clearSiteData = Headers(name: "Clear-Site-Data", category: .general)

    // response
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec6.html#sec6.2
    public static let acceptRanges = Headers(name: "Accept-Ranges", category: .response)
    public static let age = Headers(name: "Age", category: .response)
    public static let eTag = Headers(name: "ETag", category: .response)
    public static let location = Headers(name: "Location", category: .response)
    public static let proxyAuthenticate = Headers(name: "Proxy-Authenticate", category: .response)
    public static let retryAfter = Headers(name: "Retry-After", category: .response)
    public static let server = Headers(name: "Server", category: .response)
    public static let vary = Headers(name: "Vary", category: .response)
    public static let wwwAuthenticate = Headers(name: "WWW-Authenticate", category: .response)
}
