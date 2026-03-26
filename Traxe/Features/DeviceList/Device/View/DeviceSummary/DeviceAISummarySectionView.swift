import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

struct DeviceAISummarySectionView: View {
    let summary: AISummary?
    let isDataLoaded: Bool

    var body: some View {
        let lineCount = 3
        let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        let fixedHeight = lineHeight * CGFloat(lineCount)

        VStack(alignment: .leading, spacing: 16) {
            Text("Summary")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .topLeading) {
                if let summary {
                    if #available(iOS 18.0, *) {
                        AnimatedAISummaryText(
                            content: summary.content,
                            isDataLoaded: isDataLoaded
                        )
                        .lineLimit(lineCount)
                        .truncationMode(.tail)
                        .transition(.opacity)
                    } else {
                        FallbackAISummaryText(content: summary.content)
                            .lineLimit(lineCount)
                            .truncationMode(.tail)
                            .transition(.opacity)
                    }
                } else {
                    TypingDots()
                        .transition(.opacity)
                }
            }
            .frame(height: fixedHeight)
        }
    }
}
