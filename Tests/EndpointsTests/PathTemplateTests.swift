//
//  PathTemplateTests.swift
//  EndpointsTests
//
//  Created by Zac White on 2/6/19.
//  Copyright © 2019 Velos Mobile LLC. All rights reserved.
//

import Testing
@testable import Endpoints

struct Test {
    let string: String
    let integer: Int
}

struct TestOptional {
    let string: String
    let integer: Int?
}

@Suite
struct PathTemplateTests {

    @Test
    func stringInterpolation() {
        let template1: PathTemplate<Test> = "testing/\(path: \.string)/\(path: \.integer)/other"
        let path = template1.path(with: Test(string: "first", integer: 2))
        #expect(path == "testing/first/2/other")
    }

    @Test
    func stringConcatenation() {
        let template1: PathTemplate<Test> = "testing/" + \.string + \.integer
        let path1 = template1.path(with: Test(string: "first", integer: 2))
        #expect(path1 == "testing/first/2")

        let template2: PathTemplate<Test> = \.integer + "testing"
        let path2 = template2.path(with: Test(string: "first", integer: 2))
        #expect(path2 == "2/testing")

        let template3: PathTemplate<Test> = "testing" + 3
        let path3 = template3.path(with: Test(string: "first", integer: 2))
        #expect(path3 == "testing/3")
    }

    @Test
    func noSlash() {
        let template1: PathTemplate<Test> = "testing/testPath(Thing='\(path: \.string, includesSlash: false)')"
        let path1 = template1.path(with: Test(string: "first", integer: 2))
        #expect(path1 == "testing/testPath(Thing='first')")

        let template2: PathTemplate<Test> = "testing/testPath(Thing='\(path: \.string, includesSlash: false)')\(path: \.integer)"
        let path2 = template2.path(with: Test(string: "first", integer: 2))
        #expect(path2 == "testing/testPath(Thing='first')/2")

        let template3: PathTemplate<TestOptional> = "testing/testPath(Thing='\(path: \.string, includesSlash: false)')\(path: \.integer)"
        let path3 = template3.path(with: TestOptional(string: "first", integer: nil))
        #expect(path3 == "testing/testPath(Thing='first')")
    }

    @Test
    func stringLiteral() {
        let template: PathTemplate<Test> = "testing"
        let path = template.path(with: Test(string: "first", integer: 2))
        #expect(path == "testing")
    }
}
