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
    let string: String
    let integer: Int
}

struct TestOptional {
    let string: String
    let integer: Int?
}

class PathTemplateTests: XCTestCase {

    func testStringInterpolation() {
        let template1: PathTemplate<Test> = "testing/\(path: \.string)/\(path: \.integer)/other"
        let path = template1.path(with: Test(string: "first", integer: 2))
        XCTAssertEqual(path, "testing/first/2/other")
    }

    func testStringConcatenation() {
        let template1: PathTemplate<Test> = "testing/" + \.string + \.integer
        let path1 = template1.path(with: Test(string: "first", integer: 2))
        XCTAssertEqual(path1, "testing/first/2")

        let template2: PathTemplate<Test> = \.integer + "testing"
        let path2 = template2.path(with: Test(string: "first", integer: 2))
        XCTAssertEqual(path2, "2/testing")

        let template3: PathTemplate<Test> = "testing" + 3
        let path3 = template3.path(with: Test(string: "first", integer: 2))
        XCTAssertEqual(path3, "testing/3")
    }

    func testNoSlash() {
        let template1: PathTemplate<Test> = "testing/testPath(Thing='\(path: \.string, includesSlash: false)')"
        let path1 = template1.path(with: Test(string: "first", integer: 2))
        XCTAssertEqual(path1, "testing/testPath(Thing='first')")

        let template2: PathTemplate<Test> = "testing/testPath(Thing='\(path: \.string, includesSlash: false)')\(path: \.integer)"
        let path2 = template2.path(with: Test(string: "first", integer: 2))
        XCTAssertEqual(path2, "testing/testPath(Thing='first')/2")

        let template3: PathTemplate<TestOptional> = "testing/testPath(Thing='\(path: \.string, includesSlash: false)')\(path: \.integer)"
        let path3 = template3.path(with: TestOptional(string: "first", integer: nil))
        XCTAssertEqual(path3, "testing/testPath(Thing='first')")
    }

    func testStringLiteral() {
        let template: PathTemplate<Test> = "testing"
        let path = template.path(with: Test(string: "first", integer: 2))
        XCTAssertEqual(path, "testing")
    }

    static var allTests = [
        ("testStringInterpolation", testStringInterpolation),
        ("testStringConcatenation", testStringConcatenation),
        ("testNoSlash", testNoSlash),
        ("testStringLiteral", testStringLiteral)
    ]
}
