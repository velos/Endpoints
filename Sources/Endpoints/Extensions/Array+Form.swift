//
//  File.swift
//  
//
//  Created by Zac White on 3/6/21.
//

import Foundation

extension Array where Element == URLQueryItem {

    /// Goes through each URLQueryItem element and joins them with a '&',
    /// suitable for putting into the httpBody of a request
    public var formString: String {
        return map { item in
            let name = item.name.pathSafe
            let value = item.value?.pathSafe ?? ""
            return "\(name)=\(value)"
        }.joined(separator: "&")
    }
}
