import Testing
import Foundation
@testable import MonitorLizard

struct UpdateServiceTests {

    // MARK: isInformationalError

    @Test func noUpdateAvailableErrorIsInformational() {
        // Code 1001 = SUNoUpdateAvailableError. Sparkle already shows "You're up to date"
        // for this case, so we must not also show our own "Update Failed" alert.
        let error = NSError(domain: "SUSparkleErrorDomain", code: 1001)
        #expect(UpdateService.isInformationalError(error))
    }

    @Test func otherSparkleErrorCodesAreNotInformational() {
        // Any non-1001 code is a real failure and should surface an alert.
        for code in [1000, 1002, 1003, 2001, -1] {
            let error = NSError(domain: "SUSparkleErrorDomain", code: code)
            #expect(!UpdateService.isInformationalError(error), "code \(code) should not be informational")
        }
    }

    @Test func errorDomainDoesNotAffectFiltering() {
        // Filtering is keyed on code alone, not domain, since Sparkle may use
        // multiple domains across versions.
        let error = NSError(domain: "SomeOtherDomain", code: 1001)
        #expect(UpdateService.isInformationalError(error))
    }
}
