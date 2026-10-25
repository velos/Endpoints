//
//  Array+Form.swift
//  Endpoints
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

extension Array where Element == URLQueryItem {

    /// Goes through each URLQueryItem element and joins them with a '&',
    /// suitable for putting into the httpBody of a request
    var formString: String {
        return map { item in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            let value = item.value?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
            return "\(name)=\(value)"
        }.joined(separator: "&")
    }
}
