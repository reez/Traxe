import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

struct PoolLogoView: View {
    let logoName: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let poolImage {
                Image(uiImage: poolImage)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            } else {
                Image(systemName: "hammer.fill")
                    .font(.system(size: size * 0.85))
            }
        }
        .frame(width: size, height: size)
    }

    #if canImport(UIKit)
        private var poolImage: UIImage? {
            guard let logoName else { return nil }
            return UIImage(named: logoName)
        }
    #else
        private var poolImage: Never? { nil }
    #endif
}
