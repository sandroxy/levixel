import XCTest
import integration_test

final class RunnerTests: XCTestCase {
    func testFlutterSessions() {
        var resultCount = 0
        FLTIntegrationTestRunner().testIntegrationTest { selector, success, message in
            resultCount += 1
            XCTAssertTrue(success, message ?? NSStringFromSelector(selector))
        }
        XCTAssertGreaterThan(resultCount, 0, "The native runner must receive Dart test results")
    }
}
