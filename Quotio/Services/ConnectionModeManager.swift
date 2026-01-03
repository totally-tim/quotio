//
//  ConnectionModeManager.swift
//  Quotio - CLIProxyAPI GUI Wrapper
//
//  DEPRECATED: Mode management moved to OperatingModeManager.
//  This file now contains:
//  - KeychainHelper for secure credential storage
//  - RemoteConnectionHandler for auto-reconnection logic
//

import Foundation
import Security

// MARK: - Connection Mode Manager (DEPRECATED)

/// @available(*, deprecated, message: "Use OperatingModeManager instead for mode management")
/// Kept for backward compatibility - will be removed in future version
@MainActor
@Observable
final class ConnectionModeManager {
    static let shared = ConnectionModeManager()
    
    // MARK: - Observable State (Delegated to OperatingModeManager)
    
    private var operatingModeManager: OperatingModeManager {
        OperatingModeManager.shared
    }
    
    /// Current connection mode - delegates to OperatingModeManager
    var connectionMode: ConnectionMode {
        switch operatingModeManager.currentMode {
        case .monitor, .localProxy:
            return .local
        case .remoteProxy:
            return .remote
        }
    }
    
    /// Current remote configuration - delegates to OperatingModeManager
    var remoteConfig: RemoteConnectionConfig? {
        operatingModeManager.remoteConfig
    }
    
    /// Current connection status - delegates to OperatingModeManager
    var connectionStatus: ConnectionStatus {
        operatingModeManager.connectionStatus
    }
    
    /// Last connection error message
    var lastError: String? {
        operatingModeManager.lastError
    }
    
    // MARK: - Computed Properties (Delegated)
    
    /// Whether currently in remote mode
    var isRemoteMode: Bool { operatingModeManager.isRemoteProxyMode }
    
    /// Whether currently in local mode
    var isLocalMode: Bool { !operatingModeManager.isRemoteProxyMode }
    
    /// Whether a valid remote config exists
    var hasValidRemoteConfig: Bool {
        operatingModeManager.hasValidRemoteConfig
    }
    
    /// The management key for current remote config (from Keychain)
    var remoteManagementKey: String? {
        operatingModeManager.remoteManagementKey
    }
    
    // MARK: - Auto-Reconnection State
    
    /// Number of consecutive connection failures
    private(set) var consecutiveFailures: Int = 0
    
    /// If set, connection is banned until this time (auth failures)
    private(set) var authBanUntil: Date?
    
    /// Whether auto-reconnect is currently scheduled
    private var autoReconnectTask: Task<Void, Never>?
    
    /// Whether connection is currently banned due to auth failures
    var isAuthBanned: Bool {
        guard let banUntil = authBanUntil else { return false }
        return Date() < banUntil
    }
    
    /// Time remaining until auth ban expires (in seconds)
    var authBanTimeRemaining: TimeInterval {
        guard let banUntil = authBanUntil else { return 0 }
        return max(0, banUntil.timeIntervalSinceNow)
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Mode Management (Delegated)
    
    /// Set connection mode - delegates to OperatingModeManager
    func setMode(_ mode: ConnectionMode) {
        switch mode {
        case .local:
            operatingModeManager.setMode(.localProxy)
        case .remote:
            operatingModeManager.setMode(.remoteProxy)
        }
    }
    
    /// Switch to local mode
    func switchToLocal() {
        operatingModeManager.setMode(.localProxy)
    }
    
    /// Switch to remote mode with configuration
    func switchToRemote(config: RemoteConnectionConfig, managementKey: String) {
        operatingModeManager.switchToRemote(config: config, managementKey: managementKey)
    }
    
    // MARK: - Remote Config Management (Delegated)
    
    /// Save remote configuration
    func saveRemoteConfig(_ config: RemoteConnectionConfig) {
        operatingModeManager.saveRemoteConfig(config)
    }
    
    /// Update remote configuration
    func updateRemoteConfig(
        endpointURL: String? = nil,
        displayName: String? = nil,
        verifySSL: Bool? = nil,
        timeoutSeconds: Int? = nil
    ) {
        guard var config = remoteConfig else { return }
        
        if let url = endpointURL {
            config = RemoteConnectionConfig(
                endpointURL: url,
                displayName: config.displayName,
                verifySSL: config.verifySSL,
                timeoutSeconds: config.timeoutSeconds,
                lastConnected: config.lastConnected,
                id: config.id
            )
        }
        if let name = displayName {
            config = RemoteConnectionConfig(
                endpointURL: config.endpointURL,
                displayName: name,
                verifySSL: config.verifySSL,
                timeoutSeconds: config.timeoutSeconds,
                lastConnected: config.lastConnected,
                id: config.id
            )
        }
        if let ssl = verifySSL {
            config = RemoteConnectionConfig(
                endpointURL: config.endpointURL,
                displayName: config.displayName,
                verifySSL: ssl,
                timeoutSeconds: config.timeoutSeconds,
                lastConnected: config.lastConnected,
                id: config.id
            )
        }
        if let timeout = timeoutSeconds {
            config = RemoteConnectionConfig(
                endpointURL: config.endpointURL,
                displayName: config.displayName,
                verifySSL: config.verifySSL,
                timeoutSeconds: timeout,
                lastConnected: config.lastConnected,
                id: config.id
            )
        }
        
        saveRemoteConfig(config)
    }
    
    /// Update management key for current remote config
    func updateManagementKey(_ key: String) {
        guard let config = remoteConfig else { return }
        KeychainHelper.saveManagementKey(key, for: config.id)
    }
    
    /// Clear remote configuration and credentials
    func clearRemoteConfig() {
        operatingModeManager.clearRemoteConfig()
    }
    
    /// Mark last successful connection
    func markConnected() {
        operatingModeManager.markConnected()
        consecutiveFailures = 0
        authBanUntil = nil
    }
    
    /// Mark connection status with failure tracking
    func setConnectionStatus(_ status: ConnectionStatus) {
        operatingModeManager.setConnectionStatus(status)
        
        if case .error = status {
            consecutiveFailures += 1
            
            // Check for auth ban condition (5 failures = 30min ban per CLIProxyAPI docs)
            if consecutiveFailures >= 5 {
                authBanUntil = Date().addingTimeInterval(30 * 60) // 30 minutes
            }
        } else if case .connected = status {
            consecutiveFailures = 0
            authBanUntil = nil
        }
    }
    
    // MARK: - Auto-Reconnection
    
    /// Calculate backoff delay based on consecutive failures
    private func backoffDelay(for attempt: Int) -> TimeInterval {
        // Exponential backoff: 2, 4, 8, 16, 30 seconds (max 30s)
        let baseDelay: TimeInterval = 2
        let maxDelay: TimeInterval = 30
        let delay = baseDelay * pow(2, Double(min(attempt - 1, 4)))
        return min(delay, maxDelay)
    }
    
    /// Schedule auto-reconnection with exponential backoff
    func scheduleAutoReconnect(onReconnect: @escaping () async -> Void) {
        // Cancel any existing reconnect task
        autoReconnectTask?.cancel()
        
        // Don't reconnect if banned
        guard !isAuthBanned else {
            let remaining = Int(authBanTimeRemaining / 60)
            setConnectionStatus(.error("remote.error.authBanned".localized() + " (\(remaining)m)"))
            return
        }
        
        // Don't auto-reconnect after too many failures
        guard consecutiveFailures < 10 else {
            setConnectionStatus(.error("remote.error.tooManyFailures".localized()))
            return
        }
        
        let delay = backoffDelay(for: consecutiveFailures + 1)
        
        autoReconnectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            
            guard !Task.isCancelled else { return }
            guard connectionStatus != .connected else { return }
            
            await onReconnect()
        }
    }
    
    /// Cancel any pending auto-reconnect
    func cancelAutoReconnect() {
        autoReconnectTask?.cancel()
        autoReconnectTask = nil
    }
    
    /// Reset all failure counters (call after successful manual reconnect or config change)
    func resetFailureCounters() {
        consecutiveFailures = 0
        authBanUntil = nil
        cancelAutoReconnect()
    }
    
    /// Get user-friendly error message for common connection failures
    static func friendlyErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        
        if message.contains("timeout") || message.contains("timed out") {
            return "remote.error.timeout".localized()
        } else if message.contains("ssl") || message.contains("certificate") {
            return "remote.error.sslError".localized()
        } else if message.contains("refused") || message.contains("connection refused") {
            return "remote.error.connectionRefused".localized()
        } else if message.contains("host") || message.contains("dns") || message.contains("resolve") {
            return "remote.error.hostNotFound".localized()
        } else if message.contains("401") || message.contains("unauthorized") {
            return "remote.error.unauthorized".localized()
        } else if message.contains("403") || message.contains("forbidden") {
            return "remote.error.forbidden".localized()
        } else {
            return error.localizedDescription
        }
    }
}

// MARK: - Keychain Helper

/// Helper for secure storage of management keys in macOS Keychain
enum KeychainHelper {
    private static let service = "com.quotio.remote-management"
    
    /// Save management key to Keychain
    static func saveManagementKey(_ key: String, for configId: String) {
        let account = "management-key-\(configId)"
        
        // Delete existing item first
        deleteManagementKey(for: configId)
        
        guard let data = key.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Failed to save management key: \(status)")
        }
    }
    
    /// Get management key from Keychain
    static func getManagementKey(for configId: String) -> String? {
        let account = "management-key-\(configId)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return key
    }
    
    /// Delete management key from Keychain
    static func deleteManagementKey(for configId: String) {
        let account = "management-key-\(configId)"
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    /// Check if management key exists
    static func hasManagementKey(for configId: String) -> Bool {
        getManagementKey(for: configId) != nil
    }
}
