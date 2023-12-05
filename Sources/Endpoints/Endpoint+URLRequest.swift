//
//  Endpoint+URLRequest.swift
//  Endpoints
//
//  Created by Zac White on 1/26/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension Endpoint {

    /// Generates a `URLRequest` given the associated request value.
    /// - Parameter environment: The environment in which to create the request
    /// - Throws: An ``EndpointError`` which describes the error filling in data to the associated ``Definition``.
    /// - Returns: A `URLRequest` ready for requesting with all values from `self` filled in according to the associated ``Endpoint``.
    public func urlRequest(in environment: EnvironmentType) throws -> URLRequest {

        var components = URLComponents()
        components.path = Self.definition.path.path(with: pathComponents)

        let urlQueryItems: [URLQueryItem] = try Self.definition.parameters.compactMap { item in

            let value: Any
            let name: String
            switch item {
            case .query(let queryName, let valuePath):
                value = parameterComponents[keyPath: valuePath]
                name = queryName
            case .queryValue(let queryName, let queryValue):
                value = queryValue
                name = queryName
            default:
                return nil
            }

            guard let queryValue = value as? ParameterRepresentable else {
                throw EndpointError.invalidQuery(named: name, type: type(of: value))
            }

            if let encodedValue = queryValue.parameterValue {
                return URLQueryItem(name: name, value: encodedValue)
            }

            return nil
        }

        let bodyFormItems: [URLQueryItem] = try Self.definition.parameters.compactMap { item in

            let value: Any
            let name: String
            switch item {
            case .form(let formName, let valuePath):
                value = parameterComponents[keyPath: valuePath]
                name = formName
            case .formValue(let formName, let formValue):
                value = formValue
                name = formName
            default:
                return nil
            }

            guard let formValue = value as? ParameterRepresentable else {
                throw EndpointError.invalidForm(named: name, type: type(of: value))
            }

            if let encodedValue = formValue.parameterValue {
                return URLQueryItem(name: name, value: encodedValue)
            }

            return nil
        }

        if !urlQueryItems.isEmpty {
            components.queryItems = urlQueryItems
        }

        let baseUrl = environment.baseUrl
        guard let url = components.url(relativeTo: baseUrl) else {
            throw EndpointError.invalid(components: components, relativeTo: baseUrl)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = Self.definition.method.methodString

        let headerItems: [String: String] = try Self.definition.headers.reduce(into: [:]) { allHeaders, field in
            let value: Any
            let name = field.key.name

            switch field.value {
            case .field(let valuePath):
                value = headerComponents[keyPath: valuePath]
            case .fieldValue(let fieldValue):
                value = fieldValue
            }

            guard let headerValue = value as? CustomStringConvertible else {
                throw EndpointError.invalidHeader(named: name, type: type(of: value))
            }

            allHeaders[name] = headerValue.description
        }

        for (name, value) in headerItems {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        urlRequest.url = url

        if !(body is EmptyCodable) {
            do {
                urlRequest.httpBody = try Self.bodyEncoder.encode(body)
            } catch {
                throw EndpointError.invalidBody(error)
            }

            if headerItems[Header.contentType.name] == nil {
                urlRequest.addValue("application/json", forHTTPHeaderField: Header.contentType.name)
            }
        } else if !bodyFormItems.isEmpty {
            urlRequest.httpBody = bodyFormItems.formString.data(using: .utf8)
            urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: Header.contentType.name)
        }

        urlRequest = environment.requestProcessor(urlRequest)

        return urlRequest
    }
}
