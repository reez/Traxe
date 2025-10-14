internal import Combine
import SwiftUI

struct ContentView: View {
    @State private var viewModel: HashrateViewModel
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    @MainActor
    init(viewModel: HashrateViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {

            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        //                        Text("Total Hash Rate")
                        //                            .font(.caption2)
                        //                            .fontDesign(.rounded)
                        //                            .foregroundStyle(.secondary)

                        Text(viewModel.totalHashrateValue)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .fontDesign(.rounded)
                            .minimumScaleFactor(0.6)

                        if !viewModel.totalHashrateUnit.isEmpty {
                            Text(viewModel.totalHashrateUnit)
                                .font(.caption2)
                                .fontDesign(.rounded)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } header: {
                    Text("Total Hash Rate")
                    //                        .font(.caption2)
                    //                        .fontDesign(.rounded)
                    //                        .foregroundStyle(.secondary)
                } footer: {
                    if let timestamp = viewModel.totalLastUpdated {
                        Text("Updated \(timestamp, style: .time)")
                            .font(.caption2)
                            .fontDesign(.rounded)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if viewModel.miners.isEmpty {
                    Section {
                        Text("No miner data yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    Section("Miners") {
                        ForEach(viewModel.miners) { miner in
                            NavigationLink(value: miner) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(miner.name)
                                        .font(.headline)
                                        .fontDesign(.rounded)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    //                                    Text(miner.ipAddress)
                                    //                                        .font(.caption2)
                                    //                                        .foregroundStyle(.secondary)
                                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                                        Text(miner.hashrateValue)
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .fontDesign(.rounded)
                                        if !miner.hashrateUnit.isEmpty {
                                            Text(miner.hashrateUnit)
                                                .font(.caption2)
                                                .fontDesign(.rounded)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.all, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Traxe")
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.automatic)
            .navigationDestination(for: WatchMinerSummary.self) { miner in
                DeviceDetailView(miner: miner)
            }
        }
        .task {
            if !isPreview {
                await viewModel.start()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHashrateDidUpdate)) { _ in
            guard !isPreview else { return }
            Task { await viewModel.refresh() }
        }
        .onReceive(refreshTimer) { _ in
            guard !isPreview else { return }
            Task { await viewModel.refresh() }
        }
    }
}

#Preview {
    ContentView(viewModel: .previewModel())
}

#Preview {
    ContentView(viewModel: .init())
}
