import AppKit
import CryptoKit
import Foundation
import IOKit
import Security

struct LicenseDetails: Equatable {
    let licenseIdentifier: String
    let issuedAt: Date
    let expiresAt: Date?

    var validityDescription: String {
        guard let expiresAt else {
            return "永久授权"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return "有效期至 \(formatter.string(from: expiresAt))"
    }
}

enum LicenseState: Equatable {
    case active(LicenseDetails)
    case missing
    case invalid(String)
    case expired(Date)
    case clockRollback(Date)
    case deviceUnavailable(String)

    var isActive: Bool {
        if case .active = self {
            return true
        }
        return false
    }

    var statusMessage: String {
        switch self {
        case let .active(details):
            details.validityDescription
        case .missing:
            "此设备尚未激活。"
        case let .invalid(message):
            "本地许可证无效：\(message)"
        case let .expired(date):
            "许可证已于 \(Self.format(date))到期。"
        case let .clockRollback(referenceDate):
            "检测到系统时间回拨。请将系统时间恢复到 \(Self.format(referenceDate))之后。"
        case let .deviceUnavailable(message):
            "无法生成加密设备码：\(message)"
        }
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

enum DeviceIdentity {
    private static let productSalt = "MacWindowButtons.DeviceIdentity.v1|"

    static func machineCode() throws -> String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != IO_OBJECT_NULL else {
            throw DeviceIdentityError.platformServiceUnavailable
        }
        defer { IOObjectRelease(service) }

        guard let value = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String,
              !value.isEmpty else {
            throw DeviceIdentityError.platformUUIDUnavailable
        }

        let normalizedUUID = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let digest = SHA256.hash(
            data: Data((productSalt + normalizedUUID).utf8)
        )
        let identifier = digest.prefix(20).map {
            String(format: "%02X", $0)
        }.joined()
        return "MWB1-\(identifier)"
    }
}

private enum DeviceIdentityError: LocalizedError {
    case platformServiceUnavailable
    case platformUUIDUnavailable

    var errorDescription: String? {
        switch self {
        case .platformServiceUnavailable:
            "系统没有提供硬件身份服务"
        case .platformUUIDUnavailable:
            "系统没有提供 IOPlatformUUID"
        }
    }
}

private struct SignedLicensePayload: Decodable {
    let version: Int
    let product: String
    let machine: String
    let issuedAt: Int64
    let expiresAt: Int64
    let licenseIdentifier: String

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case product
        case machine
        case issuedAt = "issued_at"
        case expiresAt = "expires_at"
        case licenseIdentifier = "license_id"
    }
}

private enum LicenseVerifier {
    static let productIdentifier = "com.lwb.MacWindowButtons"
    static let publicKeyBase64 = "A/htc5md2EQNo0HVXe/6RtON4LkzryMvFgmzl30G0dg="
    private static let tokenPrefix = "MWB-L1"

    static func decodeAndVerify(
        _ activationCode: String,
        machineCode: String
    ) throws -> SignedLicensePayload {
        let compactCode = activationCode.components(
            separatedBy: .whitespacesAndNewlines
        ).joined()
        let components = compactCode.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == Substring(tokenPrefix),
              let payloadData = Data(base64URLString: String(components[1])),
              let signatureData = Data(base64URLString: String(components[2])),
              let publicKeyData = Data(base64Encoded: publicKeyBase64) else {
            throw LicenseValidationError.invalidFormat
        }

        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(
                rawRepresentation: publicKeyData
            )
        } catch {
            throw LicenseValidationError.invalidPublicKey
        }
        guard publicKey.isValidSignature(signatureData, for: payloadData) else {
            throw LicenseValidationError.invalidSignature
        }

        let payload: SignedLicensePayload
        do {
            payload = try JSONDecoder().decode(
                SignedLicensePayload.self,
                from: payloadData
            )
        } catch {
            throw LicenseValidationError.invalidPayload
        }
        guard payload.version == 1,
              payload.product == productIdentifier,
              !payload.licenseIdentifier.isEmpty else {
            throw LicenseValidationError.unsupportedLicense
        }
        guard payload.machine == machineCode else {
            throw LicenseValidationError.machineMismatch
        }
        guard payload.issuedAt > 0, payload.expiresAt >= 0 else {
            throw LicenseValidationError.invalidPayload
        }
        return payload
    }
}

private enum LicenseValidationError: LocalizedError {
    case invalidFormat
    case invalidPublicKey
    case invalidSignature
    case invalidPayload
    case unsupportedLicense
    case machineMismatch

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            "激活码格式不正确"
        case .invalidPublicKey:
            "应用内置授权公钥无效"
        case .invalidSignature:
            "激活码签名不正确"
        case .invalidPayload:
            "激活码内容损坏"
        case .unsupportedLicense:
            "激活码不属于当前产品或版本"
        case .machineMismatch:
            "激活码与此设备不匹配"
        }
    }
}

private final class LicenseStorage {
    private let fileManager: FileManager
    private let directoryURL: URL
    private var licenseURL: URL {
        directoryURL.appendingPathComponent("license.dat", isDirectory: false)
    }
    var clockStateURL: URL {
        directoryURL.appendingPathComponent(".clock-state", isDirectory: false)
    }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        directoryURL = (baseURL ?? fileManager.homeDirectoryForCurrentUser)
            .appendingPathComponent(
                LicenseVerifier.productIdentifier,
                isDirectory: true
            )
    }

    func loadActivationCode() -> String? {
        guard let data = try? Data(contentsOf: licenseURL),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func saveActivationCode(_ activationCode: String) throws {
        try ensureDirectoryExists()
        guard let data = activationCode.data(using: .utf8) else {
            throw LicenseStorageError.encodingFailed
        }
        try data.write(to: licenseURL, options: .atomic)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: licenseURL.path
        )
    }

    func ensureDirectoryExists() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }
}

private enum LicenseStorageError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "无法保存激活码"
    }
}

private final class ClockRollbackGuard {
    private static let service = "com.lwb.MacWindowButtons.license-clock"
    private static let account = "maximum-observed-time"
    private static let tolerance: TimeInterval = 5 * 60
    private static let stateFileWriteInterval: TimeInterval = 60
    private static let keychainWriteInterval: TimeInterval = 15 * 60

    private let storage: LicenseStorage
    private let fileManager: FileManager
    private let baselineWallDate: Date
    private let baselineUptime: TimeInterval
    private var keychainTimestamp: TimeInterval?
    private var stateFileTimestamp: TimeInterval?

    init(
        storage: LicenseStorage,
        fileManager: FileManager = .default,
        now: Date = Date(),
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        self.storage = storage
        self.fileManager = fileManager
        baselineWallDate = now
        baselineUptime = uptime
        keychainTimestamp = nil
        stateFileTimestamp = nil
        keychainTimestamp = readKeychain()
        stateFileTimestamp = readStateFile()
    }

    func rollbackReferenceDate(
        now: Date,
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> Date? {
        var references: [Date] = []
        if let persistedTimestamp = maximumPersistedTimestamp(),
           now.timeIntervalSince1970 + Self.tolerance < persistedTimestamp {
            references.append(Date(timeIntervalSince1970: persistedTimestamp))
        }

        let elapsedUptime = uptime - baselineUptime
        if elapsedUptime >= 0 {
            let expectedDate = baselineWallDate.addingTimeInterval(elapsedUptime)
            if now.addingTimeInterval(Self.tolerance) < expectedDate {
                references.append(expectedDate)
            }
        }
        return references.max()
    }

    func record(_ date: Date, forceKeychain: Bool = false) {
        let timestamp = floor(date.timeIntervalSince1970)
        let data = Data(String(format: "%.0f", timestamp).utf8)

        if timestamp >= (stateFileTimestamp ?? 0) + Self.stateFileWriteInterval {
            do {
                try storage.ensureDirectoryExists()
                try data.write(to: storage.clockStateURL, options: .atomic)
                try? fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: storage.clockStateURL.path
                )
                stateFileTimestamp = timestamp
            } catch {
                NSLog(
                    "[MacWindowButtons] 无法保存本地时间状态：%@",
                    error.localizedDescription
                )
            }
        }

        let shouldWriteKeychain = forceKeychain
            || timestamp >= (keychainTimestamp ?? 0) + Self.keychainWriteInterval
        if timestamp > (keychainTimestamp ?? 0), shouldWriteKeychain {
            if writeKeychain(data) {
                keychainTimestamp = timestamp
            }
        }
    }

    private func maximumPersistedTimestamp() -> TimeInterval? {
        [keychainTimestamp, stateFileTimestamp].compactMap { $0 }.max()
    }

    private func readStateFile() -> TimeInterval? {
        guard let data = try? Data(contentsOf: storage.clockStateURL),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return TimeInterval(
            string.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func readKeychain() -> TimeInterval? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return TimeInterval(
            string.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func writeKeychain(_ data: Data) -> Bool {
        let query = keychainQuery()
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecItemNotFound else {
            if updateStatus != errSecSuccess {
                NSLog("[MacWindowButtons] 无法更新时间防回拨钥匙串项：%d", updateStatus)
            }
            return updateStatus == errSecSuccess
        }
        var newItem = query
        newItem[kSecValueData as String] = data
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        if addStatus != errSecSuccess {
            NSLog("[MacWindowButtons] 无法创建时间防回拨钥匙串项：%d", addStatus)
        }
        return addStatus == errSecSuccess
    }

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }
}

final class LicenseManager {
    private static let futureIssueTolerance: TimeInterval = 5 * 60

    private let storage: LicenseStorage
    private let clockGuard: ClockRollbackGuard
    private var activationCode: String?
    private var validationTimer: Timer?
    private var clockChangeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    let machineCode: String?
    private(set) var state: LicenseState
    var onStateChange: ((LicenseState) -> Void)?

    init() {
        let storage = LicenseStorage()
        self.storage = storage
        clockGuard = ClockRollbackGuard(storage: storage)
        activationCode = storage.loadActivationCode()
        do {
            let machineCode = try DeviceIdentity.machineCode()
            self.machineCode = machineCode
            state = .missing
            state = evaluate(
                activationCode: activationCode,
                machineCode: machineCode,
                now: Date()
            )
        } catch {
            machineCode = nil
            state = .deviceUnavailable(error.localizedDescription)
        }
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        guard validationTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        validationTimer = timer
        clockChangeObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSSystemClockDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func stopMonitoring() {
        if state.isActive {
            clockGuard.record(Date(), forceKeychain: true)
        }
        validationTimer?.invalidate()
        validationTimer = nil
        if let clockChangeObserver {
            NotificationCenter.default.removeObserver(clockChangeObserver)
            self.clockChangeObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    func activate(with activationCode: String) throws -> LicenseDetails {
        guard let machineCode else {
            throw LicenseActivationError.rejected(state.statusMessage)
        }
        let newState = evaluate(
            activationCode: activationCode,
            machineCode: machineCode,
            now: Date()
        )
        guard case let .active(details) = newState else {
            throw LicenseActivationError.rejected(newState.statusMessage)
        }
        let compactCode = activationCode.components(
            separatedBy: .whitespacesAndNewlines
        ).joined()
        do {
            try storage.saveActivationCode(compactCode)
        } catch {
            throw LicenseActivationError.storageFailed(error.localizedDescription)
        }
        self.activationCode = compactCode
        setState(newState)
        return details
    }

    func refresh() {
        guard let machineCode else {
            return
        }
        setState(
            evaluate(
                activationCode: activationCode,
                machineCode: machineCode,
                now: Date()
            )
        )
    }

    private func evaluate(
        activationCode: String?,
        machineCode: String,
        now: Date
    ) -> LicenseState {
        guard let activationCode, !activationCode.isEmpty else {
            return .missing
        }

        let payload: SignedLicensePayload
        do {
            payload = try LicenseVerifier.decodeAndVerify(
                activationCode,
                machineCode: machineCode
            )
        } catch {
            return .invalid(error.localizedDescription)
        }

        let issuedAt = Date(timeIntervalSince1970: TimeInterval(payload.issuedAt))
        if now.addingTimeInterval(Self.futureIssueTolerance) < issuedAt {
            return .clockRollback(issuedAt)
        }
        if let rollbackReference = clockGuard.rollbackReferenceDate(now: now) {
            return .clockRollback(rollbackReference)
        }
        let expiresAt = payload.expiresAt == 0
            ? nil
            : Date(timeIntervalSince1970: TimeInterval(payload.expiresAt))
        if let expiresAt, now >= expiresAt {
            return .expired(expiresAt)
        }

        clockGuard.record(now)
        return .active(
            LicenseDetails(
                licenseIdentifier: payload.licenseIdentifier,
                issuedAt: issuedAt,
                expiresAt: expiresAt
            )
        )
    }

    private func setState(_ newState: LicenseState) {
        guard state != newState else {
            return
        }
        state = newState
        onStateChange?(newState)
    }
}

private enum LicenseActivationError: LocalizedError {
    case rejected(String)
    case storageFailed(String)

    var errorDescription: String? {
        switch self {
        case let .rejected(message): message
        case let .storageFailed(message): "保存许可证失败：\(message)"
        }
    }
}

private extension Data {
    init?(base64URLString: String) {
        var value = base64URLString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = value.count % 4
        if remainder != 0 {
            value.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: value)
    }
}
