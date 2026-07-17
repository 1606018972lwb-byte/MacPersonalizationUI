import AppKit
import CryptoKit
import Foundation

struct UpdateRelease {
    enum Source: String {
        case github = "GitHub"
        case gitee = "Gitee"
    }

    let source: Source
    let version: String
    let pageURL: URL
    let downloadURL: URL?
    let expectedSHA256: String?
}

/// 同时查询 GitHub 与 Gitee Release，并在满足安全校验时执行后台更新。
final class UpdateManager {
    private struct ReleasePayload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL?

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: URL?
        let body: String?
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
            case assets
        }
    }

    private struct Endpoint {
        let source: UpdateRelease.Source
        let url: URL
        let fallbackPageURL: URL
    }

    private let appSettings: AppSettings
    private let session: URLSession
    private var fallbackTimer: Timer?
    private(set) var isChecking = false
    private(set) var statusText = "尚未检查更新"
    private(set) var latestRelease: UpdateRelease?

    var onStateChange: (() -> Void)?
    var onUpdateAvailable: ((UpdateRelease) -> Void)?

    init(appSettings: AppSettings, session: URLSession = .shared) {
        self.appSettings = appSettings
        self.session = session
    }

    deinit {
        fallbackTimer?.invalidate()
    }

    func start() {
        guard fallbackTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
        timer.tolerance = 5 * 60
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
        checkIfDue()
    }

    func checkIfDue() {
        guard appSettings.checksForUpdates else {
            return
        }
        if let lastDate = appSettings.lastUpdateCheckDate,
           Date().timeIntervalSince(lastDate) < appSettings.updateInterval.timeInterval {
            return
        }
        checkNow(userInitiated: false)
    }

    func checkNow(userInitiated: Bool = true) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isChecking else {
            return
        }

        isChecking = true
        statusText = "正在同时查询 GitHub 与 Gitee…"
        notifyStateChange()

        let endpoints = [
            Endpoint(
                source: .github,
                url: URL(string: "https://api.github.com/repos/1606018972lwb-byte/MacPersonalizationUI/releases/latest")!,
                fallbackPageURL: URL(string: "https://github.com/1606018972lwb-byte/MacPersonalizationUI/releases")!
            ),
            Endpoint(
                source: .gitee,
                url: URL(string: "https://gitee.com/api/v5/repos/Lwb1151/mac-personel-ui/releases/latest")!,
                fallbackPageURL: URL(string: "https://gitee.com/Lwb1151/mac-personel-ui/releases")!
            )
        ]

        let group = DispatchGroup()
        let resultQueue = DispatchQueue(label: "com.lwb.MacWindowButtons.update-results")
        var releases: [UpdateRelease] = []
        var errors: [String] = []

        for endpoint in endpoints {
            group.enter()
            fetchLatestRelease(from: endpoint) { result in
                resultQueue.sync {
                    switch result {
                    case let .success(release):
                        releases.append(release)
                    case let .failure(error):
                        errors.append("\(endpoint.source.rawValue)：\(error.localizedDescription)")
                    }
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.completeCheck(
                releases: releases,
                errors: errors,
                userInitiated: userInitiated
            )
        }
    }

    func openLatestReleasePage() {
        guard let latestRelease else {
            return
        }
        NSWorkspace.shared.open(latestRelease.pageURL)
    }

    private func fetchLatestRelease(
        from endpoint: Endpoint,
        completion: @escaping (Result<UpdateRelease, Error>) -> Void
    ) {
        var request = URLRequest(url: endpoint.url)
        request.timeoutInterval = 15
        request.setValue("MacWindowButtons", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let data else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(UpdateError.httpStatus(code)))
                return
            }

            do {
                let payload = try JSONDecoder().decode(ReleasePayload.self, from: data)
                let version = payload.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                let dmgAsset = payload.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
                completion(
                    .success(
                        UpdateRelease(
                            source: endpoint.source,
                            version: version,
                            pageURL: payload.htmlURL ?? endpoint.fallbackPageURL,
                            downloadURL: dmgAsset?.browserDownloadURL,
                            expectedSHA256: Self.extractSHA256(from: payload.body)
                        )
                    )
                )
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func completeCheck(
        releases: [UpdateRelease],
        errors: [String],
        userInitiated: Bool
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        isChecking = false
        appSettings.markUpdateCheckCompleted()

        guard let newestVersionRelease = releases.max(by: {
            Self.compareVersions($0.version, $1.version) == .orderedAscending
        }) else {
            statusText = errors.isEmpty
                ? "两个平台均未找到正式发行版。"
                : "检查失败：\(errors.joined(separator: "；"))"
            notifyStateChange()
            return
        }

        // 两个平台可能同时发布相同版本。优先选择同时具有 DMG 和 SHA-256 的来源，
        // 避免其中一个平台资料不完整时无谓阻断安全自动更新。
        let newestRelease = releases
            .filter {
                Self.compareVersions($0.version, newestVersionRelease.version) == .orderedSame
            }
            .max { Self.installabilityScore($0) < Self.installabilityScore($1) }
            ?? newestVersionRelease

        let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
        guard Self.compareVersions(currentVersion, newestRelease.version) == .orderedAscending else {
            latestRelease = nil
            statusText = "当前已是最新版本（\(currentVersion)）。"
            if !errors.isEmpty {
                statusText += " 另一来源暂不可用。"
            }
            notifyStateChange()
            return
        }

        latestRelease = newestRelease
        statusText = "发现 \(newestRelease.version)，来源：\(newestRelease.source.rawValue)。"
        notifyStateChange()

        if appSettings.automaticallyInstallsUpdates {
            installAutomatically(newestRelease)
        } else if appSettings.checksForUpdates || userInitiated {
            onUpdateAvailable?(newestRelease)
        }
    }

    private func installAutomatically(_ release: UpdateRelease) {
        guard let downloadURL = release.downloadURL else {
            statusText = "发行版没有 DMG，已阻止自动安装。"
            notifyStateChange()
            onUpdateAvailable?(release)
            return
        }
        guard let expectedHash = release.expectedSHA256 else {
            statusText = "发行版缺少 SHA-256，已阻止自动安装。"
            notifyStateChange()
            onUpdateAvailable?(release)
            return
        }

        statusText = "正在后台下载 \(release.version)…"
        notifyStateChange()
        session.downloadTask(with: downloadURL) { [weak self] temporaryURL, _, error in
            guard let self else {
                return
            }
            if let error {
                self.finishAutomaticInstall(with: "自动下载失败：\(error.localizedDescription)")
                return
            }
            guard let temporaryURL else {
                self.finishAutomaticInstall(with: "自动下载失败：没有收到安装包。")
                return
            }

            do {
                let actualHash = try Self.sha256(of: temporaryURL)
                guard actualHash.caseInsensitiveCompare(expectedHash) == .orderedSame else {
                    throw UpdateError.checksumMismatch
                }
                try self.prepareAndInstall(dmgURL: temporaryURL, release: release)
            } catch {
                self.finishAutomaticInstall(with: "自动安装已停止：\(error.localizedDescription)")
            }
        }.resume()
    }

    private func prepareAndInstall(dmgURL: URL, release: UpdateRelease) throws {
        let attachData = try runProcess(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", "-nobrowse", "-readonly", "-plist", dmgURL.path]
        )
        let plist = try PropertyListSerialization.propertyList(
            from: attachData,
            options: [],
            format: nil
        ) as? [String: Any]
        let entities = plist?["system-entities"] as? [[String: Any]]
        guard let mountPath = entities?.compactMap({ $0["mount-point"] as? String }).last else {
            throw UpdateError.mountFailed
        }
        let mountURL = URL(fileURLWithPath: mountPath)
        defer {
            _ = try? runProcess(
                executable: "/usr/bin/hdiutil",
                arguments: ["detach", mountPath]
            )
        }

        let newAppURL = mountURL.appendingPathComponent("MacWindowButtons.app")
        let newBundle = Bundle(url: newAppURL)
        guard newBundle?.bundleIdentifier == Bundle.main.bundleIdentifier,
              newBundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                == release.version else {
            throw UpdateError.invalidApplication
        }
        _ = try runProcess(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", newAppURL.path]
        )

        let currentAppURL = Bundle.main.bundleURL
        let parentURL = currentAppURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentURL.path) else {
            throw UpdateError.installLocationNotWritable
        }

        let stagedURL = parentURL.appendingPathComponent(".MacWindowButtons-update.app")
        let backupURL = parentURL.appendingPathComponent(".MacWindowButtons-backup.app")
        try? FileManager.default.removeItem(at: stagedURL)
        _ = try runProcess(
            executable: "/usr/bin/ditto",
            arguments: [newAppURL.path, stagedURL.path]
        )

        DispatchQueue.main.async { [weak self] in
            self?.launchInstallHelper(
                currentURL: currentAppURL,
                stagedURL: stagedURL,
                backupURL: backupURL
            )
        }
    }

    private func launchInstallHelper(
        currentURL: URL,
        stagedURL: URL,
        backupURL: URL
    ) {
        let script = """
        sleep 1
        rm -rf "$2"
        mv "$1" "$2" || exit 1
        if mv "$3" "$1"; then
          open "$1"
          rm -rf "$2"
        else
          mv "$2" "$1"
          exit 1
        fi
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            "-c", script, "MacWindowButtons-UpdateHelper",
            currentURL.path, backupURL.path, stagedURL.path
        ]
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            finishAutomaticInstall(with: "无法启动更新助手：\(error.localizedDescription)")
        }
    }

    private func finishAutomaticInstall(with message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusText = message
            self?.notifyStateChange()
        }
    }

    private func notifyStateChange() {
        onStateChange?()
    }

    private func runProcess(executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errorOutput
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(
                data: errorOutput.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw UpdateError.commandFailed(detail)
        }
        return output.fileHandleForReading.readDataToEndOfFile()
    }

    private static func extractSHA256(from text: String?) -> String? {
        guard let text,
              let expression = try? NSRegularExpression(pattern: "(?i)[a-f0-9]{64}"),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return String(text[range]).lowercased()
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: 1024 * 1024)
            guard !data.isEmpty else {
                return false
            }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        for index in 0..<max(left.count, right.count) {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func installabilityScore(_ release: UpdateRelease) -> Int {
        (release.downloadURL == nil ? 0 : 1) + (release.expectedSHA256 == nil ? 0 : 2)
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                Int(component.prefix(while: \.isNumber)) ?? 0
            }
    }
}

private enum UpdateError: LocalizedError {
    case httpStatus(Int)
    case checksumMismatch
    case mountFailed
    case invalidApplication
    case installLocationNotWritable
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .httpStatus(code): "服务器返回 HTTP \(code)"
        case .checksumMismatch: "SHA-256 校验不一致"
        case .mountFailed: "无法挂载 DMG"
        case .invalidApplication: "安装包中的应用身份或版本不正确"
        case .installLocationNotWritable: "当前安装位置不可写，需要手动更新"
        case let .commandFailed(detail): detail.isEmpty ? "系统命令执行失败" : detail
        }
    }
}
