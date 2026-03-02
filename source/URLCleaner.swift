import Foundation

@MainActor
final class URLCleaner {
    private let loader: RulesLoader
    private var rules: URLCleaningRules
    private var shouldRefetchOnLaunch: Bool

    init() {
        let loader = RulesLoader()
        self.loader = loader
        let bootstrap = loader.loadBootstrapRules()
        self.rules = bootstrap.rules
        self.shouldRefetchOnLaunch = !bootstrap.loadedFromCache
    }

    func cleanedURLStringIfNeeded(from input: String, replaceMode: Bool = false) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host != nil else {
            return nil
        }

        guard let queryItems = components.queryItems, !queryItems.isEmpty else {
            return applyFutureTransforms(to: trimmed)
        }

        let matchingProviders = rules.providers.filter { $0.matches(urlString: trimmed) }

        var outputQueryItems: [URLQueryItem] = []
        outputQueryItems.reserveCapacity(queryItems.count)
        var didMutate = false

        for item in queryItems {
            let normalizedName = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty else {
                didMutate = true
                continue
            }

            let shouldNeutralize = rules.shouldRemoveParameter(
                named: normalizedName,
                matchingProviders: matchingProviders
            )

            if shouldNeutralize {
                if replaceMode {
                    if item.value != "null" || normalizedName != item.name {
                        didMutate = true
                    }
                    outputQueryItems.append(URLQueryItem(name: normalizedName, value: "null"))
                } else {
                    didMutate = true
                }
                continue
            }

            if normalizedName != item.name {
                didMutate = true
                outputQueryItems.append(URLQueryItem(name: normalizedName, value: item.value))
            } else {
                outputQueryItems.append(item)
            }
        }

        guard didMutate else {
            return applyFutureTransforms(to: trimmed)
        }

        components.queryItems = outputQueryItems.isEmpty ? nil : outputQueryItems
        let cleaned = components.url?.absoluteString ?? trimmed
        return applyFutureTransforms(to: cleaned)
    }

    func refreshRulesIfNeededOnLaunch() async -> RuleRefreshStatus? {
        guard shouldRefetchOnLaunch else { return nil }
        shouldRefetchOnLaunch = false

        let result = await loader.refreshRulesFromRepo()
        if let refreshedRules = result.rules {
            rules = refreshedRules
        }
        return result.status
    }

    func refetchRulesManually() async -> RuleRefreshStatus {
        let result = await loader.refreshRulesFromRepo()
        if let refreshedRules = result.rules {
            rules = refreshedRules
        }
        return result.status
    }

    private func applyFutureTransforms(to cleanedURL: String) -> String {
        // Placeholder for future enhancements (AMP unwrapping, redirect decoding, etc).
        cleanedURL
    }
}

struct RuleRefreshStatus {
    let message: String
    let usedRemoteTXT: Bool
    let usedRemoteJSON: Bool
    let hadErrors: Bool
}

private struct URLCleaningRules {
    let generalExact: Set<String>
    let generalRegex: [CompiledRegex]
    let providers: [ProviderRule]

    static let empty = URLCleaningRules(generalExact: [], generalRegex: [], providers: [])

    func shouldRemoveParameter(named parameterName: String, matchingProviders: [ProviderRule]) -> Bool {
        let lowercased = parameterName.lowercased()
        if generalExact.contains(lowercased) || matchesAnyRegex(in: generalRegex, value: parameterName) {
            return true
        }

        for provider in matchingProviders {
            if provider.exactParams.contains(lowercased) {
                return true
            }
            if matchesAnyRegex(in: provider.regexParams, value: parameterName) {
                return true
            }
        }
        return false
    }

    private func matchesAnyRegex(in regexes: [CompiledRegex], value: String) -> Bool {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return regexes.contains { regex in
            regex.regex.firstMatch(in: value, options: [], range: range) != nil
        }
    }
}

private struct ProviderRule {
    let name: String
    let urlPattern: CompiledRegex?
    let exactParams: Set<String>
    let regexParams: [CompiledRegex]

    func matches(urlString: String) -> Bool {
        guard let urlPattern else { return false }
        let range = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
        return urlPattern.regex.firstMatch(in: urlString, options: [], range: range) != nil
    }
}

private struct CompiledRegex {
    let source: String
    let regex: NSRegularExpression
}

private struct BootstrapLoadResult {
    let rules: URLCleaningRules
    let loadedFromCache: Bool
}

private struct RefreshResult {
    let rules: URLCleaningRules?
    let status: RuleRefreshStatus
}

private struct ParsedRulesPayload: Codable {
    struct ProviderEntry: Codable {
        let name: String
        let urlPattern: String?
        let exactParams: [String]
        let regexParams: [String]
    }

    let generalExact: [String]
    let generalRegex: [String]
    let providers: [ProviderEntry]
}

private final class RulesLoader {
    private let fileManager = FileManager.default
    private let defaultRepoURL = "https://raw.githubusercontent.com/jayf0x/url-safe-clipboard/refs/heads/main/assets/parsedRules.json"

    func loadBootstrapRules() -> BootstrapLoadResult {
        if let cachedData = loadCachedParsedRulesData(),
           let cachedRules = parseRules(from: cachedData) {
            return BootstrapLoadResult(rules: cachedRules, loadedFromCache: true)
        }

        if let bundledData = loadBundledParsedRulesData(),
           let bundledRules = parseRules(from: bundledData) {
            saveParsedRulesDataToCache(bundledData)
            return BootstrapLoadResult(rules: bundledRules, loadedFromCache: false)
        }

        return BootstrapLoadResult(rules: .empty, loadedFromCache: false)
    }

    func refreshRulesFromRepo() async -> RefreshResult {
        guard let repoURL = repoParsedRulesURL() else {
            let message = "Refetch failed: missing repo parsedRules URL."
            return refreshFromFallback(messagePrefix: message)
        }

        do {
            let request = URLRequest(url: repoURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 12)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let message = "Refetch failed: repo returned non-2xx response."
                return refreshFromFallback(messagePrefix: message)
            }

            guard let parsed = parseRules(from: data) else {
                let message = "Refetch failed: invalid parsedRules.json format from repo."
                return refreshFromFallback(messagePrefix: message)
            }

            saveParsedRulesDataToCache(data)
            return RefreshResult(
                rules: parsed,
                status: RuleRefreshStatus(
                    message: "Rules updated from repo parsedRules.json.",
                    usedRemoteTXT: true,
                    usedRemoteJSON: true,
                    hadErrors: false
                )
            )
        } catch {
            let message = "Refetch failed: \(error.localizedDescription)"
            return refreshFromFallback(messagePrefix: message)
        }
    }

    private func refreshFromFallback(messagePrefix: String) -> RefreshResult {
        if let cachedData = loadCachedParsedRulesData(),
           let cachedRules = parseRules(from: cachedData) {
            return RefreshResult(
                rules: cachedRules,
                status: RuleRefreshStatus(
                    message: "\(messagePrefix) Using cached rules.",
                    usedRemoteTXT: false,
                    usedRemoteJSON: false,
                    hadErrors: true
                )
            )
        }

        if let bundledData = loadBundledParsedRulesData(),
           let bundledRules = parseRules(from: bundledData) {
            saveParsedRulesDataToCache(bundledData)
            return RefreshResult(
                rules: bundledRules,
                status: RuleRefreshStatus(
                    message: "\(messagePrefix) Using bundled rules.",
                    usedRemoteTXT: false,
                    usedRemoteJSON: false,
                    hadErrors: true
                )
            )
        }

        let finalMessage = "\(messagePrefix) No fallback rules available."
        return RefreshResult(
            rules: nil,
            status: RuleRefreshStatus(
                message: finalMessage,
                usedRemoteTXT: false,
                usedRemoteJSON: false,
                hadErrors: true
            )
        )
    }

    private func parseRules(from data: Data) -> URLCleaningRules? {
        guard let payload = try? JSONDecoder().decode(ParsedRulesPayload.self, from: data) else {
            return nil
        }

        let generalExact = Set(payload.generalExact.map { $0.lowercased() })
        let generalRegex = compileParameterRegexes(payload.generalRegex)

        let providers = payload.providers.compactMap { provider -> ProviderRule? in
            guard let urlPattern = provider.urlPattern,
                  !urlPattern.isEmpty,
                  let compiledURLPattern = compileURLRegex(urlPattern) else {
                return nil
            }

            return ProviderRule(
                name: provider.name,
                urlPattern: compiledURLPattern,
                exactParams: Set(provider.exactParams.map { $0.lowercased() }),
                regexParams: compileParameterRegexes(provider.regexParams)
            )
        }

        return URLCleaningRules(
            generalExact: generalExact,
            generalRegex: generalRegex,
            providers: providers
        )
    }

    private func compileURLRegex(_ pattern: String) -> CompiledRegex? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return CompiledRegex(source: pattern, regex: regex)
    }

    private func compileParameterRegexes(_ patterns: [String]) -> [CompiledRegex] {
        patterns.compactMap { pattern in
            let anchoredPattern = "^(?:\(pattern))$"
            guard let regex = try? NSRegularExpression(pattern: anchoredPattern, options: [.caseInsensitive]) else {
                return nil
            }
            return CompiledRegex(source: pattern, regex: regex)
        }
    }

    private func repoParsedRulesURL() -> URL? {
        let environmentURL = ProcessInfo.processInfo.environment["PUREPASTE_RULES_URL"]
        if let environmentURL, !environmentURL.isEmpty, let url = URL(string: environmentURL) {
            return url
        }

        if let plistURL = Bundle.main.object(forInfoDictionaryKey: "PurePasteParsedRulesURL") as? String,
           !plistURL.isEmpty,
           let url = URL(string: plistURL) {
            return url
        }

        return URL(string: defaultRepoURL)
    }

    private func loadCachedParsedRulesData() -> Data? {
        try? Data(contentsOf: cacheFileURL())
    }

    private func loadBundledParsedRulesData() -> Data? {
        if let resourceURL = Bundle.main.resourceURL {
            let bundledURL = resourceURL
                .appendingPathComponent("assets", isDirectory: true)
                .appendingPathComponent("parsedRules.json")
            if fileManager.fileExists(atPath: bundledURL.path),
               let data = try? Data(contentsOf: bundledURL) {
                return data
            }
        }

        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        var current = cwd
        for _ in 0..<8 {
            let candidate = current
                .appendingPathComponent("assets", isDirectory: true)
                .appendingPathComponent("parsedRules.json")
            if fileManager.fileExists(atPath: candidate.path),
               let data = try? Data(contentsOf: candidate) {
                return data
            }

            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }

        return nil
    }

    private func saveParsedRulesDataToCache(_ data: Data) {
        let url = cacheFileURL()
        let directory = url.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Cache is optional; ignore failures.
        }
    }

    private func cacheFileURL() -> URL {
        cacheDirectoryURL().appendingPathComponent("parsedRules.json")
    }

    private func cacheDirectoryURL() -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let purePaste = base.appendingPathComponent("PurePaste", isDirectory: true)
        let legacy = base.appendingPathComponent("URLSafeClipboard", isDirectory: true)
        migrateLegacyCache(from: legacy, to: purePaste)
        return purePaste
    }

    private func migrateLegacyCache(from oldDir: URL, to newDir: URL) {
        guard fileManager.fileExists(atPath: oldDir.path) else { return }
        guard !fileManager.fileExists(atPath: newDir.path) else { return }

        do {
            try fileManager.createDirectory(at: newDir, withIntermediateDirectories: true)
            let oldParsed = oldDir.appendingPathComponent("parsedRules.json")
            let newParsed = newDir.appendingPathComponent("parsedRules.json")
            if fileManager.fileExists(atPath: oldParsed.path),
               !fileManager.fileExists(atPath: newParsed.path) {
                try fileManager.copyItem(at: oldParsed, to: newParsed)
            }
        } catch {
            // Migration is opportunistic.
        }
    }
}
