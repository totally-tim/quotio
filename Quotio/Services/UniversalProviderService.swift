//
//  UniversalProviderService.swift
//  Quotio
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class UniversalProviderService {
    static let shared = UniversalProviderService()
    
    private(set) var providers: [UniversalProvider] = []
    private(set) var activeState = ActiveProviderState()
    private(set) var isLoading = false
    private(set) var lastError: String?
    
    private let storageKey = "universalProviders"
    private let activeStateKey = "universalProviderActiveState"
    private let keychain = KeychainService.shared
    
    private init() {
        loadProviders()
        loadActiveState()
    }
    
    // MARK: - Provider Access
    
    var enabledProviders: [UniversalProvider] {
        providers.filter(\.isEnabled)
    }
    
    var customProviders: [UniversalProvider] {
        providers.filter { !$0.isBuiltIn }
    }
    
    var builtInProviders: [UniversalProvider] {
        providers.filter(\.isBuiltIn)
    }
    
    func provider(withId id: UUID) -> UniversalProvider? {
        providers.first { $0.id == id }
    }
    
    func activeProvider(for agent: CLIAgent) -> UniversalProvider? {
        guard let id = activeState.activeProviderId(for: agent) else { return nil }
        return provider(withId: id)
    }
    
    // MARK: - CRUD Operations
    
    func addProvider(_ provider: UniversalProvider) {
        var newProvider = provider
        newProvider = UniversalProvider(
            id: provider.id,
            name: provider.name,
            baseURL: provider.baseURL,
            modelId: provider.modelId,
            isBuiltIn: false,
            iconAssetName: provider.iconAssetName,
            color: provider.color,
            supportedAgents: provider.supportedAgents,
            isEnabled: provider.isEnabled,
            createdAt: Date(),
            updatedAt: Date()
        )
        providers.append(newProvider)
        saveProviders()
    }
    
    func updateProvider(_ provider: UniversalProvider) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else {
            lastError = "Provider not found"
            return
        }
        
        var updated = provider
        updated = UniversalProvider(
            id: provider.id,
            name: provider.name,
            baseURL: provider.baseURL,
            modelId: provider.modelId,
            isBuiltIn: providers[index].isBuiltIn,
            iconAssetName: provider.iconAssetName,
            color: provider.color,
            supportedAgents: provider.supportedAgents,
            isEnabled: provider.isEnabled,
            createdAt: providers[index].createdAt,
            updatedAt: Date()
        )
        providers[index] = updated
        saveProviders()
    }
    
    func removeProvider(id: UUID) {
        guard let provider = provider(withId: id), !provider.isBuiltIn else {
            lastError = "Cannot remove built-in provider"
            return
        }
        providers.removeAll { $0.id == id }
        saveProviders()
    }
    
    func toggleProvider(id: UUID) {
        guard let index = providers.firstIndex(where: { $0.id == id }) else { return }
        var provider = providers[index]
        provider = UniversalProvider(
            id: provider.id,
            name: provider.name,
            baseURL: provider.baseURL,
            modelId: provider.modelId,
            isBuiltIn: provider.isBuiltIn,
            iconAssetName: provider.iconAssetName,
            color: provider.color,
            supportedAgents: provider.supportedAgents,
            isEnabled: !provider.isEnabled,
            createdAt: provider.createdAt,
            updatedAt: Date()
        )
        providers[index] = provider
        saveProviders()
    }
    
    // MARK: - Active Provider Management
    
    func setActive(_ provider: UniversalProvider, for agent: CLIAgent) {
        activeState.setActive(provider.id, for: agent)
        saveActiveState()
    }
    
    func clearActive(for agent: CLIAgent) {
        activeState.providerIdByAgent.removeValue(forKey: agent.rawValue)
        saveActiveState()
    }
    
    // MARK: - API Key Management
    
    func storeAPIKey(_ key: String, for provider: UniversalProvider) async throws -> ValidationResult {
        let dummyProvider = AIProvider.codex
        return try await keychain.storeValidated(key: key, for: dummyProvider, account: provider.id.uuidString)
    }
    
    func retrieveAPIKey(for provider: UniversalProvider) async throws -> String? {
        let dummyProvider = AIProvider.codex
        return try await keychain.retrieve(for: dummyProvider, account: provider.id.uuidString)
    }
    
    func deleteAPIKey(for provider: UniversalProvider) async throws {
        let dummyProvider = AIProvider.codex
        try await keychain.delete(for: dummyProvider, account: provider.id.uuidString)
    }
    
    func hasAPIKey(for provider: UniversalProvider) async -> Bool {
        let dummyProvider = AIProvider.codex
        return await keychain.exists(for: dummyProvider, account: provider.id.uuidString)
    }
    
    // MARK: - Persistence
    
    private func loadProviders() {
        isLoading = true
        defer { isLoading = false }
        
        var loaded: [UniversalProvider] = []
        
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                loaded = try decoder.decode([UniversalProvider].self, from: data)
            } catch {
                lastError = "Failed to load providers: \(error.localizedDescription)"
            }
        }
        
        for builtIn in UniversalProvider.builtInProviders {
            if !loaded.contains(where: { $0.id == builtIn.id }) {
                loaded.append(builtIn)
            }
        }
        
        providers = loaded
    }
    
    private func saveProviders() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(providers)
            UserDefaults.standard.set(data, forKey: storageKey)
            lastError = nil
        } catch {
            lastError = "Failed to save providers: \(error.localizedDescription)"
        }
    }
    
    private func loadActiveState() {
        guard let data = UserDefaults.standard.data(forKey: activeStateKey) else { return }
        do {
            activeState = try JSONDecoder().decode(ActiveProviderState.self, from: data)
        } catch {
            lastError = "Failed to load active state: \(error.localizedDescription)"
        }
    }
    
    private func saveActiveState() {
        do {
            let data = try JSONEncoder().encode(activeState)
            UserDefaults.standard.set(data, forKey: activeStateKey)
        } catch {
            lastError = "Failed to save active state: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Migration
    
    func migrateFromCustomProviderService() {
        let customService = CustomProviderService.shared
        
        for customProvider in customService.providers {
            if !providers.contains(where: { $0.id == customProvider.id }) {
                let universal = UniversalProvider(from: customProvider)
                providers.append(universal)
            }
        }
        
        saveProviders()
    }
    
    func reloadProviders() {
        loadProviders()
        loadActiveState()
    }
}
