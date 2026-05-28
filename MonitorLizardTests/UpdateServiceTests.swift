import Testing
import Foundation
@testable import MonitorLizard

struct UpdateServiceTests {

    // MARK: isInformationalError

    @Test(arguments: [
        ("SUSparkleErrorDomain", 1001),
        ("SomeOtherDomain", 1001),
    ] as [(String, Int)])
    func code1001IsInformational(domain: String, code: Int) {
        // Code 1001 = SUNoUpdateAvailableError. Sparkle already shows "You're up to date"
        // for this case, so we must not also show our own "Update Failed" alert.
        let error = NSError(domain: domain, code: code)
        #expect(UpdateService.isInformationalError(error))
    }

    @Test(arguments: [1000, 1002, 1003, 2001, -1])
    func otherSparkleErrorCodesAreNotInformational(code: Int) {
        // Any non-1001 code is a real failure and should surface an alert.
        let error = NSError(domain: "SUSparkleErrorDomain", code: code)
        #expect(!UpdateService.isInformationalError(error), "code \(code) should not be informational")
    }
}
