//
//  URLSessionExtensionTests.swift
//  EndpointsTests
//
//  Created by Zac White on 7/7/21.
//  Copyright © 2021 Velos Mobile LLC. All rights reserved.
//

import XCTest
import Combine
@testable import Endpoints

class URLSessionExtensionTests: XCTestCase {

    var cancellables: Set<AnyCancellable> = Set()

    func testTaskCreationFailure() {
        XCTAssertThrowsError(
            try URLSession.shared.endpointTask(
                with: InvalidEndpoint(parameterComponents: .init(nonEncodable: .value)),
                completion: { _ in }
            )
        ) { error in
            XCTAssertTrue(error is InvalidEndpoint.TaskError, "error is \(type(of: error)) and not an EndpointTaskError")
        }
    }

    @MainActor
    func testPublisherCreationFailure() {
        let publisherExpectation = expectation(description: "publisher creation failure")
        URLSession.shared.endpointPublisher(
            with: InvalidEndpoint(parameterComponents: .init(nonEncodable: .value))
        )
        .sink { completion in
            guard case .failure(let error) = completion, case .endpointError = error else {
                return
            }

            publisherExpectation.fulfill()
        } receiveValue: { _ in
            XCTFail()
        }
        .store(in: &cancellables)

        waitForExpectations(timeout: 1)
    }
}
