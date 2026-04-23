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

                Text("LoqBar manages `whisper-cli` and model files automatically inside a hidden folder within the storage root.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(appModel.settings.managedTranscriptionRootFolder)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if appModel.settings.hasLegacyManualTranscriptionPaths {
                    Text("Legacy manual transcription paths are still present in settings for compatibility, but the intended setup is the hidden `.loqbar` folder inside the storage root.")
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
