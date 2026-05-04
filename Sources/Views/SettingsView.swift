import SwiftUI
import AppKit

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case storage
    case transcription
    case sessions

    var id: Self { self }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .storage:
            return "Storage"
        case .transcription:
            return "Transcription"
        case .sessions:
            return "Sessions"
        }
    }

    var iconName: String {
        switch self {
        case .general:
            return "gearshape"
        case .storage:
            return "externaldrive"
        case .transcription:
            return "waveform.and.magnifyingglass"
        case .sessions:
            return "rectangle.stack"
        }
    }

    var summary: String {
        switch self {
        case .general:
            return "Capture defaults and startup behavior."
        case .storage:
            return "Where LoqBar stores recordings and transcripts."
        case .transcription:
            return "How local transcription is configured."
        case .sessions:
            return "Browse, search, and manage captured sessions."
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedPane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPane) {
                Section("Settings") {
                    ForEach([SettingsPane.general, .storage, .transcription], id: \.self) { pane in
                        Label(pane.title, systemImage: pane.iconName)
                            .tag(pane)
                    }
                }

                Section("Workspace") {
                    Label(SettingsPane.sessions.title, systemImage: SettingsPane.sessions.iconName)
                        .tag(SettingsPane.sessions)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 240)
        } detail: {
            if activePane == .sessions {
                SessionHistoryView(embeddedInSettings: true)
                    .environmentObject(appModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Color(nsColor: .windowBackgroundColor))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        detailHeader
                        detailContent

                        HStack {
                            Spacer()
                            Button("Save Settings") {
                                appModel.persist()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 760, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .onAppear {
            appModel.bringAuxiliaryWindowToFront(titleContains: "Settings")
        }
        .onDisappear {
            appModel.restoreMenuBarPresentationIfPossible()
        }
    }

    private var activePane: SettingsPane {
        selectedPane ?? .general
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: activePane.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 56, height: 56)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text(activePane.title)
                        .font(.largeTitle.weight(.semibold))
                    Text(activePane.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private var detailContent: some View {
        switch activePane {
        case .general:
            generalPane
        case .storage:
            storagePane
        case .transcription:
            transcriptionPane
        case .sessions:
            EmptyView()
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle("Launch at login", isOn: Binding(
                get: { appModel.settings.launchAtLoginEnabled },
                set: { appModel.updateLaunchAtLogin($0) }
            ))

            settingsField("Default capture mode") {
                Picker("Default capture mode", selection: $appModel.settings.defaultCaptureMode) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 340, alignment: .leading)
            }

            infoCard(
                title: "Updates",
                body: """
                Current version: \(appModel.currentAppVersionDisplay)
                Status: \(appModel.updateStatus.title)
                """
            )

            infoCard(
                title: "First Use Readiness",
                body: appModel.firstUseReadinessSummary
            )

            Button(appModel.updateStatus == .checking ? "Checking…" : "Check for Updates") {
                appModel.checkForUpdates()
            }
            .buttonStyle(.bordered)
            .disabled(appModel.updateStatus == .checking)

            infoCard(
                title: "Permissions",
                body: "Refresh LoqBar's permission state after changing microphone or screen recording access in System Settings. If macOS shows Screen Recording enabled but LoqBar still disagrees, use the reset action to force macOS to rebuild the ScreenCapture permission state."
            )

            HStack(spacing: 12) {
                Button("Refresh Permissions") {
                    appModel.refreshPermissions()
                }
                .buttonStyle(.bordered)

                Button("Reset Screen Permission") {
                    appModel.resetScreenCapturePermission()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var storagePane: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsField("Storage root folder") {
                pathField(
                    text: $appModel.settings.storageRootFolder,
                    placeholder: "Storage root folder",
                    chooseLabel: "Choose…",
                    secondaryLabel: "New Folder…"
                ) {
                    appModel.chooseStorageRootFolder()
                } secondaryAction: {
                    appModel.createStorageRootFolder()
                }
            }

            infoCard(
                title: "Folder Structure",
                body: """
                LoqBar will create these folders automatically:

                \(appModel.settings.recordingOutputFolder)
                \(appModel.settings.transcriptOutputFolder)
                """
            )

            settingsField("Audio file retention") {
                Picker("Audio file retention", selection: $appModel.settings.audioRetentionPolicy) {
                    ForEach(AudioRetentionPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 340, alignment: .leading)
            }

            Toggle("Automatically delete old audio files", isOn: $appModel.settings.autoCleanupEnabled)

            infoText("This cleanup only removes old recording audio files after the selected retention period. Session entries and exported transcripts stay available.")

            infoCard(
                title: "Cleanup Status",
                body: cleanupStatusText
            )

            Button("Run Cleanup Now") {
                appModel.runCleanupNow()
            }
            .buttonStyle(.bordered)
        }
    }

    private var transcriptionPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            transcriptionStatusCard

            settingsField("Model") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Transcription model", selection: Binding(
                        get: {
                            TranscriptionModelSuggestion.allCases.first(where: {
                                $0.identifier == appModel.settings.normalizedTranscriptionModelIdentifier
                            }) ?? .base
                        },
                        set: { appModel.settings.transcriptionModelIdentifier = $0.identifier }
                    )) {
                        ForEach(TranscriptionModelSuggestion.allCases) { suggestion in
                            Text(suggestion.title).tag(suggestion)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)

                    infoText("`Base` is fastest but weakest. `Small` is the best default for call recordings. `Medium` is stronger on noisy or difficult speech. `Large` is the highest-quality option here, but it can be much slower and heavier on memory and CPU/GPU. LoqBar downloads the selected managed model automatically when you install the managed setup.")
                }
            }

            infoCard(
                title: "Model Quality Guidance",
                body: modelQualityGuidanceText
            )

            settingsField("Transcription Mode") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Transcription mode", selection: $appModel.settings.transcriptionComputeMode) {
                        ForEach(TranscriptionComputeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 260, alignment: .leading)

                    infoText("`Auto` tries the best available local acceleration path and falls back safely if needed. `GPU Preferred` explicitly tries Metal/GPU first, then retries on CPU if acceleration fails. `CPU Only` preserves the most conservative behavior, but it is also the slowest.")
                }
            }

            settingsField("Language") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Language", selection: Binding(
                        get: { TranscriptionLanguageOption(rawValue: appModel.settings.transcriptionLanguage) ?? .auto },
                        set: { appModel.settings.transcriptionLanguage = $0.rawValue }
                    )) {
                        ForEach(TranscriptionLanguageOption.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 340, alignment: .leading)

                    infoText("`Auto Detect` is the safest default for calls that may switch between languages, such as German and English in the same session.")
                }
            }

            infoCard(
                title: "How LoqBar Chooses Transcription Files",
                body: """
                If you configure both external paths below, LoqBar will prefer those files and leave that setup untouched.

                If no external paths are configured, LoqBar uses the managed setup inside the hidden .loqbar folder for this Mac.
                """
            )

            infoCard(
                title: "Managed Transcription Folder",
                body: """
                LoqBar keeps the managed transcription runtime here:

                \(appModel.settings.managedTranscriptionRootFolder)

                Managed setup installs `whisper-cli`, its runtime libraries, and the selected model automatically for this Mac.
                """
            )

            infoCard(
                title: "Managed Setup Status",
                body: appModel.managedTranscriptionInstallStatus
            )

            HStack(spacing: 12) {
                Button(appModel.isInstallingManagedTranscription ? "Installing…" : managedInstallActionTitle) {
                    appModel.installManagedTranscriptionFiles()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.isInstallingManagedTranscription)

                if appModel.settings.hasExternalTranscriptionPaths {
                    Button("Use Managed Setup") {
                        appModel.clearExternalTranscriptionPaths()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Open Managed Folder") {
                    appModel.openManagedTranscriptionFolder()
                }
                .buttonStyle(.bordered)
            }

            if appModel.settings.hasExternalTranscriptionPaths {
                infoText("External transcription paths are configured, so LoqBar will prefer those files. Choose `Use Managed Setup` when you want this Mac to switch back to the managed runtime.")
            } else {
                infoText("No external transcription paths are configured right now, so LoqBar will rely on the managed setup when transcription is ready.")
            }

            Button("Clear External Paths") {
                appModel.clearExternalTranscriptionPaths()
            }
            .buttonStyle(.bordered)
            .disabled(
                appModel.settings.transcriptionExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                appModel.settings.transcriptionModelPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            settingsField("Optional external whisper-cli path") {
                pathField(
                    text: $appModel.settings.transcriptionExecutablePath,
                    placeholder: "Optional external whisper-cli path",
                    chooseLabel: "Choose…"
                ) {
                    appModel.chooseExternalWhisperExecutable()
                }
            }

            settingsField("Optional external model path") {
                pathField(
                    text: $appModel.settings.transcriptionModelPath,
                    placeholder: "Optional external model path",
                    chooseLabel: "Choose…"
                ) {
                    appModel.chooseExternalModelFile()
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Custom vocabulary")
                    .font(.headline)
                Text("Add one term per line for names, product names, abbreviations, or jargon Whisper often gets wrong. Example entries: `LoqBar`, `LLM`, `ScreenCaptureKit`, `whisper.cpp`. LoqBar will pass these terms as hints during transcription.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { appModel.settings.customVocabularyEntries.joined(separator: "\n") },
                    set: { appModel.settings.customVocabularyEntries = $0.split(separator: "\n").map(String.init) }
                ))
                .frame(minHeight: 140)
                .padding(8)
                .background(Color.black.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var transcriptionStatusCard: some View {
        let status = appModel.transcriptionSetupStatus

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(status.title)
                    .font(.headline)

                Text(statusBadgeText(for: status))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(statusColor(for: status).opacity(0.16))
                    .foregroundStyle(statusColor(for: status))
                    .clipShape(Capsule())
            }

            Text(status.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Active source: \(status.activeSourceLabel)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(status.detailLines, id: \.self) { line in
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if appModel.isInstallingManagedTranscription {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("LoqBar is updating the managed transcription setup for this Mac.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func settingsField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }

    private func infoCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func infoText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func statusColor(for status: TranscriptionSetupStatus) -> Color {
        switch status.badgeColorName {
        case "green":
            return .green
        case "red":
            return .red
        default:
            return .orange
        }
    }

    private func statusBadgeText(for status: TranscriptionSetupStatus) -> String {
        switch status.state {
        case .readyExternal, .readyManaged:
            return "Ready"
        case .managedModelNeedsInstall, .managedRuntimeNeedsInstall:
            return "Action Needed"
        case .brokenExternal:
            return "Broken"
        case .notConfigured, .incompleteExternal:
            return "Setup Needed"
        }
    }

    private var cleanupStatusText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let lastRunText = appModel.settings.lastCleanupAt.map { formatter.string(from: $0) } ?? "Not run yet"
        let summary = appModel.settings.lastCleanupSummary ?? "LoqBar has not run cleanup yet."
        return "Last run: \(lastRunText)\n\(summary)"
    }

    private var modelQualityGuidanceText: String {
        let identifier = appModel.settings.normalizedTranscriptionModelIdentifier

        if let suggestion = TranscriptionModelSuggestion.allCases.first(where: { $0.identifier == identifier }) {
            let recommendation = suggestion.isRecommendedForCalls
                ? "This is a good model family to try for call recordings."
                : "This model is fine for fast drafts, but it is often too weak for noisy or split-source call audio."

            return """
            Current model: \(suggestion.title) (`\(suggestion.identifier)`)
            \(suggestion.summary)
            Expected managed download size: \(suggestion.approximateDownloadSize).
            \(recommendation)
            """
        }

        if identifier.isEmpty {
            return """
            No model identifier is set yet.
            For call recordings, start with `small` if you want a better balance of speed and accuracy than `base`.
            """
        }

        return """
        Current model: `\(appModel.settings.transcriptionModelIdentifier)`
        LoqBar will use this identifier as configured. For call recordings, `small` or `medium` usually produce better results than `base`.
        """
    }

    private var managedInstallActionTitle: String {
        switch appModel.transcriptionSetupStatus.state {
        case .readyManaged:
            return "Reinstall Managed Setup"
        case .managedModelNeedsInstall:
            return "Install Selected Model"
        case .managedRuntimeNeedsInstall:
            return "Repair Managed Setup"
        case .readyExternal:
            return "Refresh Managed Setup"
        case .notConfigured, .incompleteExternal, .brokenExternal:
            return "Install Managed Setup"
        }
    }

    private func pathField(
        text: Binding<String>,
        placeholder: String,
        chooseLabel: String,
        secondaryLabel: String? = nil,
        chooseAction: @escaping () -> Void,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
            Button(chooseLabel) {
                chooseAction()
            }
            .buttonStyle(.bordered)

            if let secondaryLabel, let secondaryAction {
                Button(secondaryLabel) {
                    secondaryAction()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
