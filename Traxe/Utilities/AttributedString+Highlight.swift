import SwiftUI
import UIKit

// Highlights numeric value tokens and common units within a string.
// Examples that will be colored:
// - 7.3 TH/s, 485.2 GH/s
// - 61-72°C, 65°C
// - 2450W, 85%
extension String {
    func highlightingValues(color: Color = .traxeGold) -> AttributedString {
        let mutable = NSMutableAttributedString(string: self)

        let uiColor = UIColor(color)
        // Use body size for baseline, bump matches to semibold weight
        let bodyUIFont = UIFont.preferredFont(forTextStyle: .body)
        let semiboldUIFont = UIFont.systemFont(ofSize: bodyUIFont.pointSize, weight: .semibold)
        let highlight: [NSAttributedString.Key: Any] = [
            .foregroundColor: uiColor,
            .font: semiboldUIFont,
        ]

        let patterns: [String] = [
            // Miner count phrase (e.g., "15 miners" or "1 miner")
            #"\b\d+\s+miners?\b"#,
            #"\b\d+(?:\.\d+)?\s?(?:TH/s|GH/s|MH/s|kH/s|H/s)\b"#,
            #"\b\d+\s?-\s?\d+°C\b"#,
            #"\b\d+(?:\.\d+)?°C\b"#,
            #"\b\d+(?:\.\d+)?W\b"#,
            #"\b\d+(?:\.\d+)?%\b"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let fullRange = NSRange(location: 0, length: (self as NSString).length)
                regex.enumerateMatches(in: self, range: fullRange) { match, _, _ in
                    if let r = match?.range, r.location != NSNotFound {
                        mutable.addAttributes(highlight, range: r)
                    }
                }
            }
        }

        return AttributedString(mutable)
    }
}
