import Foundation
import Testing
@testable import xcodecloud

struct BuildRunSummaryTests {
    @Test
    func runningStatusWinsWhenProgressRunning() {
        let status = BuildStatus.derive(executionProgress: "RUNNING", completionStatus: "FAILED")
        #expect(status == .running)
    }

    @Test
    func completionStatusMapsToFailed() {
        let status = BuildStatus.derive(executionProgress: "COMPLETE", completionStatus: "ERRORED")
        #expect(status == .failed)
    }

    @Test
    func issueCountsTotalSumsAllFields() {
        let counts = BuildIssueCounts(errors: 1, warnings: 2, testFailures: 3, analyzerWarnings: 4)
        #expect(counts.total == 10)
    }

    @Test
    func appSummaryDisplayNameContainsBundleID() {
        let app = ASCAppSummary(id: "1", name: "MyApp", bundleID: "com.example.app")
        #expect(app.displayName.contains("MyApp"))
        #expect(app.displayName.contains("com.example.app"))
    }
}
