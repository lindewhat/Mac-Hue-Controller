import Foundation
import Testing
@testable import HueKit

/// Records what the queue sent, in order.
private actor Recorder {
    var sent: [(Target, Command)] = []
    var failures = 0
    func add(_ t: Target, _ c: Command) { sent.append((t, c)) }
    func fail() { failures += 1 }
}

private let light = Target(.light, "l1")
private let room = Target(.groupedLight, "g1")

@Test func aSingleClickIsSentAtOnce() async {
    let rec = Recorder()
    let q = CommandQueue(gap: { _ in .milliseconds(200) }, send: { await rec.add($0, $1) }, onError: { _, _ in })
    let start = ContinuousClock.now
    await q.enqueue(Command(on: true), for: light)
    await q.waitUntilIdle()
    #expect(ContinuousClock.now - start < .milliseconds(150))
    #expect(await rec.sent.map(\.1) == [Command(on: true)])
}

@Test func aSliderDragSendsFirstAndFinalValueAndFewInBetween() async {
    let rec = Recorder()
    let q = CommandQueue(gap: { _ in .milliseconds(60) }, send: { await rec.add($0, $1) }, onError: { _, _ in })
    for value in 1...50 {
        await q.enqueue(Command(brightness: Double(value)), for: light)
        try? await Task.sleep(for: .milliseconds(4))
    }
    await q.waitUntilIdle()
    let values = await rec.sent.compactMap(\.1.dimming?.brightness)
    #expect(values.first == 1)
    #expect(values.last == 50)            // the final position is always sent
    #expect(values.count < 20)            // but not every step
    #expect(values == values.sorted())    // and in order
}

@Test func noClickIsLostWhileAChangeIsWaiting() async {
    let rec = Recorder()
    let q = CommandQueue(gap: { _ in .milliseconds(100) }, send: { await rec.add($0, $1) }, onError: { _, _ in })
    await q.enqueue(Command(brightness: 10), for: light) // goes out at once
    await q.enqueue(Command(on: false), for: light)      // waits...
    await q.enqueue(Command(brightness: 40), for: light) // ...and is merged with this
    await q.waitUntilIdle()
    let sent = await rec.sent.map(\.1)
    #expect(sent == [Command(brightness: 10), Command(on: false, brightness: 40)])
}

@Test func differentLightsDoNotWaitForEachOther() async {
    let rec = Recorder()
    let q = CommandQueue(gap: { _ in .milliseconds(500) }, send: { await rec.add($0, $1) }, onError: { _, _ in })
    let start = ContinuousClock.now
    await q.enqueue(Command(on: true), for: light)
    await q.enqueue(Command(on: true), for: room)
    await q.enqueue(Command(on: true), for: Target(.light, "l2"))
    await q.waitUntilIdle()
    #expect(ContinuousClock.now - start < .milliseconds(300))
    #expect(await rec.sent.count == 3)
}

@Test func aBusyBridgeGetsTheCommandAgain() async {
    let rec = Recorder()
    let q = CommandQueue(gap: { _ in .milliseconds(10) }, send: { t, c in
        if await rec.failures == 0 { await rec.fail(); throw HueError.rateLimited }
        await rec.add(t, c)
    }, onError: { _, _ in })
    await q.enqueue(Command(on: true), for: room)
    await q.waitUntilIdle()
    #expect(await rec.sent.map(\.1) == [Command(on: true)])
}

@Test func failuresAreReported() async {
    let rec = Recorder()
    let q = CommandQueue(gap: { _ in .milliseconds(10) }, send: { _, _ in throw HueError.unreachable },
                         onError: { _, _ in await rec.fail() })
    await q.enqueue(Command(on: true), for: light)
    await q.waitUntilIdle()
    #expect(await rec.failures == 1)
}

@Test func manyLightsShareTheBridgesBudget() async {
    let rec = Recorder()
    let q = CommandQueue(gap: { _ in .milliseconds(10) }, lightSpacing: .milliseconds(50),
                         send: { await rec.add($0, $1) }, onError: { _, _ in })
    let start = ContinuousClock.now
    for i in 1...5 { await q.enqueue(Command(brightness: 50), for: Target(.light, "l\(i)")) }
    await q.waitUntilIdle()
    #expect(await rec.sent.count == 5)                         // every light got it
    #expect(ContinuousClock.now - start >= .milliseconds(190)) // but spaced out, not all at once
}
