import SwiftUI

private enum SessionHistoryModeFilter: String, CaseIterable, Identifiable {
    case all
    case call
    case localMeeting

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "All Modes"
        case .call:
            return "Call"
        case .localMeeting:
            return "Local Meeting"
        }
    }
}

private enum SessionHistoryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case completed
    case transcriptionPending
    case failed

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "All Statuses"
        case .completed:
            return "Completed"
        case .transcriptionPending:
            return "Pending"
        case .failed:
            return "Failed"
        }
    }
}

struct SessionHistoryView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var searchText = ""
    @State private var showFilters = false
    @State private var selectedModeFilter: SessionHistoryModeFilter = .all
    @State private var selectedStatusFilter: SessionHistoryStatusFilter = .all
    @State private var useStartDateFilter = false
    @State private var useEndDateFilter = false
    @State private var startDateFilter = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var endDateFilter = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerCard

                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(filteredSessions) { session in
                            NavigationLink {
                                SessionDetailView(sessionID: session.id)
                                    .environmentObject(appModel)
                            } label: {
                                SessionRow(session: session)
                            }
                            .buttonStyle(.plain)
                        }

                        if filteredSessions.isEmpty {
                            emptyStateCard
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 40)
                .frame(maxWidth: 980, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Recent Sessions")
        }
        .onAppear {
            appModel.bringAuxiliaryWindowToFront(titleContains: "Recent Sessions")
        }
        .onDisappear {
            appModel.restoreMenuBarPresentationIfPossible()
        }
    }

    private var filteredSessions: [SessionRecord] {
        appModel.sessions.filter { session in
            matchesModeFilter(session) &&
            matchesStatusFilter(session) &&
            matchesDateFilter(session) &&
            matchesSearch(session)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Sessions")
                .font(.largeTitle.weight(.semibold))
            Text("Review completed captures, spot pending transcription work, and jump into speaker labeling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Search title, notes, transcript, or participants", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.top, 6)

            Button {
                showFilters.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    Text("Filters")
                        .font(.subheadline.weight(.semibold))

                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    if !activeFilterSummary.isEmpty {
                        Text(activeFilterSummary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: showFilters ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showFilters {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Picker("Mode", selection: $selectedModeFilter) {
                            ForEach(SessionHistoryModeFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220, alignment: .leading)

                        Picker("Status", selection: $selectedStatusFilter) {
                            ForEach(SessionHistoryStatusFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Toggle("From", isOn: $useStartDateFilter)
                                .toggleStyle(.checkbox)
                                .frame(width: 70, alignment: .leading)

                            DatePicker(
                                "From date",
                                selection: $startDateFilter,
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                            .disabled(!useStartDateFilter)
                        }

                        HStack(spacing: 12) {
                            Toggle("To", isOn: $useEndDateFilter)
                                .toggleStyle(.checkbox)
                                .frame(width: 70, alignment: .leading)

                            DatePicker(
                                "To date",
                                selection: $endDateFilter,
                                displayedComponents: [.date]
                            )
                            .labelsHidden()
                            .disabled(!useEndDateFilter)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No Matching Sessions")
                .font(.title3.weight(.semibold))
            Text("Try a broader search term or reset one of the filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func matchesModeFilter(_ session: SessionRecord) -> Bool {
        switch selectedModeFilter {
        case .all:
            return true
        case .call:
            return session.captureMode == .call
        case .localMeeting:
            return session.captureMode == .localMeeting
        }
    }

    private func matchesStatusFilter(_ session: SessionRecord) -> Bool {
        switch selectedStatusFilter {
        case .all:
            return true
        case .completed:
            return session.status == .completed && !session.isTranscriptionPending
        case .transcriptionPending:
            return session.isTranscriptionPending
        case .failed:
            return session.status == .failed
        }
    }

    private func matchesDateFilter(_ session: SessionRecord) -> Bool {
        let sessionDate = session.startedAt

        if useStartDateFilter {
            let startOfDay = Calendar.current.startOfDay(for: startDateFilter)
            guard sessionDate >= startOfDay else { return false }
        }

        if useEndDateFilter {
            guard let endOfDay = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: endDateFilter)) else {
                return false
            }
            guard sessionDate <= endOfDay else { return false }
        }

        return true
    }

    private func matchesSearch(_ session: SessionRecord) -> Bool {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return true }

        let participantText = session.aliasMapping.values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")
        let transcriptText = transcriptSearchText(for: session)
        let haystack = [
            session.title.lowercased(),
            session.notes.lowercased(),
            session.captureMode.title.lowercased(),
            session.displayStatusTitle.lowercased(),
            participantText,
            transcriptText
        ].joined(separator: "\n")

        return haystack.contains(trimmedQuery)
    }

    private func transcriptSearchText(for session: SessionRecord) -> String {
        guard let transcriptPath = session.transcriptPath,
              let markdown = try? String(contentsOfFile: transcriptPath, encoding: .utf8) else {
            return ""
        }

        return markdown
            .components(separatedBy: "# Transcript")
            .dropFirst()
            .joined(separator: "# Transcript")
            .components(separatedBy: "# Analysis Notes")
            .first?
            .lowercased() ?? ""
    }

    private var activeFilterCount: Int {
        var count = 0
        if selectedModeFilter != .all { count += 1 }
        if selectedStatusFilter != .all { count += 1 }
        if useStartDateFilter { count += 1 }
        if useEndDateFilter { count += 1 }
        return count
    }

    private var activeFilterSummary: String {
        var parts: [String] = []

        if selectedModeFilter != .all {
            parts.append(selectedModeFilter.title)
        }
        if selectedStatusFilter != .all {
            parts.append(selectedStatusFilter.title)
        }
        if useStartDateFilter || useEndDateFilter {
            parts.append("Date")
        }

        return parts.joined(separator: " · ")
    }
}

private struct SessionRow: View {
    let session: SessionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Text(session.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .top, spacing: 18) {
                    sessionMetaLabel("Started", value: startedAtText)
                    sessionMetaLabel("Duration", value: durationText)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                statusBadge
                Text(session.captureMode.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !participantAliases.isEmpty {
                    participantAliasRow
                }
            }

            if !session.notes.isEmpty {
                Text(session.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var statusBadge: some View {
        Text(session.displayStatusTitle)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.16))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private func sessionMetaLabel(_ title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var participantAliasRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(participantAliases, id: \.self) { alias in
                    Text(alias)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var participantAliases: [String] {
        session.aliasMapping.values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private var startedAtText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: session.startedAt)
    }

    private var durationText: String {
        let totalSeconds = max(session.durationSeconds, 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        }

        if minutes > 0 {
            return String(format: "%dm %02ds", minutes, seconds)
        }

        return "\(seconds)s"
    }

    private var statusColor: Color {
        if session.isTranscriptionPending {
            return .orange
        }

        switch session.status {
        case .idle:
            return .secondary
        case .recording:
            return .red
        case .processing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}
