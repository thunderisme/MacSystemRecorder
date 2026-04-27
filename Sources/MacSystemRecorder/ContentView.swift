import AppKit
import ScreenCaptureKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var recorder: RecorderModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                sourcePanel
                audioPanel
                optionsPanel
                statusBar
            }
            .padding(22)

            Spacer(minLength: 0)

            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await recorder.refreshDisplays()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(recorder.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 42, height: 42)

                Image(systemName: recorder.isRecording ? "waveform" : "record.circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Mac System Recorder")
                    .font(.system(size: 22, weight: .semibold))

                Text("Screen recording with system audio, delay, and crop.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if recorder.isRecording {
                Label(recorder.elapsedText, systemImage: "record.circle.fill")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var sourcePanel: some View {
        SettingsPanel(title: "Source", systemImage: "display") {
            settingRow("Display") {
                Picker("Display", selection: $recorder.selectedDisplayID) {
                    ForEach(recorder.displays) { display in
                        Text(display.name).tag(Optional(display.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
                .disabled(recorder.controlsAreLocked || recorder.displays.isEmpty)
            }

            settingRow(recorder.outputLocationLabel) {
                HStack(spacing: 8) {
                    Text(recorder.outputLocationText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        recorder.revealCurrentOutputInFinder()
                    } label: {
                        Label("Show", systemImage: "folder")
                    }
                    .disabled(recorder.isRecording)

                    Button("Choose...") {
                        recorder.chooseOutputLocation()
                    }
                    .disabled(recorder.controlsAreLocked)
                }
            }
        }
    }

    private var audioPanel: some View {
        SettingsPanel(title: "Audio", systemImage: "speaker.wave.2") {
            HStack(spacing: 24) {
                Toggle("Capture system audio", isOn: $recorder.captureSystemAudio)
                    .disabled(recorder.controlsAreLocked)

                Toggle("Hide this app from the recording", isOn: $recorder.hideCurrentApp)
                    .disabled(recorder.controlsAreLocked)

                Spacer()
            }
        }
    }

    private var optionsPanel: some View {
        SettingsPanel(title: "Options", systemImage: "slider.horizontal.3") {
            settingRow("Start delay") {
                Picker("Start delay", selection: $recorder.startDelaySeconds) {
                    Text("None").tag(0)
                    Text("3s").tag(3)
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 270)
                .disabled(recorder.controlsAreLocked)
            }

            settingRow("Crop") {
                HStack(spacing: 10) {
                    Toggle("Selected area", isOn: $recorder.useCrop)
                        .disabled(recorder.controlsAreLocked)

                    Button {
                        recorder.selectCropArea()
                    } label: {
                        Label("Select Area", systemImage: "crop")
                    }
                    .disabled(recorder.controlsAreLocked || !recorder.useCrop || recorder.selectedDisplayID == nil)

                    Button {
                        recorder.clearCropArea()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .disabled(recorder.controlsAreLocked || recorder.cropRect == nil)

                    Text(recorder.cropDescription)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: recorder.statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(recorder.statusIsError ? .red : .green)
                .frame(width: 18)

            Text(recorder.statusMessage)
                .foregroundStyle(recorder.statusIsError ? .red : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                Task { await recorder.toggleRecording() }
            } label: {
                Label(recorder.primaryButtonTitle,
                      systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                    .frame(minWidth: 170)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(recorder.isRecording ? .red : .accentColor)
            .disabled(!recorder.canStartOrStop)

            Button {
                Task { await recorder.refreshDisplays() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .controlSize(.large)
            .disabled(recorder.controlsAreLocked)

            Spacer()

            Text("Auto-saves as MP4")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private func settingRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)

            content()
        }
    }
}

private struct SettingsPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct DisplayChoice: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let display: SCDisplay
}
