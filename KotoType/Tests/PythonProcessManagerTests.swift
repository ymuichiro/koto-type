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
        var buffer = Data()

        let lines1 = PythonProcessManager.extractOutputLines(
            buffer: &buffer,
            chunk: Data("hel".utf8)
        )
        XCTAssertTrue(lines1.isEmpty)
        XCTAssertEqual(buffer, Data("hel".utf8))

        let lines2 = PythonProcessManager.extractOutputLines(
            buffer: &buffer,
            chunk: Data("lo\nwor".utf8)
        )
        XCTAssertEqual(lines2, ["hello"])
        XCTAssertEqual(buffer, Data("wor".utf8))

        let lines3 = PythonProcessManager.extractOutputLines(
            buffer: &buffer,
            chunk: Data("ld\n".utf8)
        )
        XCTAssertEqual(lines3, ["world"])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testExtractOutputLinesHandlesMultipleAndEmptyLines() {
        var buffer = Data()

        let lines1 = PythonProcessManager.extractOutputLines(
            buffer: &buffer,
            chunk: Data("one\ntwo\n\nthr".utf8)
        )
        XCTAssertEqual(lines1, ["one", "two", ""])
        XCTAssertEqual(buffer, Data("thr".utf8))

        let lines2 = PythonProcessManager.extractOutputLines(
            buffer: &buffer,
            chunk: Data("ee\r\n".utf8)
        )
        XCTAssertEqual(lines2, ["three"])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testExtractOutputLinesPreservesWhitespaceInsideLine() {
        var buffer = Data()

        let lines = PythonProcessManager.extractOutputLines(
            buffer: &buffer,
            chunk: Data("  padded text  \n".utf8)
        )
        XCTAssertEqual(lines, ["  padded text  "])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testExtractOutputLinesPreservesUTF8WhenReadSplitsCharacter() {
        var buffer = Data()
        let payload = Data("日本語の文字起こしです。\n".utf8)

        let firstPart = Data(payload.prefix(2))
        let secondPart = Data(payload.dropFirst(2))

        XCTAssertTrue(
            PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: firstPart).isEmpty
        )
        XCTAssertEqual(
            PythonProcessManager.extractOutputLines(buffer: &buffer, chunk: secondPart),
            ["日本語の文字起こしです。"]
        )
        XCTAssertTrue(buffer.isEmpty)
    }

    func testTerminationCallbackOnlyHandlesCurrentProcess() {
        let activeProcess = Process()
        let staleProcess = Process()

        XCTAssertTrue(
            PythonProcessManager.shouldHandleTermination(
                activeProcess: activeProcess,
                terminatedProcess: activeProcess
            )
        )
        XCTAssertFalse(
            PythonProcessManager.shouldHandleTermination(
                activeProcess: activeProcess,
                terminatedProcess: staleProcess
            )
        )
        XCTAssertFalse(
            PythonProcessManager.shouldHandleTermination(
                activeProcess: nil,
                terminatedProcess: staleProcess
            )
        )
    }

    func testParseBackendStatusDecodesControlMessage() {
        let output =
            PythonProcessManager.controlMessagePrefix
            + "{\"effectiveBackend\":\"mlx\",\"gpuRequested\":true,\"gpuAvailable\":true}"

        let status = PythonProcessManager.parseBackendStatus(from: output)

        XCTAssertEqual(status?.effectiveBackend, .mlx)
        XCTAssertEqual(status?.gpuRequested, true)
        XCTAssertEqual(status?.gpuAvailable, true)
        XCTAssertNil(status?.fallbackReason)
    }

    func testParseBackendStatusReturnsNilForTranscriptOutput() {
        XCTAssertNil(PythonProcessManager.parseBackendStatus(from: "hello world"))
    }

    func testParseBackendProcessGroupIDAcceptsOnlyValidatedHandshake() {
        let prefix = PythonProcessManager.controlMessagePrefix
        XCTAssertEqual(
            PythonProcessManager.parseBackendProcessGroupID(
                from: prefix + "{\"type\":\"backend_process_group_ready\",\"process_id\":12,\"process_group_id\":34}"
            ),
            34
        )
        XCTAssertNil(
            PythonProcessManager.parseBackendProcessGroupID(
                from: prefix + "{\"type\":\"backend_process_group_ready\",\"process_id\":0,\"process_group_id\":34}"
            )
        )
        XCTAssertNil(PythonProcessManager.parseBackendProcessGroupID(from: "transcript"))
    }

    func testParseBackendPreparationProgressDecodesControlMessage() {
        let output =
            PythonProcessManager.controlMessagePrefix
            + "{\"type\":\"backend_preparation_progress\",\"step\":\"downloading_mlx_model\",\"detail\":\"Downloading the Apple GPU transcription model.\"}"

        let progress = PythonProcessManager.parseBackendPreparationProgress(from: output)

        XCTAssertEqual(progress?.type, "backend_preparation_progress")
        XCTAssertEqual(progress?.step, .downloadingMLXModel)
        XCTAssertEqual(progress?.detail, "Downloading the Apple GPU transcription model.")
    }

    func testParseBackendPreparationProgressDecodesMLXRuntimeImportStep() {
        let output =
            PythonProcessManager.controlMessagePrefix
            + "{\"type\":\"backend_preparation_progress\",\"step\":\"importing_mlx_runtime\",\"detail\":\"Loading the MLX runtime components needed for Apple GPU transcription.\"}"

        let progress = PythonProcessManager.parseBackendPreparationProgress(from: output)

        XCTAssertEqual(progress?.step, .importingMLXRuntime)
    }

    func testParseBackendPreparationProgressReturnsNilForOtherControlMessages() {
        let output =
            PythonProcessManager.controlMessagePrefix
            + "{\"type\":\"managed_model\",\"model\":{\"kind\":\"mlx\",\"displayName\":\"MLX model\",\"modelID\":\"mlx-community/whisper-large-v3-turbo\",\"directoryPath\":\"/tmp/mlx\",\"isDownloaded\":false,\"fileCount\":0,\"byteCount\":0}}"

        XCTAssertNil(PythonProcessManager.parseBackendPreparationProgress(from: output))
    }

    func testParseManagedModelsResponseDecodesControlMessage() {
        let output =
            PythonProcessManager.controlMessagePrefix
            + "{\"type\":\"managed_models\",\"request_id\":17,\"models\":[{\"kind\":\"cpu\",\"displayName\":\"CPU model\",\"modelID\":\"large-v3-turbo\",\"directoryPath\":\"/tmp/cpu\",\"isDownloaded\":true,\"fileCount\":3,\"byteCount\":100}]}"

        let response = PythonProcessManager.parseManagedModelsResponse(from: output)

        XCTAssertEqual(response?.type, "managed_models")
        XCTAssertEqual(response?.models.first?.kind, .cpu)
        XCTAssertEqual(response?.models.first?.directoryPath, "/tmp/cpu")
        XCTAssertEqual(response?.models.first?.isDownloaded, true)
        XCTAssertEqual(response?.requestID, 17)
    }

    func testParseManagedModelResponseDecodesControlMessage() {
        let output =
            PythonProcessManager.controlMessagePrefix
            + "{\"type\":\"managed_model\",\"request_id\":17,\"model\":{\"kind\":\"mlx\",\"displayName\":\"MLX model\",\"modelID\":\"mlx-community/whisper-large-v3-turbo\",\"directoryPath\":\"/tmp/mlx\",\"isDownloaded\":false,\"fileCount\":0,\"byteCount\":0}}"

        let response = PythonProcessManager.parseManagedModelResponse(from: output)

        XCTAssertEqual(response?.type, "managed_model")
        XCTAssertEqual(response?.model.kind, .mlx)
        XCTAssertEqual(response?.model.isDownloaded, false)
        XCTAssertEqual(response?.requestID, 17)
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
        XCTAssertEqual(environment["KOTOTYPE_CPU_MODEL_DIR"], KotoTypeStoragePaths.managedModelDirectory(for: .cpu).path)
        XCTAssertEqual(environment["KOTOTYPE_MLX_MODEL_DIR"], KotoTypeStoragePaths.managedModelDirectory(for: .mlx).path)
        XCTAssertEqual(environment["KOTOTYPE_MODEL_CACHE_DIR"], KotoTypeStoragePaths.managedModelCacheRoot().path)
        XCTAssertEqual(environment["HF_HOME"], KotoTypeStoragePaths.huggingFaceHome().path)
        XCTAssertEqual(environment["HUGGINGFACE_HUB_CACHE"], KotoTypeStoragePaths.huggingFaceHubCache().path)
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
        XCTAssertEqual(environment["KOTOTYPE_CPU_MODEL_DIR"], KotoTypeStoragePaths.managedModelDirectory(for: .cpu).path)
        XCTAssertEqual(environment["KOTOTYPE_MLX_MODEL_DIR"], KotoTypeStoragePaths.managedModelDirectory(for: .mlx).path)
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

    func testConcurrentHealthCheckRequestsRemainLineDelimited() throws {
        let fileManager = FileManager.default
        let scriptURL = fileManager.temporaryDirectory
            .appendingPathComponent("koto-type-echo-\(UUID().uuidString).py")
        let script = """
        import sys

        for line in sys.stdin:
            print(line.rstrip("\\n"), flush=True)
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: scriptURL) }

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pythonPath = packageRoot
            .deletingLastPathComponent()
            .appendingPathComponent(".venv/bin/python")
        guard fileManager.isExecutableFile(atPath: pythonPath.path) else {
            throw XCTSkip("The repository virtualenv Python executable is unavailable")
        }

        let runtime = makeRuntime(
            currentDirectoryPath: packageRoot.path,
            bundlePath: packageRoot.appendingPathComponent(".build/debug/KotoType").path,
            bundleResourcePath: nil,
            existingPaths: [scriptURL.path, pythonPath.path],
            uvPath: nil
        )
        let manager = PythonProcessManager(runtime: runtime)
        let outputLock = NSLock()
        var received: [String] = []
        let requestCount = 24
        let outputReceived = expectation(description: "echo backend returns every request")
        outputReceived.expectedFulfillmentCount = requestCount
        manager.outputReceived = { line in
            outputLock.lock()
            received.append(line)
            outputLock.unlock()
            outputReceived.fulfill()
        }

        manager.startPython(scriptPath: scriptURL.path)
        XCTAssertTrue(manager.isRunning())

        let messages = (0..<requestCount).map { index in
            "__KOTOTYPE_HEALTHCHECK__:\(index):\(String(repeating: "x", count: 12_000))"
        }
        let expected = Set(messages)
        let sendFailures = LockedInt()
        DispatchQueue.concurrentPerform(iterations: requestCount) { index in
            if !manager.sendInput(messages[index]) {
                sendFailures.increment()
            }
        }

        wait(for: [outputReceived], timeout: 10)
        manager.stop()

        XCTAssertEqual(sendFailures.value, 0)
        XCTAssertEqual(Set(received), expected)
    }

    func testActualPipePreservesLongJapaneseOutput() throws {
        let fileManager = FileManager.default
        let scriptURL = fileManager.temporaryDirectory
            .appendingPathComponent("koto-type-output-" + UUID().uuidString + ".py")
        let payload = String(repeating: "日本語の文字起こしです。", count: 2_000)
        let script = """
        print("日本語の文字起こしです。" * 2000, flush=True)
        print("PIPE_DONE", flush=True)
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: scriptURL) }

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let pythonPath = packageRoot
            .deletingLastPathComponent()
            .appendingPathComponent(".venv/bin/python")
        guard fileManager.isExecutableFile(atPath: pythonPath.path) else {
            throw XCTSkip("The repository virtualenv Python executable is unavailable")
        }

        let runtime = makeRuntime(
            currentDirectoryPath: packageRoot.path,
            bundlePath: packageRoot.appendingPathComponent(".build/debug/KotoType").path,
            bundleResourcePath: nil,
            existingPaths: [scriptURL.path, pythonPath.path],
            uvPath: nil
        )
        let manager = PythonProcessManager(runtime: runtime)
        let outputLock = NSLock()
        var received: [String] = []
        let done = expectation(description: "actual subprocess returns long Japanese output")
        manager.outputReceived = { line in
            outputLock.lock()
            received.append(line)
            outputLock.unlock()
            if line == "PIPE_DONE" {
                done.fulfill()
            }
        }

        manager.startPython(scriptPath: scriptURL.path)
        defer { manager.stop() }
        wait(for: [done], timeout: 10)

        outputLock.lock()
        let transcript = received.first
        outputLock.unlock()
        XCTAssertEqual(transcript, payload)
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

private final class LockedInt: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        let current = storage
        lock.unlock()
        return current
    }
}
