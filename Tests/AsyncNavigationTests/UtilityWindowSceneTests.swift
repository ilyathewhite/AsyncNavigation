#if os(macOS)
import AppKit
import Foundation
import Testing

extension AsyncNavigationTestSuites {
    @MainActor
    @Suite(.serialized) struct UtilityWindowSceneTests {}
}

extension AsyncNavigationTestSuites.UtilityWindowSceneTests {
    @Test
    func presentationForwardsFrameKeyAndOwnerRemovalClosesWindow() async throws {
        let app = try UtilityTestApplication()
        defer { app.cleanUp() }
        let report = try await app.run("lifecycle")
        #expect(report.failures.isEmpty, "\(report.failures.joined(separator: "; ")); windows: \(report.windows)")
        #expect(report.checks.contains("owner removal never rebuilds cancelled content"))
    }

    @Test
    func utilityWindowsStayClosedAfterQuitAndRelaunch() async throws {
        let app = try UtilityTestApplication()
        defer { app.cleanUp() }
        let firstLaunch = try await app.run("leave-open")
        try #require(firstLaunch.failures.isEmpty, "\(firstLaunch.failures.joined(separator: "; "))")
        let relaunch = try await app.run("relaunch")
        #expect(relaunch.failures.isEmpty, "\(relaunch.failures.joined(separator: "; "))")
        #expect(relaunch.checks.contains("ordinary window restores after relaunch"))
    }
}

// Package tests cannot own SwiftUI's App lifecycle. Launch a bundled fixture, using a unique identity and defaults.
@MainActor
private final class UtilityTestApplication {
    struct Report: Decodable {
        let checks: [String]
        let failures: [String]
        let windows: [String]
    }

    let directory: URL
    let bundleURL: URL
    let bundleID: String
    let defaultsName: String

    init() throws {
        bundleID = "org.AsyncNavigation.WindowTests.\(UUID().uuidString)"
        defaultsName = bundleID + ".frames"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(bundleID, isDirectory: true)
        bundleURL = directory.appendingPathComponent("UtilityWindowTest.app", isDirectory: true)
        let executableDirectory = bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        let binary = try Self.fixtureBinary()
        try FileManager.default.copyItem(at: binary, to: executableDirectory.appendingPathComponent("WindowTest"))
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": "WindowTest",
            "CFBundleName": "UtilityWindowTest",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
            "NSPrincipalClass": "NSApplication",
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
    }

    func run(_ mode: String) async throws -> Report {
        let reportURL = directory.appendingPathComponent("\(mode).json")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        configuration.arguments = [mode, reportURL.path, defaultsName]
        if let profile = ProcessInfo.processInfo.environment["LLVM_PROFILE_FILE"] {
            let profileDirectory = URL(fileURLWithPath: profile).deletingLastPathComponent()
            configuration.environment = [
                "LLVM_PROFILE_FILE": profileDirectory.appendingPathComponent("UtilityWindowTestApp-%p.profraw").path
            ]
        }
        let app = try await NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
        defer { if !app.isTerminated { app.forceTerminate() } }
        let terminated = await waitUntil(timeout: 20) { app.isTerminated }
        try #require(terminated, "Fixture app did not finish scenario \(mode)")
        let data = try Data(contentsOf: reportURL)
        return try JSONDecoder().decode(Report.self, from: data)
    }

    func cleanUp() {
        UserDefaults(suiteName: defaultsName)?.removePersistentDomain(forName: defaultsName)
        UserDefaults(suiteName: bundleID)?.removePersistentDomain(forName: bundleID)
        let state = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Saved Application State/\(bundleID).savedState")
        try? FileManager.default.removeItem(at: state)
        try? FileManager.default.removeItem(at: directory)
    }

    private static func fixtureBinary() throws -> URL {
        // SwiftPM puts executable dependencies next to the .xctest bundle (or the test runner on older toolchains).
        var directory = Bundle(for: FixtureBundleToken.self).bundleURL.deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = directory.appendingPathComponent("UtilityWindowTestApp")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "Build UtilityWindowTestApp first"])
    }
}
private final class FixtureBundleToken: NSObject {}
#endif
