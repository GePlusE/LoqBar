import Foundation

struct UpdateCheckService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func checkForUpdates(
        currentVersion: AppVersion,
        configuration: AppReleaseFeedConfiguration
    ) async -> UpdateCheckResult {
        guard let feedURL = configuration.feedURL else {
            return .notConfigured
        }

        do {
            let (data, response) = try await session.data(from: feedURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                return .failed("LoqBar could not load the latest release information right now.")
            }

            let release = try decodeRelease(
                data: data,
                feedURL: feedURL,
                fallbackReleasePageURL: configuration.releasePageURL
            )

            if currentVersion.isOlder(than: release.version) {
                return .updateAvailable(release)
            }

            return .upToDate
        } catch {
            return .failed("LoqBar could not check for updates: \(error.localizedDescription)")
        }
    }

    private func decodeRelease(
        data: Data,
        feedURL: URL,
        fallbackReleasePageURL: URL?
    ) throws -> AvailableAppUpdate {
        if feedURL.host == "api.github.com" {
            let githubRelease = try JSONDecoder.githubDecoder.decode(GitHubLatestRelease.self, from: data)
            let normalizedVersion = githubRelease.tagName
                .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let preferredAsset = githubRelease.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) ??
                githubRelease.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) ??
                githubRelease.assets.first

            return AvailableAppUpdate(
                version: AppVersion(marketingVersion: normalizedVersion.nilIfEmpty ?? githubRelease.tagName, buildNumber: nil),
                title: githubRelease.name?.nilIfEmpty ?? "LoqBar \(normalizedVersion)",
                downloadURL: preferredAsset?.downloadURL,
                releasePageURL: githubRelease.htmlURL ?? fallbackReleasePageURL,
                publishedAt: githubRelease.publishedAt,
                notes: githubRelease.body?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
        }

        let manifest = try JSONDecoder.githubDecoder.decode(ReleaseManifest.self, from: data)
        return AvailableAppUpdate(
            version: AppVersion(marketingVersion: manifest.version, buildNumber: manifest.build),
            title: manifest.title?.nilIfEmpty ?? "LoqBar \(manifest.version)",
            downloadURL: manifest.downloadURL,
            releasePageURL: manifest.releasePageURL ?? fallbackReleasePageURL,
            publishedAt: manifest.publishedAt,
            notes: manifest.notes?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }
}

private struct ReleaseManifest: Decodable {
    let version: String
    let build: String?
    let title: String?
    let downloadURL: URL?
    let releasePageURL: URL?
    let publishedAt: Date?
    let notes: String?

    private enum CodingKeys: String, CodingKey {
        case version
        case build
        case title
        case downloadURL = "download_url"
        case releasePageURL = "release_page_url"
        case publishedAt = "published_at"
        case notes
    }
}

private struct GitHubLatestRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: URL?
    let body: String?
    let publishedAt: Date?
    let assets: [GitHubAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case body
        case publishedAt = "published_at"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let downloadURL: URL?

    private enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}

private extension JSONDecoder {
    static let githubDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
