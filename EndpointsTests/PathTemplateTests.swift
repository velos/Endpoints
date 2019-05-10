//
//  PathTemplateTests.swift
//  EndpointsTests
//
//  Created by Zac White on 2/6/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import XCTest
@testable import Endpoints

struct Test {
    let one: String
    let two: Int
}

class PathTemplateTests: XCTestCase {
    func testInterpolation() {
        let template1: PathTemplate<Test> = "/testing/\(\.one)\(\.two)"
        let path = template1.path(with: Test(one: "first", two: 2))
        XCTAssertEqual(path, "/testing/first/2")
    }
}
