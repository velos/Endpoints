#if !os(watchOS)
import XCTest

import EndpointsTests

var tests = [XCTestCaseEntry]()
tests += EndpointsTests.allTests()
XCTMain(tests)
#endif
