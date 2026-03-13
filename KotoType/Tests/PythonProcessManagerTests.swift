import XCTest
@testable import KotoType

final class PythonProcessManagerTests: XCTestCase {
    func testResolveLaunchCommandPrefersBundledServer() throws {
        let scriptPath = "/tmp/koto-type/python/whisper_server.py"
        let runtime = makeRuntime(
            currentDirectoryPath: "/tmp/koto-type/KotoType",
            bundlePath: "/Applications/KotoType.app",
            bundleResourcePath: "/tmp/app/Resources",
            existingPaths: ["/tmp/app/Resources/whisper_server", scriptPath],
            uvPath: "/opt/homebrew/bin/uv"
        )

        let command = try XCTUnwrap(
            PythonProcessManager.resolveLaunchCommand(scriptPath: scriptPath, runtime: runtime)
        )

        XCTAssertEqual(command.executablePath, "/tmp/app/Resources/whisper_server")
        XCTAssertEqual(command.arguments, [])
        XCTAssertEqual(command.mode, "bundled-binary")
        XCTAssertEqual(command.workingDirectory, "/tmp/koto-type")
    }

    func testResolveLaunchCommandUsesUvRunWhenBundledMissing() throws {
        let scriptPath = "/tmp/koto-type/python/whisper_server.py"
        let runtime = makeRuntime(
            currentDirectoryPath: "/tmp/koto-type/KotoType",
            bundlePath: "/tmp/koto-type/.build/debug/KotoType",
            bundleResourcePath: "/tmp/app/Resources",
            existingPaths: [scriptPath],
            uvPath: "/usr/local/bin/uv"
        )

        let command = try XCTUnwrap(
            PythonProcessManager.resolveLaunchCommand(scriptPath: scriptPath, runtime: runtime)
        )

        XCTAssertEqual(command.executablePath, "/usr/local/bin/uv")
        XCTAssertEqual(command.arguments, ["run", "--project", "/tmp/koto-type", "python", scriptPath])
        XCTAssertEqual(command.mode, "uv-run")
        XCTAssertEqual(command.workingDirectory, "/tmp/koto-type")
    }

    func testResolveLaunchCommandFallsBackToVenvPythonWhenUvMissing() throws {
        let scriptPath = "/tmp/koto-type/python/whisper_server.py"
        let runtime = makeRuntime(
            currentDirectoryPath: "/tmp/koto-type/KotoType",
            bundlePath: "/tmp/koto-type/.build/debug/KotoType",
            bundleResourcePath: nil,
            existingPaths: [scriptPath, "/tmp/koto-type/.venv/bin/python"],
            uvPath: nil
        )

        let command = try XCTUnwrap(
            PythonProcessManager.resolveLaunchCommand(scriptPath: scriptPath, runtime: runtime)
        )

        XCTAssertEqual(command.executablePath, "/tmp/koto-type/.venv/bin/python")
        XCTAssertEqual(command.arguments, [scriptPath])
        XCTAssertEqual(command.mode, "venv-python")
        XCTAssertEqual(command.workingDirectory, "/tmp/koto-type")
    }

    func testResolveLaunchCommandReturnsNilWhenScriptMissing() {
        let runtime = makeRuntime(
            currentDirectoryPath: "/tmp/koto-type/KotoType",
            bundlePath: "/tmp/koto-type/.build/debug/KotoType",
            bundleResourcePath: nil,
            existingPaths: ["/tmp/koto-type/.venv/bin/python"],
            uvPath: "/opt/homebrew/bin/uv"
        )

        let command = PythonProcessManager.resolveLaunchCommand(
            scriptPath: "/tmp/koto-type/python/whisper_server.py",
            runtime: runtime
        )

        XCTAssertNil(command)
    }

    func testResolveLaunchCommandReturnsNilForAppBundleWhenBundledServerMissing() {
        let scriptPath = "/tmp/koto-type/python/whisper_server.py"
        let runtime = makeRuntime(
            currentDirectoryPath: "/tmp/koto-type/KotoType",
            bundlePath: "/Applications/KotoType.app",
            bundleResourcePath: "/Applications/KotoType.app/Contents/Resources",
            existingPaths: [scriptPath],
            uvPath: "/opt/homebrew/bin/uv"
        )

        let command = PythonProcessManager.resolveLaunchCommand(scriptPath: scriptPath, runtime: runtime)
        XCTAssertNil(command)
    }

    func testExtractOutputLinesHandlesChunkBoundaries() {
        var buffer = ""

        let lines1 = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "hel")
        XCTAssertTrue(lines1.isEmpty)
        XCTAssertEqual(buffer, "hel")

        let lines2 = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "lo\nwor")
        XCTAssertEqual(lines2, ["hello"])
        XCTAssertEqual(buffer, "wor")

        let lines3 = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "ld\n")
        XCTAssertEqual(lines3, ["world"])
        XCTAssertEqual(buffer, "")
    }

    func testExtractOutputLinesHandlesMultipleAndEmptyLines() {
        var buffer = ""

        let lines1 = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "one\ntwo\n\nthr")
        XCTAssertEqual(lines1, ["one", "two", ""])
        XCTAssertEqual(buffer, "thr")

        let lines2 = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "ee\r\n")
        XCTAssertEqual(lines2, ["three"])
        XCTAssertEqual(buffer, "")
    }

    func testExtractOutputLinesPreservesWhitespaceInsideLine() {
        var buffer = ""

        let lines = PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: "  padded text  \n")
        XCTAssertEqual(lines, ["  padded text  "])
        XCTAssertEqual(buffer, "")
    }

    func testRuntimeEnvironmentForAppBundleForcesBackendSafetyCaps() {
        let environment = PythonProcessManager.runtimeEnvironment(
            base: [
                "KOTOTYPE_MAX_ACTIVE_SERVERS": "8",
                "KOTOTYPE_MAX_PARALLEL_MODEL_LOADS": "4",
            ],
            bundlePath: "/Applications/KotoType.app"
        )

        XCTAssertEqual(environment["KOTOTYPE_MAX_ACTIVE_SERVERS"], "1")
        XCTAssertEqual(environment["KOTOTYPE_MAX_PARALLEL_MODEL_LOADS"], "1")
        XCTAssertEqual(environment["KOTOTYPE_MODEL_LOAD_WAIT_TIMEOUT_SECONDS"], "120")
    }

    func testRuntimeEnvironmentForDevelopmentKeepsExistingValues() {
        let environment = PythonProcessManager.runtimeEnvironment(
            base: [
                "KOTOTYPE_MAX_ACTIVE_SERVERS": "8",
                "KOTOTYPE_MAX_PARALLEL_MODEL_LOADS": "4",
            ],
            bundlePath: "/tmp/koto-type/.build/debug/KotoType"
        )

        XCTAssertEqual(environment["KOTOTYPE_MAX_ACTIVE_SERVERS"], "8")
        XCTAssertEqual(environment["KOTOTYPE_MAX_PARALLEL_MODEL_LOADS"], "4")
        XCTAssertNil(environment["KOTOTYPE_MODEL_LOAD_WAIT_TIMEOUT_SECONDS"])
    }

    func testRuntimeEnvironmentForAppBundlePrependsPackageManagerPaths() {
        let environment = PythonProcessManager.runtimeEnvironment(
            base: [
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            ],
            bundlePath: "/Applications/KotoType.app"
        )

        XCTAssertEqual(
            environment["PATH"],
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        )
    }

    func testMergedSearchPathAvoidsDuplicates() {
        let path = PythonProcessManager.mergedSearchPath(
            basePath: "/opt/homebrew/bin:/usr/bin:/bin",
            prepending: ["/opt/homebrew/bin", "/usr/local/bin"]
        )

        XCTAssertEqual(path, "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
    }

    func testDescendantProcessIdentifiersFindsRecursiveChildren() {
        let psOutput = """
        100 1
        101 100
        102 101
        103 100
        200 2
        """

        let descendants = PythonProcessManager.descendantProcessIdentifiers(
            rootPID: 100,
            psOutput: psOutput
        )

        XCTAssertEqual(Set(descendants), Set([101, 102, 103]))
    }

    func testDescendantProcessIdentifiersIgnoresMalformedRows() {
        let psOutput = """
        garbage
        100 1
        101 100
        bad 200
        102 101
        """

        let descendants = PythonProcessManager.descendantProcessIdentifiers(
            rootPID: 100,
            psOutput: psOutput
        )

        XCTAssertEqual(Set(descendants), Set([101, 102]))
    }

    private func makeRuntime(
        currentDirectoryPath: String,
        bundlePath: String,
        bundleResourcePath: String?,
        existingPaths: Set<String>,
        uvPath: String?
    ) -> PythonProcessManager.Runtime {
        PythonProcessManager.Runtime(
            currentDirectoryPath: { currentDirectoryPath },
            bundlePath: { bundlePath },
            bundleResourcePath: { bundleResourcePath },
            fileExists: { path in existingPaths.contains(path) },
            findExecutable: { name in
                guard name == "uv" else { return nil }
                return uvPath
            }
        )
    }
}
