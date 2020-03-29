#if !os(watchOS)
import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(EndpointsTests.allTests),
        testCase(PathTemplateTests.allTests),
    ]
}
#endif
#endif
