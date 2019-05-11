//
//  URLSession+Endpoints.swift
//  Endpoints
//
//  Created by Zac White on 5/11/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

extension URLSession {
    func task<T: RequestType>(in environment: EnvironmentType, for endpoint: Endpoint<T>, with request: T, completion: @escaping (Result<T.Response, Error>) -> Void) throws -> URLSessionDataTask {

        let urlRequest = try endpoint.request(in: environment, for: request)

        return dataTask(with: urlRequest, completionHandler: { (data, response, error) in
            if let error = error {
                completion(.failure(error))
            } else if let data = data {
                let decoded: T.Response
                do {
                    decoded = try T.decode(data: data)
                } catch {
                    completion(.failure(error))
                    return
                }

                completion(.success(decoded))
            }
        })
    }
}
