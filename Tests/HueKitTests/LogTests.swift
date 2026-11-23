import Foundation
import Testing
@testable import HueKit

private func tempFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "hue-log-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func aLogLineHasTimeLevelAreaAndText() {
    let date = Date(timeIntervalSince1970: 1_795_000_085) // 2026-11-18 ...:05 UTC
    let line = LogFile.line(level: "ERROR", area: "command", text: "light 3 failed:\ntimed out", date: date,
                            timeZone: TimeZone(identifier: "UTC")!)
    #expect(line.hasSuffix(":05 ERROR command light 3 failed: timed out"))
    #expect(line.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} "#, options: .regularExpression) != nil)
}

@Test func theLogFileRotatesWhenItGetsBig() throws {
    let folder = tempFolder()
    let url = folder.appending(path: "Test.log")
    let file = LogFile(url: url, maxBytes: 200)
    for i in 1...40 { file.append("line \(i) with some padding to grow the file") }
    file.flush()
    let current = try String(contentsOf: url, encoding: .utf8)
    let old = try String(contentsOf: url.appendingPathExtension("1"), encoding: .utf8)
    #expect(current.contains("line 40"))
    #expect(!old.isEmpty)
    #expect(current.utf8.count < 400)
}

@Test func aLogThatCannotBeWrittenIsIgnored() {
    let file = LogFile(url: URL(filePath: "/nonexistent-root-folder/x/Test.log"))
    file.append("nothing happens")
    file.flush() // no crash, no throw
}

@Test func errorsAreDescribedWithoutTheirMessageText() {
    // URLError messages can name the bridge's address; only the code may reach the log.
    let url = URLError(.serverCertificateUntrusted, userInfo: [
        NSURLErrorFailingURLStringErrorKey: "https://192.168.77.5/clip/v2/resource/light",
        NSLocalizedDescriptionKey: "pretending to be “192.168.77.5”",
    ])
    let described = Log.describe(url)
    #expect(described.contains("-1202"))
    #expect(!described.contains("192.168"))
    #expect(!Log.describe(HueError.bridgeSaid("Kitchen lamp is unreachable")).contains("Kitchen"))
}

@Test func commandFieldNamesCarryNoValues() {
    let names = Command(on: false, brightness: 42).fieldNames
    #expect(names == "on, dimming")
}

/// These two use the shared log, so they run one after the other.
@Suite(.serialized) struct SharedLogTests {
    @Test func labelsAreAnonymousAndStableWithinARun() {
        let a = Log.label("testthing", "id-a")
        let b = Log.label("testthing", "id-b")
        #expect(a != b)
        #expect(Log.label("testthing", "id-a") == a)
        #expect(a.hasPrefix("testthing ") && !a.contains("id-a"))
    }

    @Test func aCommandProblemIsLoggedWithoutTheLightsIdOrAddress() async throws {
        let url = tempFolder().appending(path: "Mac Hue Control.log")
        Log.start(url: url, startLine: "test run")
        let secret = Target(.light, "f00d-secret-light-id")
        let tries = Counter()
        let queue = CommandQueue(gap: { _ in .milliseconds(10) }, send: { _, _ in
            if await tries.next() == 1 { throw HueError.rateLimited }
        }, onError: { _, _ in })
        await queue.enqueue(Command(brightness: 50), for: secret)
        await queue.waitUntilIdle()
        Log.error("bridge", "reading failed: \(Log.describe(URLError(.timedOut)))")
        Log.flush()

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("INFO app test run"))
        #expect(text.contains("bridge busy, trying again"))
        #expect(text.contains("URLError -1001 timed out"))
        #expect(!text.contains("f00d-secret-light-id"))
        #expect(text.range(of: #"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}"#, options: .regularExpression) == nil)
    }
}

private actor Counter {
    var n = 0
    func next() -> Int { n += 1; return n }
}
