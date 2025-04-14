//
//  SparklineView.swift
//  Traxe
//
//  Created by Matthew Ramsden on 4/14/25.
//

import Foundation
import SwiftUI

struct SparklineView: View {
    let data: [HistoricalDataPoint]
    let valueKey: KeyPath<HistoricalDataPoint, Double>
    var style: ChartStyle = .line
    var maxDataPoints: Int = 20
    @State private var isPulsing = false
    @State private var selectedValue: Double?
    @State private var selectedTimestamp: Date?
    @State private var lastHapticTime: Date = .distantPast
    @State private var selectedIndex: Int?

    // MARK: - Constants for Bar Geometry
    private let fixedBarWidth: CGFloat = 4.0
    private let barSpacing: CGFloat = 2.0

    enum ChartStyle {
        case line
        case bars
    }

    private var sampledData: [HistoricalDataPoint] {
        guard data.count > maxDataPoints else { return data }

        let stride = Double(data.count - 1) / Double(maxDataPoints - 1)
        return (0..<maxDataPoints).map { i in
            let index = min(Int(Double(i) * stride), data.count - 1)
            return data[index]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main line or bars
                if style == .line {
                    linePath(in: geometry)
                        .stroke(
                            Color.secondary.opacity(isPulsing ? 0.9 : 0.7),
                            style: StrokeStyle(
                                lineWidth: 2.5,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .shadow(color: .secondary.opacity(0.3), radius: 1, x: 0, y: 0)
                } else {
                    // Remove the single fill for barsPath
                    // barsPath(in: geometry)
                    //    .fill(Color.secondary.opacity(isPulsing ? 0.9 : 0.7))

                    // Draw bars individually to allow for highlighting
                    let values = sampledData.map { $0[keyPath: valueKey] }
                    let maxValue = values.max() ?? 1
                    let minValue = values.min() ?? 0
                    let range = max(maxValue - minValue, 0.01)
                    let startX = barAreaStartX(geometry: geometry)

                    ForEach(Array(sampledData.enumerated()), id: \.element.timestamp) {
                        index,
                        dataPoint in
                        let value = dataPoint[keyPath: valueKey]
                        let normalizedHeight = CGFloat((value - minValue) / range)
                        let barHeight = geometry.size.height * normalizedHeight
                        let y = geometry.size.height - barHeight
                        let finalBarHeight = (value != 0 && barHeight < 1) ? 1 : barHeight

                        let x = startX + CGFloat(index) * (fixedBarWidth + barSpacing)

                        Rectangle()
                            .frame(width: fixedBarWidth, height: finalBarHeight)
                            .position(x: x + fixedBarWidth / 2, y: y + finalBarHeight / 2)
                            .foregroundColor(
                                index == selectedIndex
                                    ? Color.traxeGold  // Highlight color
                                    : Color.secondary.opacity(isPulsing ? 0.9 : 0.7)  // Default color
                            )
                    }
                }

                // End point dot
                if style == .line {
                    if let selectedValue = selectedValue,
                        let selectedTimestamp = selectedTimestamp,
                        !sampledData.isEmpty  // Ensure data exists
                    {
                        // --- Calculate Position First ---
                        let values = sampledData.map { $0[keyPath: valueKey] }
                        // Find index of the selected point
                        let index =
                            sampledData.firstIndex {
                                abs($0[keyPath: valueKey] - selectedValue) < 0.001
                                    && $0.timestamp == selectedTimestamp
                            } ?? 0

                        // Calculate Y position (reusable logic)
                        let maxValue = values.max() ?? 1
                        let minValue = values.min() ?? 0
                        let range = max(maxValue - minValue, 0.01)
                        let y =
                            geometry.size.height
                            * (1
                                - CGFloat(
                                    (selectedValue - minValue)
                                        / range
                                ))

                        // Calculate X using an immediately-invoked closure
                        let x: CGFloat = {
                            if sampledData.count > 1 {
                                let step = geometry.size.width / CGFloat(sampledData.count - 1)
                                return CGFloat(index) * step
                            } else {
                                // If only one point, center it horizontally
                                return geometry.size.width / 2
                            }
                        }()

                        // --- Create View ---
                        Circle()
                            .fill(Color.traxeGold)
                            .frame(width: 4, height: 4)
                            .position(x: x, y: y)
                    }
                }

                // Selection indicator
                if let selectedValue = selectedValue,
                    let selectedTimestamp = selectedTimestamp
                {
                    let index =
                        sampledData.firstIndex {
                            abs($0[keyPath: valueKey] - selectedValue) < 0.001
                                && $0.timestamp == selectedTimestamp
                        } ?? 0
                    let x = barCenterX(for: index, geometry: geometry)

                    VStack {
                        Text(String(format: "%.0f", selectedValue))
                            .font(.caption2)
                            .padding(4)
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        Text(selectedTimestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .position(x: x, y: -20)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !sampledData.isEmpty else { return }

                        let touchX = value.location.x
                        let startX = barAreaStartX(geometry: geometry)
                        let totalBarAreaWidth = calculateTotalBarAreaWidth(count: sampledData.count)

                        // Calculate index based on touch position relative to the bar area
                        let relativeX = touchX - startX
                        let totalStepWidth = fixedBarWidth + barSpacing

                        var calculatedIndex = -1
                        if relativeX >= 0 && touchX <= startX + totalBarAreaWidth {
                            // Determine index by checking which bar's horizontal span contains the touch
                            calculatedIndex = Int(relativeX / totalStepWidth)
                            // Fine-tune: check if touch is in the spacing area after the bar
                            let xInStep = relativeX.truncatingRemainder(dividingBy: totalStepWidth)
                            if xInStep > fixedBarWidth {
                                // If in spacing, associate with the *next* bar unless it's the last one
                                if calculatedIndex < sampledData.count - 1 {
                                    calculatedIndex += 1
                                }
                            }
                        } else if touchX < startX {
                            calculatedIndex = 0  // Before the first bar
                        } else {
                            calculatedIndex = sampledData.count - 1  // After the last bar
                        }

                        // Clamp index to valid range (should already be mostly handled)
                        let clampedIndex = max(0, min(calculatedIndex, sampledData.count - 1))

                        let selectedData = sampledData[clampedIndex]
                        self.selectedIndex = clampedIndex
                        self.selectedValue = selectedData[keyPath: valueKey]
                        self.selectedTimestamp = selectedData.timestamp

                        let now = Date()
                        if now.timeIntervalSince(lastHapticTime) > 0.1 {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            lastHapticTime = now
                        }
                    }
                    .onEnded { _ in
                        self.selectedValue = nil
                        self.selectedTimestamp = nil
                        self.selectedIndex = nil
                    }
            )
        }
        .frame(width: 150, height: 50)  //.frame(width: 60, height: 25)
        .onChange(of: data) { _, _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                isPulsing = true
            }

            // Reset after animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isPulsing = false
                }
            }
        }
    }

    private func linePath(in geometry: GeometryProxy) -> Path {
        Path { path in
            guard !sampledData.isEmpty else { return }

            let values = sampledData.map { $0[keyPath: valueKey] }
            let step = geometry.size.width / CGFloat(values.count - 1)
            let maxValue = values.max() ?? 1
            let minValue = values.min() ?? 0
            let range = max(maxValue - minValue, 0.01)

            for (index, value) in values.enumerated() {
                let x = CGFloat(index) * step
                let y = geometry.size.height * (1 - CGFloat((value - minValue) / range))

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    // MARK: - Helper Functions for Bar Geometry

    /// Calculates the total width required for all bars and spaces.
    private func calculateTotalBarAreaWidth(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * (fixedBarWidth + barSpacing) - barSpacing  // Subtract last spacing
    }

    /// Calculates the starting X coordinate to center the bar area.
    private func barAreaStartX(geometry: GeometryProxy) -> CGFloat {
        let count = sampledData.count
        guard count > 0 else { return 0 }
        let totalWidth = calculateTotalBarAreaWidth(count: count)
        return max(0, (geometry.size.width - totalWidth) / 2)
    }

    /// Calculates the center X coordinate of a bar at a specific index.
    private func barCenterX(for index: Int, geometry: GeometryProxy) -> CGFloat {
        let start = barAreaStartX(geometry: geometry)
        return start + CGFloat(index) * (fixedBarWidth + barSpacing) + (fixedBarWidth / 2)
    }

    private func calculateLastPoint(in geometry: GeometryProxy) -> CGPoint? {
        guard let lastValue = sampledData.last?[keyPath: valueKey],
            !sampledData.isEmpty
        else { return nil }

        let values = sampledData.map { $0[keyPath: valueKey] }
        let maxValue = values.max() ?? 1
        let minValue = values.min() ?? 0
        let range = max(maxValue - minValue, 0.01)

        // Calculate x position using the consistent bar center logic
        let lastIndex = sampledData.count - 1
        let x = barCenterX(for: lastIndex, geometry: geometry)

        let y = geometry.size.height * (1 - CGFloat((lastValue - minValue) / range))

        return CGPoint(x: x, y: y)
    }
}

#Preview("SparklineView") {
    VStack(spacing: 20) {
        // Line style with varying data
        HStack {
            Text("Line Style:")
                .font(.caption)
            SparklineView(
                data: [
                    HistoricalDataPoint(hashrate: 500, temperature: 65),
                    HistoricalDataPoint(hashrate: 520, temperature: 67),
                    HistoricalDataPoint(hashrate: 480, temperature: 64),
                    HistoricalDataPoint(hashrate: 510, temperature: 66),
                    HistoricalDataPoint(hashrate: 530, temperature: 68),
                ],
                valueKey: \.hashrate,
                style: .line
            )
        }

        // Bar style with varying data
        HStack {
            Text("Bar Style:")
                .font(.caption)
            SparklineView(
                data: [
                    HistoricalDataPoint(hashrate: 500, temperature: 65),
                    HistoricalDataPoint(hashrate: 520, temperature: 67),
                    HistoricalDataPoint(hashrate: 480, temperature: 64),
                    HistoricalDataPoint(hashrate: 510, temperature: 66),
                    HistoricalDataPoint(hashrate: 530, temperature: 68),
                ],
                valueKey: \.hashrate,
                style: .bars
            )
        }

        // Line style with flat data
        HStack {
            Text("Flat Line:")
                .font(.caption)
            SparklineView(
                data: [
                    HistoricalDataPoint(hashrate: 500, temperature: 65),
                    HistoricalDataPoint(hashrate: 500, temperature: 65),
                    HistoricalDataPoint(hashrate: 500, temperature: 65),
                    HistoricalDataPoint(hashrate: 500, temperature: 65),
                    HistoricalDataPoint(hashrate: 500, temperature: 65),
                ],
                valueKey: \.hashrate,
                style: .line
            )
        }

        // Line style with temperature data
        HStack {
            Text("Temperature:")
                .font(.caption)
            SparklineView(
                data: [
                    HistoricalDataPoint(hashrate: 500, temperature: 65),
                    HistoricalDataPoint(hashrate: 520, temperature: 68),
                    HistoricalDataPoint(hashrate: 480, temperature: 72),
                    HistoricalDataPoint(hashrate: 510, temperature: 69),
                    HistoricalDataPoint(hashrate: 530, temperature: 67),
                ],
                valueKey: \.temperature,
                style: .line
            )
        }
    }
    .padding()
    .background(Color(uiColor: .systemBackground))
}
