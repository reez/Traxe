import SwiftUI

struct StratumProtocolDetailsView: View {
    let poolTitle: String
    @Binding var protocolValue: String
    @Binding var channelType: String
    @Binding var authorityPubkey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(poolTitle) Protocol".uppercased())
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Protocol", selection: $protocolValue) {
                Text("Stratum V1").tag("SV1")
                Text("Stratum V2").tag("SV2")
            }
            .pickerStyle(.segmented)

            if isStratumV2 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SV2 Channel".uppercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("SV2 Channel", selection: $channelType) {
                        Text("Extended").tag("extended")
                        Text("Standard").tag("standard")
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Authority Pubkey".uppercased())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    MonospacedIdentifierEditor(
                        placeholder: "9c4zpyJ2ndm4e8sP2uNc1VNCGxYjqaxWS6wUCjk8zFj6njFquH6",
                        text: $authorityPubkey,
                        minHeight: 56
                    )
                }
            }
        }
    }

    private var trimmedProtocolValue: String {
        protocolValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isStratumV2: Bool {
        trimmedProtocolValue.uppercased() == "SV2"
    }
}
