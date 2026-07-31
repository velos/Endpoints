//
//  Server.swift
//  Endpoints
//
//  Created by Zac White on 11/27/24.
//

import Foundation

// The environment a request is built against is supplied per request — see
// ``Endpoint/urlRequest(in:)`` and the `environment:` parameter on the `URLSession`
// request methods — rather than stored in process-wide mutable state. That is what
// lets two clients talk to different environments at the same time.
//
// ``ServerDefinition/defaultEnvironment`` provides the default for those parameters.
