import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { appModel.settings.launchAtLoginEnabled },
                    set: { appModel.updateLaunchAtLogin($0) }
                ))

                Picker("Default capture mode", selection: $appModel.settings.defaultCaptureMode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                TextField("Storage root folder", text: $appModel.settings.storageRootFolder)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Storage") {
                Picker("Audio retention", selection: $appModel.settings.audioRetentionPolicy) {
                    ForEach(AudioRetentionPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }

                Toggle("Automatic cleanup", isOn: $appModel.settings.autoCleanupEnabled)
            }

            Section("Transcription") {
                TextField("Local model identifier", text: $appModel.settings.transcriptionModelIdentifier)
                    .textFieldStyle(.roundedBorder)

                TextField("Language (`auto`, `en`, `de`, ...)", text: $appModel.settings.transcriptionLanguage)
                    .textFieldStyle(.roundedBorder)

                Text("LoqBar can use either externally configured transcription files or the hidden managed `.loqbar` folder inside the storage root.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(appModel.settings.managedTranscriptionRootFolder)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                TextField("Optional external whisper-cli path", text: $appModel.settings.transcriptionExecutablePath)
                    .textFieldStyle(.roundedBorder)

                TextField("Optional external model path", text: $appModel.settings.transcriptionModelPath)
                    .textFieldStyle(.roundedBorder)

                if appModel.settings.hasExternalTranscriptionPaths {
                    Text("External transcription paths are configured, so LoqBar will prefer those files and leave your existing setup untouched.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("If no external paths are configured, LoqBar will look for managed files inside the hidden `.loqbar` folder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                TextEditor(text: Binding(
                    get: { appModel.settings.customVocabularyEntries.joined(separator: "\n") },
                    set: { appModel.settings.customVocabularyEntries = $0.split(separator: "\n").map(String.init) }
                ))
                .frame(height: 120)
            }

            Section {
                Button("Save Settings") {
                    appModel.persist()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }
}
