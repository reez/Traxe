//
//  WhatsNewConfig.swift
//  Traxe
//
//  Created by Codex on 11/17/24.
//

import Foundation

public struct WhatsNewHighlight: Identifiable, Sendable, Equatable {
    public enum BadgeTint: String, Sendable {
        case accent
        case blue
        case cyan
        case green
        case indigo
        case mint
        case orange
        case pink
        case purple
        case red
        case teal
        case yellow
    }

    public let id: UUID
    public let badgeTint: BadgeTint
    public let iconSystemName: String
    public let title: String
    public let detail: String

    public init(
        id: UUID = UUID(),
        badgeTint: BadgeTint,
        iconSystemName: String,
        title: String,
        detail: String
    ) {
        self.id = id
        self.badgeTint = badgeTint
        self.iconSystemName = iconSystemName
        self.title = title
        self.detail = detail
    }
}

public struct WhatsNewContent: Sendable, Equatable {
    public let title: String
    public let message: String?
    public let highlights: [WhatsNewHighlight]

    public init(
        title: String,
        message: String? = nil,
        highlights: [WhatsNewHighlight]
    ) {
        self.title = title
        self.message = message
        self.highlights = highlights
    }
}

public enum WhatsNewConfig {
    /// Toggle this flag when you want the TipKit surface to appear for the current build.
    public static var isEnabledForCurrentBuild = true  //false

    /// A stable identifier for a "What's New" announcement.
    ///
    /// Set this when you want to surface a new announcement that isn't strictly tied to the app version
    /// (for example, a feature rollout you choose to highlight later).
    ///
    /// When `nil`, the app version is used as the fallback key.
    public static var currentAnnouncementID: String? = nil

    /// Customize the content that the sheet renders when users tap the tip action.
    public static var content = WhatsNewContent(
        title: "What’s New",
        message: "Version \(currentVersion())",  // "New features in Traxe",
        highlights: [
            WhatsNewHighlight(
                badgeTint: .orange,
                iconSystemName: "calendar",
                title: "Weekly Recap",
                detail:
                    "Added Weekly Recap views for fleet and individual miners, with charts & key stats."
            ),
            WhatsNewHighlight(
                badgeTint: .green,
                iconSystemName: "macbook",
                title: "Open Source Contributors",
                detail: "Thanks to @joeycast for your recent code contributions to Traxe!"
            ),
        ]
    )

    public static func currentVersion(in bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    public static func currentWhatsNewKey(in bundle: Bundle = .main) -> String {
        currentAnnouncementID ?? currentVersion(in: bundle)
    }
}
