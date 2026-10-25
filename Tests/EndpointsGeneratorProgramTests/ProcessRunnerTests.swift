#if OpenAPIGenerator
import Foundation
import Testing
@testable import endpoints_generate

@Suite struct ProcessRunnerTests {
    @Test func processRunnerDoesNotHangOnLinux() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for iteration in 0..<50 {
            let result = try ConfigProcessRunner().run(
                URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf 'child output'; printf 'child error' >&2"],
                directory: root.appendingPathComponent(String(iteration)),
                environment: ["SWIFT_DETERMINISTIC_HASHING": "1"], timeout: 2)
            try #require(!result.timedOut, "Child completion hung on iteration \(iteration)")
            #expect(result.status == 0 && !result.signalled)
            #expect(result.text(result.stdout) == "child output")
            #expect(result.text(result.stderr) == "child error")
        }
    }
    @Test func childReceivesOnlyExplicitEnvironmentAndNullInput() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = ConfigProcessRunner()
        let environment = try runner.run(
            URL(fileURLWithPath: "/usr/bin/env"), arguments: [],
            directory: root.appendingPathComponent("environment"),
            environment: ["SWIFT_DETERMINISTIC_HASHING": "1"], timeout: 2)
        #expect(
            environment.status == 0
                && environment.text(environment.stdout) == "SWIFT_DETERMINISTIC_HASHING=1\n")
        let input = try runner.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c", "if read value; then exit 1; fi; printf '%s' \"$1\"", "child",
                "fixed argument",
            ], directory: root.appendingPathComponent("input"), environment: [:], timeout: 2)
        #expect(input.status == 0 && input.text(input.stdout) == "fixed argument")
    }
    @Test func timeoutKillsCompilerDescendants() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("surviving-descendant")
        let result = try ConfigProcessRunner().run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c", "(sleep 0.6; printf survived > \"$1\") & printf started; wait",
                "child", marker.path,
            ], directory: root.appendingPathComponent("run"), timeout: 0.2)
        try #require(result.text(result.stdout) == "started", "Child did not start its descendant")
        #expect(result.timedOut)
        Thread.sleep(forTimeInterval: 0.7)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }
    @Test func timeoutExitSignalAndBoundedStderr() throws {
        let root = try programScratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = ConfigProcessRunner()
        // Reuse host compiler/SDK discovery, without compiling or evaluating a config.
        let program = try ConfigProgram(
            path: configFile(root), stem: "Pets", swiftc: nil,
            cache: root.appendingPathComponent("cache"))
        let child = root.appendingPathComponent("signal-child")
        let source = Bundle.module.resourceURL!.appendingPathComponent(
            "Fixtures/ProcessRunner/SignalChild.swift")
        let compiled = try runner.run(
            program.compiler,
            arguments: ["-swift-version", "6", "-warnings-as-errors"] + program.sdkFlags
                + [source.path, "-o", child.path],
            directory: root.appendingPathComponent("compile"), timeout: 30)
        try #require(
            !compiled.timedOut && !compiled.signalled && compiled.status == 0,
            "Signal helper compilation failed: \(compiled.tail)")
        let exit = try runner.run(
            URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "printf 'failure' >&2; exit 7"],
            directory: root.appendingPathComponent("exit"), timeout: 2)
        #expect(exit.status == 7 && !exit.signalled && exit.tail == "failure")
        for status in [15, 143] {
            let normal = try runner.run(
                child, arguments: ["exit\(status)"],
                directory: root.appendingPathComponent("exit\(status)"),
                environment: [:], timeout: 2)
            #expect(!normal.timedOut && !normal.signalled && normal.status == Int32(status))
        }
        let signal = try runner.run(
            child, arguments: ["signal"],
            directory: root.appendingPathComponent("signal"), environment: [:], timeout: 2)
        #expect(!signal.timedOut && signal.signalled && signal.status == 15)
        let start = ContinuousClock.now
        let timeout = try runner.run(
            URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exec sleep 30"],
            directory: root.appendingPathComponent("timeout"), timeout: 0.05)
        #expect(timeout.timedOut && start.duration(to: .now) < .seconds(3))
        let data = String(repeating: "long line\n", count: 20_000)
        try Data(data.utf8).write(to: exit.stderr)
        #expect(exit.text(exit.stderr).utf8.count <= 65_536)
        #expect(exit.tail.split(separator: "\n").count == 20)
    }
}
#endif
