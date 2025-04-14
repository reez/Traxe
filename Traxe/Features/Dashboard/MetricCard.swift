//
//  MetricCard.swift
//  Traxe
//
//  Created by Matthew Ramsden on 4/14/25.
//

import Foundation
import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String?
    var progress: (value: Double, maxValue: Double)? = nil
    var historicalData: [HistoricalDataPoint]? = nil
    var historicalDataKey: KeyPath<HistoricalDataPoint, Double>? = nil
    var chartStyle: SparklineView.ChartStyle = .line
    var isConnected: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if icon != nil {
                    Image(systemName: icon!)
                        .font(.caption)
                }
                Text(title).bold()
                Spacer()
            }
            .foregroundStyle(.primary)
            .font(.subheadline)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(value)
                        .font(.title)
                        .fontWeight(.semibold)
                        .redacted(reason: isConnected ? [] : .placeholder)
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .redacted(reason: isConnected ? [] : .placeholder)

                    Spacer()
                    if let data = historicalData, let key = historicalDataKey, !data.isEmpty,
                        isConnected
                    {
                        VStack(alignment: .center, spacing: 2) {
                            SparklineView(data: data, valueKey: key, style: chartStyle)
                            //                            Text("Last Hour")
                            //                                .font(.caption2)
                            //                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let progress = progress, isConnected {
                    LinearProgressView(
                        value: progress.value,
                        maxValue: progress.maxValue,
                        unit: unit
                    )
                } else if !isConnected {
                    LinearProgressView(
                        value: 0,
                        maxValue: 1,
                        unit: unit
                    )
                    .opacity(0.3)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary, lineWidth: 1)
        )
        .opacity(isConnected ? 1.0 : 0.7)
    }
}
