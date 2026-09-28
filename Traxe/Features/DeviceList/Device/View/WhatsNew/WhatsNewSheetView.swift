//
//  WhatsNewSheetView.swift
//  Traxe
//
//  Created by Matthew Ramsden on 11/17/24.
//

import StoreKit
import SwiftUI

struct WhatsNewSheetView: View {
    let content: WhatsNewContent
    let accentColor: Color
    let sendSupportEmail: () -> Void
    let openSourceRepo: () -> Void

    @Environment(\.dismiss) private var dismiss
    // The review prompt is requested from the presenting view's own scene, so it
    // never has to pick a window scene out of the application's connected scenes.
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                bitaxeImage

                if !content.highlights.isEmpty {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(content.highlights) { highlight in
                            highlightRow(for: highlight)
                        }
                    }
                }

                if !secondaryActions.isEmpty {
                    if !content.highlights.isEmpty {
                        Divider()
                            .padding(.trailing, 40)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(secondaryActions) { action in
                            secondaryActionRow(action)
                        }
                    }
                }

            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
            .padding(.bottom, 40)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemBackground))
        .bottomActionBar {
            footer
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(content.title)
                .font(.system(size: 34, weight: .bold, design: .default))
                .multilineTextAlignment(.leading)

            if let message = content.message, !message.isEmpty {
                Text(.init(message))
                    .font(.system(.body))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func highlightRow(for highlight: WhatsNewHighlight) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(badgeColor(for: highlight.badgeTint).opacity(0.15))

                Image(systemName: highlight.iconSystemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(badgeColor(for: highlight.badgeTint))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text(highlight.title)
                    .font(.system(.headline))
                    .foregroundStyle(.primary)

                Text(.init(highlight.detail))
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func secondaryActionRow(_ action: SecondaryAction) -> some View {
        Button {
            action.handler()
        } label: {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(action.tint.opacity(0.15))

                    Image(systemName: action.iconSystemName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(action.tint)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.system(.headline))
                        .foregroundStyle(.primary)

                    Text(action.detail)
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.quaternary)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .prominentActionButtonStyle()
        .tint(Color.traxeGold)
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.large)
        .frame(maxWidth: 700)
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
    }

    private func badgeColor(for _: WhatsNewHighlight.BadgeTint) -> Color {
        .traxeGold
    }

    private var bitaxeImage: some View {
        Image("bitaxe")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 220)
            .frame(maxWidth: .infinity)
    }
}

extension WhatsNewSheetView {
    private struct SecondaryAction: Identifiable {
        enum Kind: Hashable {
            case rateAndReview
            case emailFeedback
            case openSource
        }

        let id: Kind
        let iconSystemName: String
        let tint: Color
        let title: String
        let detail: String
        let handler: () -> Void
    }

    private var secondaryActions: [SecondaryAction] {
        [
            SecondaryAction(
                id: .rateAndReview,
                iconSystemName: "heart.fill",
                tint: .traxeGold,
                title: "Loving the app?",
                detail: "A nice review would be great!",
                handler: { requestReview() }
            ),
            SecondaryAction(
                id: .emailFeedback,
                iconSystemName: "envelope.fill",
                tint: .traxeGold,
                title: "Having issues?",
                detail: "Reach out and I'll make it right.",
                handler: sendSupportEmail
            ),
            SecondaryAction(
                id: .openSource,
                iconSystemName: "chevron.left.slash.chevron.right",
                tint: .traxeGold,
                title: "Open Source",
                detail: "Because of course an app for bitaxe should be open source.",
                handler: openSourceRepo
            ),
        ]
    }
}

#Preview("Sheet Example") {
    WhatsNewConfig.isEnabledForCurrentBuild = true
    return WhatsNewSheetView(
        content: WhatsNewConfig.content,
        accentColor: .orange,
        sendSupportEmail: {},
        openSourceRepo: {}
    )
}
