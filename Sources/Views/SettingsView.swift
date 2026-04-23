import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                settingsSection("General") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { appModel.settings.launchAtLoginEnabled },
                        set: { appModel.updateLaunchAtLogin($0) }
                    ))

                    settingsRow("Default capture mode") {
                        Picker("Default capture mode", selection: $appModel.settings.defaultCaptureMode) {
                            ForEach(CaptureMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                    }

                    settingsRow("Storage root folder") {
                        TextField("Storage root folder", text: $appModel.settings.storageRootFolder)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                settingsSection("Storage") {
                    settingsRow("Audio retention") {
                        Picker("Audio retention", selection: $appModel.settings.audioRetentionPolicy) {
                            ForEach(AudioRetentionPolicy.allCases) { policy in
                                Text(policy.title).tag(policy)
                            }
                        }
                        .labelsHidden()
                    }

                    Toggle("Automatic cleanup", isOn: $appModel.settings.autoCleanupEnabled)
                }

                settingsSection("Transcription") {
                    settingsRow("Model identifier") {
                        TextField("Local model identifier", text: $appModel.settings.transcriptionModelIdentifier)
                            .textFieldStyle(.roundedBorder)
                    }

                    settingsRow("Language") {
                        TextField("auto, en, de, ...", text: $appModel.settings.transcriptionLanguage)
                            .textFieldStyle(.roundedBorder)
                    }

                    infoText("LoqBar can use either externally configured transcription files or the hidden managed `.loqbar` folder inside the storage root.")
                    monoText(appModel.settings.managedTranscriptionRootFolder)

                    settingsRow("External whisper-cli") {
                        TextField("Optional external whisper-cli path", text: $appModel.settings.transcriptionExecutablePath)
                            .textFieldStyle(.roundedBorder)
                    }

                    settingsRow("External model") {
                        TextField("Optional external model path", text: $appModel.settings.transcriptionModelPath)
                            .textFieldStyle(.roundedBorder)
                    }

                    if appModel.settings.hasExternalTranscriptionPaths {
                        infoText("External transcription paths are configured, so LoqBar will prefer those files and leave your existing setup untouched.")
                    } else {
                        infoText("If no external paths are configured, LoqBar will look for managed files inside the hidden `.loqbar` folder.")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom vocabulary")
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: Binding(
                            get: { appModel.settings.customVocabularyEntries.joined(separator: "\n") },
                            set: { appModel.settings.customVocabularyEntries = $0.split(separator: "\n").map(String.init) }
                        ))
                        .frame(minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                    }
                }

                HStack {
                    Spacer()
                    Button("Save Settings") {
                        appModel.persist()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
    }

    private func settingsRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func infoText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func monoText(_ text: String) -> some View {
        Text(text)
            .font(.footnote.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}
