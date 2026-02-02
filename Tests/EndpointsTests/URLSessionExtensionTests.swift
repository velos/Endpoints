//
//  URLSessionExtensionTests.swift
//  EndpointsTests
//
//  Created by Zac White on 7/7/21.
//  Copyright © 2021 Velos Mobile LLC. All rights reserved.
//

import Testing
import Foundation
@testable import Endpoints

@Suite
struct URLSessionExtensionTests {
    @Test
    func taskCreationFailure() {
        #expect(throws: InvalidEndpoint.TaskError.self) {
            try URLSession.shared.endpointTask(
                with: InvalidEndpoint(parameterComponents: .init(nonEncodable: .value)),
                completion: { _ in }
            )
        }
    }

    #if canImport(Combine)
    @Test
    @available(iOS 15.0, *)
    func publisherCreationFailure() async {
        let values = URLSession.shared.endpointPublisher(
            with: InvalidEndpoint(parameterComponents: .init(nonEncodable: .value))
        ).values

        await #expect(throws: EndpointTaskError<InvalidEndpoint.ErrorResponse>.self) {
            for try await _ in values {

            }
        }
    }
    #endif
}
