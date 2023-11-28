//
//  EnvironmentType.swift
//  Endpoints
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol EnvironmentType {
    /// The baseUrl of the Environment
    var baseUrl: URL { get }
    /// Processes the built URLRequest right before sending in order to attach any Environment related authentication or data to the outbound request
    var requestProcessor: (URLRequest) -> URLRequest { get }
}

public extension EnvironmentType {
    var requestProcessor: (URLRequest) -> URLRequest { return { $0 } }
}
