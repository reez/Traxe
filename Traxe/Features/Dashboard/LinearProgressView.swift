//
//  LinearProgressView.swift
//  Traxe
//
//  Created by Matthew Ramsden on 4/14/25.
//

import Foundation
import SwiftUI

struct LinearProgressView: View {
    let value: Double
    let maxValue: Double
    let unit: String

    private var progress: Double {
        min(max(value / maxValue, 0.0), 1.0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.traxeGold.opacity(0.2))
                    .frame(height: 4)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.traxeGold)
                    .frame(width: geometry.size.width * progress, height: 4)
            }
        }
        .frame(height: 4)
    }
}
