import Foundation

struct AppReleaseFeedConfiguration {
    let feedURL: URL?
    let releasePageURL: URL?

    static func fromMainBundle() -> AppReleaseFeedConfiguration {
        let info = Bundle.main.infoDictionary ?? [:]
        let bundleFeedURL = (info["LoqBarReleaseFeedURL"] as? String)
            .flatMap(normalizedURL)
        let bundleReleasePageURL = (info["LoqBarReleasePageURL"] as? String)
            .flatMap(normalizedURL)

        if bundleFeedURL != nil || bundleReleasePageURL != nil {
            return AppReleaseFeedConfiguration(feedURL: bundleFeedURL, releasePageURL: bundleReleasePageURL)
        }

        let environment = ProcessInfo.processInfo.environment
        let envFeedURL = environment["RELEASE_FEED_URL"].flatMap(normalizedURL)
        let envReleasePageURL = environment["RELEASE_PAGE_URL"].flatMap(normalizedURL)

        if envFeedURL != nil || envReleasePageURL != nil {
            return AppReleaseFeedConfiguration(feedURL: envFeedURL, releasePageURL: envReleasePageURL)
        }

        let localFallback = localDevelopmentFallback()
        return AppReleaseFeedConfiguration(feedURL: localFallback.feedURL, releasePageURL: localFallback.releasePageURL)
    }

    private static func localDevelopmentFallback() -> (feedURL: URL?, releasePageURL: URL?) {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidateFiles = [
            currentDirectory.appendingPathComponent("Packaging/release.env"),
            currentDirectory.appendingPathComponent("Packaging/release.env.local")
        ]

        for candidate in candidateFiles {
            guard let content = try? String(contentsOf: candidate, encoding: .utf8) else { continue }
            let values = parseShellExports(from: content)
            let feedURL = values["RELEASE_FEED_URL"].flatMap(normalizedURL)
            let releasePageURL = values["RELEASE_PAGE_URL"].flatMap(normalizedURL)

            if feedURL != nil || releasePageURL != nil {
                return (feedURL, releasePageURL)
            }
        }

        return (nil, nil)
    }

    private static func parseShellExports(from content: String) -> [String: String] {
        content
            .split(whereSeparator: \.isNewline)
            .reduce(into: [:]) { result, rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("export ") else { return }

                let declaration = String(line.dropFirst("export ".count))
                let parts = declaration.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return }

                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

                result[key] = value
            }
    }

    private static func normalizedURL(_ rawValue: String) -> URL? {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            .flatMap(URL.init(string:))
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
