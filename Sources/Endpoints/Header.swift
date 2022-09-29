//
//  Header.swift
//  Endpoints
//
//  Created by Zac White on 6/25/20.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

/// An HTTP header name and category
public struct Header: Hashable, ExpressibleByStringLiteral {

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

extension Header {

    // Request Headers
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec5.html#sec5.3

    /// See [Accept](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept) header documentation.
    public static let accept = Header(name: "Accept", category: .request)
    public static let acceptCharset = Header(name: "Accept-Charset", category: .request)
    public static let acceptEncoding = Header(name: "Accept-Encoding", category: .request)
    public static let acceptLanguage = Header(name: "Accept-Language", category: .request)
    public static let authorization = Header(name: "Authorization", category: .request)
    public static let expect = Header(name: "Expect", category: .request)
    public static let from = Header(name: "From", category: .request)
    public static let host = Header(name: "Host", category: .request)
    public static let ifMatch = Header(name: "If-Match", category: .request)
    public static let ifModifiedSince = Header(name: "If-Modified-Since", category: .request)
    public static let ifNoneMatch = Header(name: "If-None-Match", category: .request)
    public static let ifRange = Header(name: "If-Range", category: .request)
    public static let ifUnmodifiedSince = Header(name: "If-Unmodified-Since", category: .request)
    public static let maxForwards = Header(name: "Max-Forwards", category: .request)
    public static let proxyAuthorization = Header(name: "Proxy-Authorization", category: .request)
    public static let range = Header(name: "Range", category: .request)
    public static let referer = Header(name: "Referer", category: .request)
    public static let te = Header(name: "TE", category: .request)
    public static let userAgent = Header(name: "User-Agent", category: .request)

    // Entity Headers
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec7.html#sec7.1
    public static let allow = Header(name: "Allow", category: .entity)
    public static let contentEncoding = Header(name: "Content-Encoding", category: .entity)
    public static let contentLanguage = Header(name: "Content-Language", category: .entity)
    public static let contentLength = Header(name: "Content-Length", category: .entity)
    public static let contentLocation = Header(name: "Content-Location", category: .entity)
    public static let contentMD5 = Header(name: "Content-MD5", category: .entity)
    public static let contentRange = Header(name: "Content-Range", category: .entity)
    public static let contentType = Header(name: "Content-Type", category: .entity)
    public static let expires = Header(name: "Expires", category: .entity)
    public static let lastModified = Header(name: "Last-Modified", category: .entity)

    // General Headers
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec4.html#sec4.5
    public static let cacheControl = Header(name: "Cache-Control", category: .general)
    public static let connection = Header(name: "Connection", category: .general)
    public static let date = Header(name: "Date", category: .general)
    public static let pragma = Header(name: "Pragma", category: .general)
    public static let trailer = Header(name: "Trailer", category: .general)
    public static let transferEncoding = Header(name: "Transfer-Encoding", category: .general)
    public static let upgrade = Header(name: "Upgrade", category: .general)
    public static let via = Header(name: "Via", category: .general)
    public static let warning = Header(name: "Warning", category: .general)

    public static let keepAlive = Header(name: "Keep-Alive", category: .general)
    public static let cookie = Header(name: "Cookie", category: .general)
    public static let setCookie = Header(name: "Set-Cookie", category: .general)
    public static let clearSiteData = Header(name: "Clear-Site-Data", category: .general)

    // response
    // https://www.w3.org/Protocols/rfc2616/rfc2616-sec6.html#sec6.2
    public static let acceptRanges = Header(name: "Accept-Ranges", category: .response)
    public static let age = Header(name: "Age", category: .response)
    public static let eTag = Header(name: "ETag", category: .response)
    public static let location = Header(name: "Location", category: .response)
    public static let proxyAuthenticate = Header(name: "Proxy-Authenticate", category: .response)
    public static let retryAfter = Header(name: "Retry-After", category: .response)
    public static let server = Header(name: "Server", category: .response)
    public static let vary = Header(name: "Vary", category: .response)
    public static let wwwAuthenticate = Header(name: "WWW-Authenticate", category: .response)
}
