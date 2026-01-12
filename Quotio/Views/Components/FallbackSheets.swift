//
//  FallbackSheets.swift
//  Quotio - Model Fallback Configuration
//

import SwiftUI

// MARK: - Add Virtual Model Sheet

struct VirtualModelSheet: View {
    let virtualModel: VirtualModel?
    let onSave: (String) -> Void
    let onDismiss: () -> Void

    @State private var modelName: String = ""
    @State private var showValidationError = false

    var isEditing: Bool { virtualModel != nil }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: isEditing ? "pencil.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(isEditing ? .blue : .green)

                Text(isEditing ? "fallback.editVirtualModel".localized() : "fallback.addVirtualModel".localized())
                    .font(.title2)
                    .fontWeight(.bold)

                Text("fallback.virtualModelDescription".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("fallback.virtualModelName".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)

                TextField("fallback.virtualModelPlaceholder".localized(), text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { validateAndSave() }

                if showValidationError && modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("fallback.modelNameRequired".localized())
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 16) {
                Button("action.cancel".localized(), role: .cancel) { onDismiss() }
                    .buttonStyle(.bordered)

                Button { validateAndSave() } label: {
                    Label(isEditing ? "fallback.update".localized() : "fallback.create".localized(), systemImage: isEditing ? "pencil" : "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(40)
        .frame(width: 480)
        .onAppear { modelName = virtualModel?.name ?? "" }
    }

    private func validateAndSave() {
        let trimmedName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            showValidationError = true
            return
        }

        onSave(trimmedName)
        onDismiss()
    }
}

// MARK: - Add Fallback Entry Sheet

struct AddFallbackEntrySheet: View {
    let virtualModelId: UUID
    let existingEntries: [FallbackEntry]
    let availableModels: [AvailableModel]
    let onAdd: (AIProvider, String) -> Void
    let onDismiss: () -> Void

    @State private var selectedModelKey: String = ""
    @State private var showValidationError = false

    private func modelKey(_ model: AvailableModel) -> String {
        let provider = providerFromModel(model).rawValue.lowercased()
        let modelId = model.id.lowercased()
        return "\(provider)::\(modelId)"
    }

    private var filteredModels: [AvailableModel] {
        let existingModelKeys = Set(existingEntries.map { entry in
            "\(entry.provider.rawValue.lowercased())::\(entry.modelId.lowercased())"
        })
        return availableModels.filter { model in
            model.provider.lowercased() != "fallback" &&
            !existingModelKeys.contains(modelKey(model))
        }
    }

    private var selectedModel: AvailableModel? {
        filteredModels.first { modelKey($0) == selectedModelKey }
    }

    private func providerFromModel(_ model: AvailableModel) -> AIProvider {
        let providerName = model.provider.lowercased()
        let modelId = model.id.lowercased()

        if providerName == "copilot" {
            return .copilot
        }
        if let provider = AIProvider.allCases.first(where: { $0.rawValue.lowercased() == providerName }) {
            return provider
        }

        for provider in AIProvider.allCases {
            let providerKey = provider.rawValue.lowercased()
            if modelId.hasPrefix(providerKey + "-") || modelId.hasPrefix(providerKey + "_") {
                return provider
            }
        }

        if modelId.contains("kiro") {
            return .kiro
        } else if modelId.contains("gemini") {
            return .gemini
        } else if modelId.contains("copilot") {
            return .copilot
        } else if modelId.contains("codex") {
            return .codex
        }

        return .claude
    }

    private var isValidEntry: Bool {
        !selectedModelKey.isEmpty && selectedModel != nil
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("fallback.addFallbackEntry".localized())
                    .font(.title2)
                    .fontWeight(.bold)

                Text("fallback.addEntryDescription".localized())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("fallback.modelId".localized())
                    .font(.subheadline)
                    .fontWeight(.medium)

                if filteredModels.isEmpty {
                    Text("fallback.noModelsHint".localized())
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.vertical, 8)
                } else {
                    Picker("", selection: $selectedModelKey) {
                        Text("fallback.selectModelPlaceholder".localized())
                            .tag("")

                        let providers = Set(filteredModels.map { $0.provider }).sorted()

                        ForEach(providers, id: \.self) { provider in
                            Section(header: Text(provider.capitalized)) {
                                ForEach(filteredModels.filter { $0.provider == provider }) { model in
                                    Text(model.displayName)
                                        .tag(modelKey(model))
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }

                if showValidationError && !isValidEntry {
                    Text("fallback.entryRequired".localized())
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if let model = selectedModel {
                    HStack(spacing: 8) {
                        let provider = providerFromModel(model)
                        ProviderIcon(provider: provider, size: 16)
                        Text(provider.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("→")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(model.id)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: 400)

            HStack(spacing: 16) {
                Button("action.cancel".localized(), role: .cancel) { onDismiss() }
                    .buttonStyle(.bordered)

                Button {
                    if isValidEntry, let model = selectedModel {
                        let provider = providerFromModel(model)
                        onAdd(provider, model.id)
                        onDismiss()
                    } else {
                        showValidationError = true
                    }
                } label: {
                    Label("fallback.addEntry".localized(), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidEntry)
            }
        }
        .padding(40)
        .frame(width: 480)
    }
}

// MARK: - UUID Extension for Sheet Binding

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
