import Foundation
import Testing
@testable import HueKit

/// The Sonos app once had a search that never finished. This makes sure the bridge search always returns,
/// even when nothing answers.
@Test func discoveryFinishesWhenNothingIsFound() async {
    let start = ContinuousClock.now
    let result = await BridgeDiscovery(serviceType: "_machuecontrol-test._tcp").discover(maxWait: 0.5)
    #expect(result.bridges.isEmpty)
    #expect(ContinuousClock.now - start < .seconds(3))
}

@Test func severalSearchesAtOnceAllFinish() async {
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<3 {
            group.addTask { _ = await BridgeDiscovery(serviceType: "_machuecontrol-test._tcp").discover(maxWait: 0.3) }
        }
    }
}
