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

        let result = await loader.refreshRules()
        if let refreshedRules = result.rules {
            rules = refreshedRules
        }

        return result.status
    }

    func refetchRulesManually() async -> RuleRefreshStatus {
        let result = await loader.refreshRules()
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

private struct SourceSelection {
    let txt: String?
    let jsonData: Data?
    let usedRemoteTXT: Bool
    let usedRemoteJSON: Bool
    let errors: [String]
}

private struct RemoteTextFetchResult {
    let text: String?
    let error: String?
}

private struct RemoteDataFetchResult {
    let data: Data?
    let error: String?
}

private final class RulesLoader {
    private let fileManager = FileManager.default
    private let removeParamPrefix = "$removeparam="
    private let regexMetaCharacters = CharacterSet(charactersIn: "\\^$.*+?()[]{}|")

    private let txtURL = URL(string: "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy-removeparam.txt")!
    private let jsonURL = URL(string: "https://gitlab.com/ClearURLs/rules/-/raw/master/data.min.json")!

    func loadBootstrapRules() -> BootstrapLoadResult {
        if let cached = loadCachedRules() {
            return BootstrapLoadResult(rules: cached, loadedFromCache: true)
        }

        if let parsedFromCachedRaw = parseRules(txt: cachedTXTString(), jsonData: cachedJSONData()) {
            saveRulesToCache(parsedFromCachedRaw)
            return BootstrapLoadResult(rules: parsedFromCachedRaw, loadedFromCache: true)
        }

        if let parsedFromAssets = parseRules(txt: assetTXTString(), jsonData: assetJSONData()) {
            saveRulesToCache(parsedFromAssets)
            return BootstrapLoadResult(rules: parsedFromAssets, loadedFromCache: false)
        }

        return BootstrapLoadResult(rules: .empty, loadedFromCache: false)
    }

    func refreshRules() async -> RefreshResult {
        let selection = await fetchRuleSourcesWithFallback()

        let parsed: URLCleaningRules
        let usedRemoteTXT: Bool
        let usedRemoteJSON: Bool
        var combinedErrors = selection.errors

        if let selectedParsed = parseRules(txt: selection.txt, jsonData: selection.jsonData) {
            parsed = selectedParsed
            usedRemoteTXT = selection.usedRemoteTXT
            usedRemoteJSON = selection.usedRemoteJSON
        } else if let fallbackParsed = parseRules(txt: cachedTXTString() ?? assetTXTString(), jsonData: cachedJSONData() ?? assetJSONData()) {
            parsed = fallbackParsed
            usedRemoteTXT = false
            usedRemoteJSON = false
            combinedErrors.append("Remote parse failed; used cached/assets fallback.")
        } else {
            let failureMessage = "Rule refresh failed; using existing in-memory rules."
            logErrors(combinedErrors + [failureMessage])
            return RefreshResult(
                rules: nil,
                status: RuleRefreshStatus(
                    message: failureMessage,
                    usedRemoteTXT: selection.usedRemoteTXT,
                    usedRemoteJSON: selection.usedRemoteJSON,
                    hadErrors: true
                )
            )
        }

        saveRulesToCache(parsed)
        if !combinedErrors.isEmpty {
            logErrors(combinedErrors)
        }

        let message: String
        if usedRemoteTXT && usedRemoteJSON {
            message = "Rules updated from remote sources."
        } else if usedRemoteTXT || usedRemoteJSON {
            message = "Rules refreshed with partial fallback."
        } else {
            message = "Rules refreshed from cache/assets fallback."
        }

        return RefreshResult(
            rules: parsed,
            status: RuleRefreshStatus(
                message: message,
                usedRemoteTXT: usedRemoteTXT,
                usedRemoteJSON: usedRemoteJSON,
                hadErrors: !combinedErrors.isEmpty
            )
        )
    }

    private func fetchRuleSourcesWithFallback() async -> SourceSelection {
        async let remoteTXT = fetchRemoteText(from: txtURL)
        async let remoteJSON = fetchRemoteData(from: jsonURL)

        let txtResult = await remoteTXT
        let jsonResult = await remoteJSON

        var errors: [String] = []

        var txt = txtResult.text
        var usedRemoteTXT = txt != nil
        if txt == nil {
            if let error = txtResult.error {
                errors.append(error)
            }
            txt = cachedTXTString() ?? assetTXTString()
            usedRemoteTXT = false
        } else if let text = txt {
            saveRemoteTXTCache(text)
        }

        var jsonData = jsonResult.data
        var usedRemoteJSON = jsonData != nil
        if jsonData == nil {
            if let error = jsonResult.error {
                errors.append(error)
            }
            jsonData = cachedJSONData() ?? assetJSONData()
            usedRemoteJSON = false
        } else if let data = jsonData {
            saveRemoteJSONCache(data)
        }

        return SourceSelection(
            txt: txt,
            jsonData: jsonData,
            usedRemoteTXT: usedRemoteTXT,
            usedRemoteJSON: usedRemoteJSON,
            errors: errors
        )
    }

    private func fetchRemoteText(from url: URL) async -> RemoteTextFetchResult {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return RemoteTextFetchResult(text: nil, error: "TXT fetch returned non-2xx status.")
            }
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
                return RemoteTextFetchResult(text: nil, error: "TXT fetch returned invalid UTF-8 or empty data.")
            }
            return RemoteTextFetchResult(text: text, error: nil)
        } catch {
            return RemoteTextFetchResult(text: nil, error: "TXT fetch failed: \(error.localizedDescription)")
        }
    }

    private func fetchRemoteData(from url: URL) async -> RemoteDataFetchResult {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return RemoteDataFetchResult(data: nil, error: "JSON fetch returned non-2xx status.")
            }
            guard !data.isEmpty else {
                return RemoteDataFetchResult(data: nil, error: "JSON fetch returned empty data.")
            }
            return RemoteDataFetchResult(data: data, error: nil)
        } catch {
            return RemoteDataFetchResult(data: nil, error: "JSON fetch failed: \(error.localizedDescription)")
        }
    }

    private func parseRules(txt: String?, jsonData: Data?) -> URLCleaningRules? {
        guard let txt, let jsonData else { return nil }

        let general = parseGeneralRules(fromContent: txt)
        let providers = parseProviderRules(fromData: jsonData)

        return URLCleaningRules(
            generalExact: general.exact,
            generalRegex: compileParameterRegexes(general.regexPatterns),
            providers: providers
        )
    }

    private func parseGeneralRules(fromContent content: String) -> (exact: Set<String>, regexPatterns: [String]) {
        var exact = Set<String>()
        var regexPatterns: [String] = []

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("!"), !line.hasPrefix("#") else { continue }
            guard line.hasPrefix(removeParamPrefix) else { continue }

            var token = String(line.dropFirst(removeParamPrefix.count))
            if let commaIndex = token.firstIndex(of: ",") {
                token = String(token[..<commaIndex])
            }
            addToken(token, exact: &exact, regexPatterns: &regexPatterns)
        }

        return (exact, regexPatterns)
    }

    private func parseProviderRules(fromData data: Data) -> [ProviderRule] {
        guard let decoded = try? JSONDecoder().decode(ProviderRoot.self, from: data) else {
            return []
        }

        var rules: [ProviderRule] = []
        for (providerName, provider) in decoded.providers.sorted(by: { $0.key < $1.key }) {
            guard let urlPattern = provider.urlPattern, !urlPattern.isEmpty else {
                continue
            }

            var exact = Set<String>()
            var regexPatterns: [String] = []

            for token in provider.rules ?? [] {
                addToken(token, exact: &exact, regexPatterns: &regexPatterns)
            }
            for token in provider.referralMarketing ?? [] {
                addToken(token, exact: &exact, regexPatterns: &regexPatterns)
            }
            for token in provider.rawRules ?? [] {
                addToken(token, exact: &exact, regexPatterns: &regexPatterns)
            }

            rules.append(
                ProviderRule(
                    name: providerName,
                    urlPattern: compileURLRegex(urlPattern),
                    exactParams: exact,
                    regexParams: compileParameterRegexes(regexPatterns)
                )
            )
        }

        return rules
    }

    private func addToken(_ rawToken: String, exact: inout Set<String>, regexPatterns: inout [String]) {
        var token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        if token.first == "/", token.last == "/", token.count > 2 {
            token = String(token.dropFirst().dropLast())
        }

        if token.contains("=") || token.rangeOfCharacter(from: regexMetaCharacters) != nil {
            regexPatterns.append(token)
        } else {
            exact.insert(token.lowercased())
        }
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

    private func loadCachedRules() -> URLCleaningRules? {
        let url = parsedRulesCacheURL()
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(CachedRulesPayload.self, from: data) else {
            return nil
        }

        let providers = payload.providers.compactMap { provider -> ProviderRule? in
            guard let urlPattern = provider.urlPattern else {
                return nil
            }
            return ProviderRule(
                name: provider.name,
                urlPattern: compileURLRegex(urlPattern),
                exactParams: Set(provider.exactParams),
                regexParams: compileParameterRegexes(provider.regexParams)
            )
        }

        return URLCleaningRules(
            generalExact: Set(payload.generalExact),
            generalRegex: compileParameterRegexes(payload.generalRegex),
            providers: providers
        )
    }

    private func saveRulesToCache(_ rules: URLCleaningRules) {
        let payload = CachedRulesPayload(
            generalExact: Array(rules.generalExact).sorted(),
            generalRegex: rules.generalRegex.map(\.source),
            providers: rules.providers.map { provider in
                CachedRulesPayload.ProviderEntry(
                    name: provider.name,
                    urlPattern: provider.urlPattern?.source,
                    exactParams: Array(provider.exactParams).sorted(),
                    regexParams: provider.regexParams.map(\.source)
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }

        let url = parsedRulesCacheURL()
        let directory = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Cache is optional; ignore failures.
        }
    }

    private func cachedTXTString() -> String? {
        try? String(contentsOf: remoteTXTCacheURL(), encoding: .utf8)
    }

    private func cachedJSONData() -> Data? {
        try? Data(contentsOf: remoteJSONCacheURL())
    }

    private func saveRemoteTXTCache(_ value: String) {
        writeCacheData(Data(value.utf8), to: remoteTXTCacheURL())
    }

    private func saveRemoteJSONCache(_ value: Data) {
        writeCacheData(value, to: remoteJSONCacheURL())
    }

    private func writeCacheData(_ data: Data, to url: URL) {
        let directory = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Cache is optional; ignore failures.
        }
    }

    private func assetTXTString() -> String? {
        guard let assetURLs = locateAssetFiles() else { return nil }
        return try? String(contentsOf: assetURLs.generalRulesURL, encoding: .utf8)
    }

    private func assetJSONData() -> Data? {
        guard let assetURLs = locateAssetFiles() else { return nil }
        return try? Data(contentsOf: assetURLs.providerRulesURL)
    }

    private func locateAssetFiles() -> AssetURLs? {
        if let resourceURL = Bundle.main.resourceURL,
           let assets = assetURLs(in: resourceURL.appendingPathComponent("assets", isDirectory: true)) {
            return assets
        }

        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        if let assets = searchAssetsUpTree(startingFrom: cwd) {
            return assets
        }

        if let executableURL = Bundle.main.executableURL?.deletingLastPathComponent(),
           let assets = searchAssetsUpTree(startingFrom: executableURL) {
            return assets
        }

        return nil
    }

    private func searchAssetsUpTree(startingFrom root: URL) -> AssetURLs? {
        var current = root
        for _ in 0..<8 {
            if let assets = assetURLs(in: current.appendingPathComponent("assets", isDirectory: true)) {
                return assets
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return nil
    }

    private func assetURLs(in assetDirectory: URL) -> AssetURLs? {
        let txt = assetDirectory.appendingPathComponent("privacy-removeparam.txt")
        let json = assetDirectory.appendingPathComponent("data.min.json")
        guard fileManager.fileExists(atPath: txt.path),
              fileManager.fileExists(atPath: json.path) else {
            return nil
        }
        return AssetURLs(generalRulesURL: txt, providerRulesURL: json)
    }

    private func cacheDirectoryURL() -> URL {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("URLSafeClipboard", isDirectory: true)
    }

    private func parsedRulesCacheURL() -> URL {
        cacheDirectoryURL().appendingPathComponent("parsedRules.json")
    }

    private func remoteTXTCacheURL() -> URL {
        cacheDirectoryURL().appendingPathComponent("privacy-removeparam.txt")
    }

    private func remoteJSONCacheURL() -> URL {
        cacheDirectoryURL().appendingPathComponent("data.min.json")
    }

    private func errorLogURL() -> URL {
        cacheDirectoryURL().appendingPathComponent("error.txt")
    }

    private func logErrors(_ errors: [String]) {
        guard !errors.isEmpty else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let body = errors.map { "\(timestamp) \($0)" }.joined(separator: "\n") + "\n"
        let data = Data(body.utf8)

        let url = errorLogURL()
        let directory = url.deletingLastPathComponent()

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: [.atomic])
            }
        } catch {
            // Logging is optional; ignore failures.
        }
    }
}

private struct AssetURLs {
    let generalRulesURL: URL
    let providerRulesURL: URL
}

private struct ProviderRoot: Decodable {
    let providers: [String: ProviderDefinition]
}

private struct ProviderDefinition: Decodable {
    let urlPattern: String?
    let rules: [String]?
    let referralMarketing: [String]?
    let rawRules: [String]?
}

private struct CachedRulesPayload: Codable {
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
