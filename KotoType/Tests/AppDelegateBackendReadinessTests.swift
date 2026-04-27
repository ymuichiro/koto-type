import XCTest
@testable import KotoType

final class AppDelegateBackendReadinessTests: XCTestCase {
    func testShouldWaitForWarmRealtimeBackendWhenPreparationInFlight() {
        XCTAssertTrue(
            AppDelegate.shouldWaitForWarmRealtimeBackend(
                keepBackendReadyInBackground: true,
                currentBackendStatus: TranscriptionBackendStatus(
                    effectiveBackend: .mlx,
                    gpuRequested: true,
                    gpuAvailable: true,
                    fallbackReason: nil
                ),
                isAwaitingPreparedRealtimeBackend: true,
                hasExpectedRealtimeWorkers: true
            )
        )
    }

    func testShouldNotWaitWhenWarmRealtimeBackendIsReady() {
        XCTAssertFalse(
            AppDelegate.shouldWaitForWarmRealtimeBackend(
                keepBackendReadyInBackground: true,
                currentBackendStatus: TranscriptionBackendStatus(
                    effectiveBackend: .mlx,
                    gpuRequested: true,
                    gpuAvailable: true,
                    fallbackReason: nil
                ),
                isAwaitingPreparedRealtimeBackend: false,
                hasExpectedRealtimeWorkers: true
            )
        )
    }

    func testBackendPreparationIndicatorMessageUsesProgressTitle() {
        let message = AppDelegate.backendPreparationIndicatorMessage(
            progress: BackendPreparationProgress(step: .importingMLXRuntime)
        )

        XCTAssertEqual(message, "Loading Apple GPU runtime")
    }
}
