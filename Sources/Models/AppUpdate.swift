import Foundation

struct AppReleaseFeedConfiguration {
    let feedURL: URL?
    let releasePageURL: URL?

    static func fromMainBundle() -> AppReleaseFeedConfiguration {
        let info = Bundle.main.infoDictionary ?? [:]
        let feedURL = (info["LoqBarReleaseFeedURL"] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .flatMap(URL.init(string:))
        let releasePageURL = (info["LoqBarReleasePageURL"] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .flatMap(URL.init(string:))

        return AppReleaseFeedConfiguration(feedURL: feedURL, releasePageURL: releasePageURL)
    }
}

struct AppVersion: Equatable {
    let marketingVersion: String
    let buildNumber: String?

    static func current() -> AppVersion {
        let info = Bundle.main.infoDictionary ?? [:]
        let marketingVersion = (info["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "Development Build"
        let buildNumber = (info["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        return AppVersion(marketingVersion: marketingVersion, buildNumber: buildNumber)
    }

    var displayString: String {
        guard let buildNumber else { return marketingVersion }
        return "\(marketingVersion) (\(buildNumber))"
    }

    func isOlder(than other: AppVersion) -> Bool {
        let versionComparison = marketingVersion.compare(
            other.marketingVersion,
            options: [.numeric]
        )

        if versionComparison == .orderedAscending {
            return true
        }

        if versionComparison == .orderedDescending {
            return false
        }

        guard let buildNumber else { return false }
        guard let otherBuildNumber = other.buildNumber else { return false }
        return buildNumber.compare(otherBuildNumber, options: [.numeric]) == .orderedAscending
    }
}

struct AvailableAppUpdate {
    let version: AppVersion
    let title: String
    let downloadURL: URL?
    let releasePageURL: URL?
    let publishedAt: Date?
    let notes: String?

    var primaryActionURL: URL? {
        downloadURL ?? releasePageURL
    }
}

enum UpdateCheckResult {
    case updateAvailable(AvailableAppUpdate)
    case upToDate
    case notConfigured
    case failed(String)
}

enum UpdateStatusSummary: Equatable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case updateAvailable(version: String, checkedAt: Date)
    case notConfigured
    case failed(message: String)

    var title: String {
        switch self {
        case .idle:
            return "Not checked yet"
        case .checking:
            return "Checking for updates..."
        case let .upToDate(checkedAt):
            return "Up to date as of \(Self.timestampFormatter.string(from: checkedAt))"
        case let .updateAvailable(version, checkedAt):
            return "Version \(version) available as of \(Self.timestampFormatter.string(from: checkedAt))"
        case .notConfigured:
            return "Release feed not configured"
        case let .failed(message):
            return message
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
