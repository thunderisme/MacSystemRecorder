import AppKit
@preconcurrency import AVFoundation
import CoreGraphics
import ScreenCaptureKit
import SwiftUI

@MainActor
final class RecorderModel: ObservableObject {
    enum ScreenCapturePermissionState {
        case unknown
        case granted
        case needsPermission
        case needsRelaunch
    }

    @Published var displays: [DisplayChoice] = []
    @Published var selectedDisplayID: CGDirectDisplayID?
    @Published var outputURL: URL = RecorderModel.defaultOutputURL()
    @Published var lastSavedURL: URL?
    @Published var captureSystemAudio = true
    @Published var hideCurrentApp = true
    @Published var startDelaySeconds = 0
    @Published var useCrop = false
    @Published var cropRect: CGRect?
    @Published var isRecording = false
    @Published var isCountingDown = false
    @Published var statusMessage = "Ready."
    @Published var statusIsError = false
    @Published var elapsedText = "00:00"
    @Published var screenCapturePermissionState: ScreenCapturePermissionState = .unknown

    private var recorder: ScreenRecorder?
    private var startedAt: Date?
    private var elapsedTimer: Timer?
    private var countdownTask: Task<Void, Never>?
    private var cropDisplayID: CGDirectDisplayID?

    var canStartOrStop: Bool {
        isRecording || isCountingDown || (hasScreenCapturePermission && selectedDisplayID != nil)
    }

    var controlsAreLocked: Bool {
        isRecording || isCountingDown
    }

    var primaryButtonTitle: String {
        if isRecording { return "Stop Recording" }
        if isCountingDown { return "Cancel Start" }
        return "Start Recording"
    }

    var cropDescription: String {
        guard useCrop else { return "Full display" }
        guard let cropRect, cropDisplayID == selectedDisplayID else { return "No area selected" }
        return "\(Int(cropRect.width)) x \(Int(cropRect.height)) at \(Int(cropRect.minX)), \(Int(cropRect.minY))"
    }

    var outputLocationText: String {
        if isRecording {
            return outputURL.path
        }
        if let lastSavedURL {
            return lastSavedURL.path
        }
        return outputURL.path
    }

    var outputLocationLabel: String {
        lastSavedURL == nil || isRecording ? "Save to" : "Last saved"
    }

    var hasScreenCapturePermission: Bool {
        screenCapturePermissionState == .granted
    }

    var permissionTitle: String {
        switch screenCapturePermissionState {
        case .unknown:
            "Checking Screen Recording Access"
        case .granted:
            "Screen Recording Access Enabled"
        case .needsPermission:
            "Screen Recording Access Needed"
        case .needsRelaunch:
            "Restart Needed"
        }
    }

    var permissionMessage: String {
        switch screenCapturePermissionState {
        case .unknown:
            "MacSystemRecorder is checking macOS privacy access."
        case .granted:
            "MacSystemRecorder can record the selected display and system audio."
        case .needsPermission:
            "Enable MacSystemRecorder in System Settings, then quit and reopen the app. macOS usually applies Screen Recording changes only after relaunch."
        case .needsRelaunch:
            "macOS shows Screen Recording access is enabled, but this running copy has not picked it up yet. Quit and reopen MacSystemRecorder."
        }
    }

    func refreshDisplays() async {
        let preflightAllowsScreenCapture = CGPreflightScreenCaptureAccess()

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let choices = content.displays.enumerated().map { index, display in
                DisplayChoice(
                    id: display.displayID,
                    name: displayName(for: display, fallbackIndex: index + 1),
                    display: display
                )
            }
            displays = choices
            if selectedDisplayID == nil || !choices.contains(where: { $0.id == selectedDisplayID }) {
                selectedDisplayID = choices.first?.id
            }
            screenCapturePermissionState = .granted
            setStatus(choices.isEmpty ? "No displays found." : "Ready.", isError: choices.isEmpty)
        } catch {
            displays = []
            selectedDisplayID = nil
            if preflightAllowsScreenCapture {
                screenCapturePermissionState = .needsRelaunch
                setStatus("Permission is enabled, but macOS has not applied it to this running app. Quit and reopen MacSystemRecorder.", isError: true)
            } else {
                screenCapturePermissionState = .needsPermission
                setStatus("Enable MacSystemRecorder in System Settings, then quit and reopen the app. \(error.localizedDescription)", isError: true)
            }
        }
    }

    func requestScreenCapturePermission() async {
        if CGPreflightScreenCaptureAccess() {
            await refreshDisplays()
            return
        }

        let granted = CGRequestScreenCaptureAccess()
        if granted {
            await refreshDisplays()
        } else {
            screenCapturePermissionState = .needsPermission
            setStatus("macOS needs Screen Recording access for MacSystemRecorder. Enable it in System Settings, then quit and reopen the app.", isError: true)
        }
    }

    func chooseOutputLocation() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = outputURL.lastPathComponent
        panel.directoryURL = outputURL.deletingLastPathComponent()

        if panel.runModal() == .OK, let url = panel.url {
            outputURL = url.pathExtension.lowercased() == "mp4" ? url : url.appendingPathExtension("mp4")
            lastSavedURL = nil
        }
    }

    func revealCurrentOutputInFinder() {
        let url = lastSavedURL ?? outputURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    func relaunchApp() {
        let appURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", appURL.path]

        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            setStatus("Could not relaunch automatically. Quit and open the app again. \(error.localizedDescription)", isError: true)
        }
    }

    func selectCropArea() {
        guard let selectedDisplayID,
              let choice = displays.first(where: { $0.id == selectedDisplayID }),
              let screen = screen(for: choice.display) else {
            setStatus("Pick a display before selecting an area.", isError: true)
            return
        }

        guard let selection = CropSelectionSession.selectArea(on: screen) else {
            return
        }

        let scale = screen.backingScaleFactor
        let screenHeight = screen.frame.height
        let pixelRect = CGRect(
            x: selection.minX * scale,
            y: (screenHeight - selection.maxY) * scale,
            width: selection.width * scale,
            height: selection.height * scale
        ).integral

        guard pixelRect.width >= 64, pixelRect.height >= 64 else {
            setStatus("Select an area at least 64 x 64 pixels.", isError: true)
            return
        }

        cropRect = clamp(pixelRect, to: CGSize(width: choice.display.width, height: choice.display.height))
        cropDisplayID = selectedDisplayID
        useCrop = true
        setStatus("Crop area selected.", isError: false)
    }

    func clearCropArea() {
        cropRect = nil
        cropDisplayID = nil
        setStatus("Crop cleared.", isError: false)
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecording()
        } else if isCountingDown {
            cancelCountdown()
        } else {
            await startRecording()
        }
    }

    private func startRecording() async {
        guard let selectedDisplayID,
              let display = displays.first(where: { $0.id == selectedDisplayID })?.display else {
            setStatus("Pick a display first.", isError: true)
            return
        }

        if useCrop && (cropRect == nil || cropDisplayID != selectedDisplayID) {
            setStatus("Select a crop area for the current display.", isError: true)
            return
        }

        if startDelaySeconds > 0 {
            beginCountdown(seconds: startDelaySeconds)
            return
        }

        await beginRecording(display: display, selectedDisplayID: selectedDisplayID)
    }

    private func beginCountdown(seconds: Int) {
        countdownTask?.cancel()
        isCountingDown = true
        countdownTask = Task { [weak self] in
            for remaining in stride(from: seconds, through: 1, by: -1) {
                await MainActor.run {
                    self?.setStatus("Recording starts in \(remaining)...", isError: false)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }

            await MainActor.run {
                guard let self,
                      let selectedDisplayID = self.selectedDisplayID,
                      let display = self.displays.first(where: { $0.id == selectedDisplayID })?.display else {
                    self?.isCountingDown = false
                    self?.setStatus("Pick a display first.", isError: true)
                    return
                }
                self.isCountingDown = false
                Task { await self.beginRecording(display: display, selectedDisplayID: selectedDisplayID) }
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        isCountingDown = false
        setStatus("Start canceled.", isError: false)
    }

    private func beginRecording(display: SCDisplay, selectedDisplayID: CGDirectDisplayID) async {
        do {
            lastSavedURL = nil
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: outputURL.path) {
                try fileManager.removeItem(at: outputURL)
            }

            let nextRecorder = try ScreenRecorder(
                display: display,
                outputURL: outputURL,
                captureSystemAudio: captureSystemAudio,
                hideCurrentApp: hideCurrentApp,
                cropRect: useCrop && cropDisplayID == selectedDisplayID ? cropRect : nil
            )
            try await nextRecorder.start()
            recorder = nextRecorder
            isRecording = true
            startedAt = Date()
            startElapsedTimer()
            setStatus("Recording to \(outputURL.path)", isError: false)
        } catch {
            setStatus("Could not start recording. \(error.localizedDescription)", isError: true)
        }
    }

    private func stopRecording() async {
        guard let recorder else { return }
        let savedURL = outputURL

        do {
            try await recorder.stop()
            self.recorder = nil
            isRecording = false
            stopElapsedTimer()
            lastSavedURL = savedURL
            outputURL = Self.defaultOutputURL()
            setStatus("Saved to \(savedURL.path)", isError: false)
        } catch {
            self.recorder = nil
            isRecording = false
            stopElapsedTimer()
            setStatus("Recording stopped, but finalizing failed. \(error.localizedDescription)", isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedText = "00:00"
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedText()
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        startedAt = nil
        elapsedText = "00:00"
    }

    private func updateElapsedText() {
        guard let startedAt else { return }
        let elapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
        elapsedText = String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }

    private static func defaultOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let filename = "ScreenRecording-\(formatter.string(from: Date())).mp4"
        return FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    private func displayName(for display: SCDisplay, fallbackIndex: Int) -> String {
        let screen = screen(for: display)

        let baseName = screen?.localizedName ?? "Display \(fallbackIndex)"
        return "\(baseName) (\(display.width)x\(display.height))"
    }

    private func screen(for display: SCDisplay) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return number.uint32Value == display.displayID
        }
    }

    private func clamp(_ rect: CGRect, to size: CGSize) -> CGRect {
        let x = min(max(rect.minX, 0), size.width - 1)
        let y = min(max(rect.minY, 0), size.height - 1)
        let width = min(rect.width, size.width - x)
        let height = min(rect.height, size.height - y)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }
}
