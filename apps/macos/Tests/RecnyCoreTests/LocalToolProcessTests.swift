import Foundation
import Testing
@testable import RecnyCore

struct LocalToolProcessTests {
    @Test func inheritedContinuousOutputCannotHoldExitedParentOpen() async throws {
        let started = ContinuousClock.now
        do {
            _ = try await LocalToolProcess.run(executable: URL(fileURLWithPath: "/usr/bin/perl"), arguments: ["-e", "use Time::HiRes qw(usleep); $|=1; if(fork()==0) { for(1..300) { print 'x'; usleep(10000); } } exit 0;"], timeout: 0.5)
            Issue.record("Expected bounded inherited pipe timeout")
        } catch let error as LocalToolError { #expect(error == .timedOut) }
        #expect(started.duration(to: .now) < .seconds(2))
    }
    @Test func largeOutputDoesNotDeadlock() async throws {
        let result = try await LocalToolProcess.run(executable: URL(fileURLWithPath: "/usr/bin/perl"), arguments: ["-e", "print 'x' x 200000"], timeout: 10)
        #expect(result.count == 200000)
    }
    @Test func cancelsRunningHelperPromptly() async throws {
        let task = Task { try await LocalToolProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 60) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
    }
    @Test func timeoutProducesSanitizedError() async throws {
        do {
            _ = try await LocalToolProcess.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 0.1)
            Issue.record("Expected timeout")
        } catch let error as LocalToolError { #expect(error == .timedOut) }
    }
    @Test func noisyHelperIsStoppedBeforeTimeout() async throws {
        do {
            _ = try await LocalToolProcess.run(executable: URL(fileURLWithPath: "/usr/bin/perl"), arguments: ["-e", "use Time::HiRes qw(usleep); while(1) { print 'x' x 65536; usleep(1000); }"], timeout: 2)
            Issue.record("Expected output limit")
        } catch let error as LocalToolError { #expect(error == .outputTooLarge) }
    }
    @Test func failedHelperDoesNotExposeContent() async throws {
        do {
            _ = try await LocalToolProcess.run(executable: URL(fileURLWithPath: "/usr/bin/perl"), arguments: ["-e", "print STDERR 'private transcript'; exit 7"], timeout: 10)
            Issue.record("Expected failure")
        } catch let error as LocalToolError { #expect(error == .failed(7)); #expect(!error.localizedDescription.contains("private")) }
    }
}
