import SwiftData
import SwiftUI

// Pool Settings for ESP-Miner v2.15. The miner keeps up to eight pool slots; the primary and
// fallback are picked from them, and each slot is edited in place below.
struct PoolCatalogView: View {
    var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: PoolCatalogDraft
    @State private var selectedSlotID: Int
    @State private var showErrorAlert: Bool = false

    init(viewModel: SettingsViewModel, initialSelectedSlotID: Int? = nil) {
        self.viewModel = viewModel
        let draft = viewModel.poolCatalog ?? Self.emptyDraft
        _draft = State(initialValue: draft)
        _selectedSlotID = State(initialValue: initialSelectedSlotID ?? draft.primaryPoolID)
    }

    private static let emptyDraft = PoolCatalogDraft(
        slots: [],
        primaryPoolID: 0,
        secondaryPoolID: 1,
        useFallbackStratum: false
    )

    private var selectedSlot: PoolSlotDraft? {
        draft.slot(withID: selectedSlotID)
    }

    private var isSelectedSlotInUse: Bool {
        draft.isSelected(selectedSlotID)
    }

    private var fallbackSlotIsBlank: Bool {
        draft.slot(withID: draft.secondaryPoolID)?.isBlank ?? true
    }

    private var deleteFooterText: String? {
        guard let slot = selectedSlot else { return nil }
        if slot.id == draft.primaryPoolID {
            return
                "\(slot.title) is the primary pool and can't be deleted. Pick a different primary first."
        }
        if slot.id == draft.secondaryPoolID {
            return
                "\(slot.title) is the fallback pool and can't be deleted. Pick a different fallback first."
        }
        return nil
    }

    private func slotBinding(_ keyPath: WritableKeyPath<PoolSlotDraft, String>) -> Binding<String> {
        Binding(
            get: { draft.slot(withID: selectedSlotID)?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let index = draft.slots.firstIndex(where: { $0.id == selectedSlotID }) else {
                    return
                }
                draft.slots[index][keyPath: keyPath] = newValue
            }
        )
    }

    var body: some View {
        Form {
            Section {
                if viewModel.supportsActivePoolSelection {
                    Picker("Active Pool", selection: $draft.useFallbackStratum) {
                        Text("Primary").tag(false)
                        Text("Fallback").tag(true)
                    }
                    .pickerStyle(.menu)
                    // Switching back to Primary stays possible even if the fallback slot is blank.
                    .disabled(fallbackSlotIsBlank && !draft.useFallbackStratum)
                }

                Picker("Primary", selection: $draft.primaryPoolID) {
                    ForEach(draft.slots) { slot in
                        Text(slot.menuLabel).tag(slot.id)
                    }
                }
                .pickerStyle(.menu)

                Picker("Fallback", selection: $draft.secondaryPoolID) {
                    ForEach(draft.slots) { slot in
                        Text(slot.menuLabel).tag(slot.id)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Pool Configuration")
            } footer: {
                if viewModel.supportsActivePoolSelection {
                    Text(
                        fallbackSlotIsBlank
                            ? "Fill in the fallback pool to select it as the active pool."
                            : "Fallback keeps mining on the fallback pool and does not switch back to the primary pool automatically."
                    )
                }
            }
            // Like AxeOS, choosing the other selected slot swaps the two instead of duplicating.
            .onChange(of: draft.primaryPoolID) { previousID, newID in
                if newID == draft.secondaryPoolID {
                    draft.secondaryPoolID = previousID
                }
            }
            .onChange(of: draft.secondaryPoolID) { previousID, newID in
                if newID == draft.primaryPoolID {
                    draft.primaryPoolID = previousID
                }
            }

            Section {
                LabeledContent("Pool") {
                    Menu {
                        Picker("Pool", selection: $selectedSlotID) {
                            ForEach(draft.slots) { slot in
                                Text(slot.menuLabel).tag(slot.id)
                            }
                        }
                        if draft.canAddSlot {
                            Divider()
                            Button {
                                addPool()
                            } label: {
                                Label("Add Pool", systemImage: "plus")
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(selectedSlot?.menuLabel ?? "Choose a pool")
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.footnote.weight(.medium))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Stratum Host".uppercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("NA.lincoin.com", text: slotBinding(\.stratumURL))
                        .keyboardType(.URL)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    Text("Do not include 'stratum+tcp://' or port.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stratum Port".uppercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("3333", text: slotBinding(\.stratumPortString))
                        .keyboardType(.numberPad)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stratum User".uppercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    MonospacedIdentifierEditor(
                        placeholder: "pod256.traxe",
                        text: slotBinding(\.stratumUser)
                    )
                }

                if viewModel.supportsStratumProtocolSettings {
                    StratumProtocolDetailsView(
                        poolTitle: selectedSlot?.title ?? "Pool",
                        protocolValue: slotBinding(\.stratumProtocol),
                        channelType: slotBinding(\.stratumV2ChannelType),
                        authorityPubkey: slotBinding(\.stratumV2AuthorityPubkey)
                    )
                    .padding(.vertical, 4)
                }

                Button("Delete Pool", role: .destructive) {
                    deleteSelectedPool()
                }
                .disabled(isSelectedSlotInUse)
            } header: {
                HStack {
                    Text("Pools")
                    Spacer()
                    Text("\(draft.slots.count) of \(PoolSlotDraft.maximumSlotCount)")
                }
            } footer: {
                if let deleteFooterText {
                    Text(deleteFooterText)
                }
            }

            Section {
                Button("Save") {
                    Task {
                        let success = await viewModel.savePoolCatalog(draft)
                        if success {
                            dismiss()
                        } else {
                            showErrorAlert = true
                        }
                    }
                }
                .disabled(viewModel.isUpdatingPoolConfiguration)

                if viewModel.isUpdatingPoolConfiguration {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } footer: {
                Text(
                    "The miner restarts after saving if the primary, fallback, or active pool changed."
                )
            }
        }
        .navigationTitle("Pool Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reloadDraftFromMiner()
        }
        // Settings can still be loading when the screen opens; take the list once it arrives.
        .onChange(of: viewModel.poolCatalog) { _, _ in
            if draft.slots.isEmpty {
                reloadDraftFromMiner()
            }
        }
        .alert("Save Error", isPresented: $showErrorAlert) {
            Button("OK") {}
        } message: {
            Text(viewModel.poolConfigurationError ?? "An unknown error occurred. Please try again.")
        }
    }

    private func reloadDraftFromMiner() {
        guard let catalog = viewModel.poolCatalog else { return }
        draft = catalog
        if draft.slot(withID: selectedSlotID) == nil {
            selectedSlotID = draft.primaryPoolID
        }
    }

    private func addPool() {
        guard let slot = draft.addSlot() else { return }
        selectedSlotID = slot.id
    }

    private func deleteSelectedPool() {
        guard draft.deleteSlot(withID: selectedSlotID) else { return }
        selectedSlotID = draft.primaryPoolID
    }
}

#if DEBUG
    #Preview("ESP-Miner v2.15 pool slots") {
        let schema = Schema([HistoricalDataPoint.self])
        let container = try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let suiteName = "traxe.poolCatalogPreview"
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.removePersistentDomain(forName: suiteName)
        defaults?.set("192.168.1.100", forKey: "bitaxeIPAddress")
        let viewModel = SettingsViewModel(
            sharedUserDefaults: defaults,
            modelContext: container.mainContext,
            shouldFetchDeviceSettingsOnLoad: false
        )
        viewModel.supportsMultiPoolSettings = true
        viewModel.supportsActivePoolSelection = true
        viewModel.supportsStratumProtocolSettings = true
        var publicPool = PoolSlotDraft(id: 0)
        publicPool.stratumURL = "public-pool.io"
        publicPool.stratumPortString = "3333"
        publicPool.stratumUser = "bc1qpublicpoolpreview.worker1"
        publicPool.stratumProtocol = "SV2"
        publicPool.stratumV2ChannelType = "extended"
        publicPool.stratumV2AuthorityPubkey = "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6"
        var ckpool = PoolSlotDraft(id: 1)
        ckpool.stratumURL = "solo.ckpool.org"
        ckpool.stratumPortString = "3333"
        ckpool.stratumUser = "bc1qpublicpoolpreview.worker1"
        var ocean = PoolSlotDraft(id: 2)
        ocean.stratumURL = "mine.ocean.xyz"
        ocean.stratumPortString = "3334"
        ocean.stratumUser = "bc1qpublicpoolpreview.worker2"
        viewModel.poolCatalog = PoolCatalogDraft(
            slots: [publicPool, ckpool, ocean],
            primaryPoolID: 0,
            secondaryPoolID: 1,
            useFallbackStratum: false
        )
        return NavigationStack {
            PoolCatalogView(viewModel: viewModel)
        }
    }
#endif
