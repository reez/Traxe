import SwiftUI

struct MonospacedIdentifierEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 72

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.callout.monospaced())
                .frame(height: minHeight)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .accessibilityLabel(placeholder)

            if text.isEmpty {
                Text(placeholder)
                    .font(.callout.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
    }
}
