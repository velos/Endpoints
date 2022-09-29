//
//  File.swift
//  
//
//  Created by Zac White on 3/6/21.
//

import Foundation

public protocol EnvironmentType {
    /// The baseUrl of the Environment
    var baseUrl: URL { get }
    /// Processes the built URLRequest right before sending in order to attach any Environment related authentication or data to the outbound request
    var requestProcessor: (URLRequest) -> URLRequest { get }
}

public extension EnvironmentType {
    var requestProcessor: (URLRequest) -> URLRequest { return { $0 } }
}
