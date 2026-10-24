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

    @Test(arguments: [
        (nil, "testing/first.test"),
        (Optional(2), "testing/first.test/2")
    ])
    func embeddedValuePreservesLiteralSlash(integer: Int?, expected: String) {
        let template: PathTemplate<TestOptional> = "testing/\(path: \.string, includesSlash: false).test\(path: \.integer)"
        #expect(template.path(with: TestOptional(string: "first", integer: integer)) == expected)
    }

    @Test
    func embeddedValues() {
        let value = Test(string: "first", integer: 42)
        let embedded: PathTemplate<Test> = "files/\(path: \.integer, includesSlash: false).json"
        #expect(embedded.path(with: value) == "files/42.json")

        let surrounded: PathTemplate<Test> = "a/\(path: \.string, includesSlash: false)-\(path: \.integer, includesSlash: false).json"
        #expect(surrounded.path(with: Test(string: "first", integer: 2)) == "a/first-2.json")

        let segment: PathTemplate<Test> = "files/\(path: \.integer).json"
        #expect(segment.path(with: value) == "files/42/.json")
    }

    @Test
    func adjacentInterpolations() {
        let value = Test(string: "first", integer: 2)
        let segments: PathTemplate<Test> = "\(path: \.string)\(path: \.integer)"
        #expect(segments.path(with: value) == "first/2")

        let embedded: PathTemplate<Test> = "\(path: \.string)\(path: \.integer, includesSlash: false)"
        #expect(embedded.path(with: value) == "first2")
    }

    @Test
    func nilEmbeddedValues() {
        let value = TestOptional(string: "first", integer: nil)
        let cases: [(PathTemplate<TestOptional>, String)] = [
            ("\(path: \.integer, includesSlash: false)/tail", "/tail"),
            ("head/\(path: \.integer, includesSlash: false)/tail", "head/tail"),
            ("head/\(path: \.integer, includesSlash: false)", "head"),
            ("\(path: \.string)\(path: \.integer, includesSlash: false)", "first"),
            ("\(path: \.integer, includesSlash: false)\(path: \.string)", "first"),
            ("\(path: \.integer, includesSlash: false)", "")
        ]

        for (template, expected) in cases {
            #expect(template.path(with: value) == expected)
        }
    }

    @Test(arguments: ["testing", "testing/"])
    func compositionSeparators(prefix: String) {
        let template: PathTemplate<Test> = prefix + \.string + ".json"
        #expect(template.path(with: Test(string: "first", integer: 2)) == "testing/first/.json")
    }

    @Test
    func stringLiteral() {
        let template: PathTemplate<Test> = "testing"
        let path = template.path(with: Test(string: "first", integer: 2))
        #expect(path == "testing")
    }
}
