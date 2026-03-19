import Charts
import Foundation
import SwiftData
import SwiftUI

struct WeeklyRecapFleetDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let poolName: String?
    let currentHashrate: Double
}

struct WeeklyRecapView: View {
    private struct FleetDeviceRecap: Identifiable, Sendable {
        let id: String
        let name: String
        let poolName: String?
        let currentHashrate: Double
        let recap: WeeklyRecap?
    }

    private struct WeeklyRecapSampleRecord: Sendable {
        let timestamp: Date
        let hashrate: Double
        let temperature: Double
        let deviceID: String?
    }

    enum Scope {
        case device(deviceID: String, deviceName: String, poolName: String?)
        case fleet(devices: [WeeklyRecapFleetDevice])
    }

    let scope: Scope

    @Environment(\.modelContext) private var modelContext
    @State private var recap: WeeklyRecap?
    @State private var fleetRecaps: [FleetDeviceRecap] = []
    @State private var isLoading = false
    @State private var expandedFleetDeviceIDs: Set<String> = []

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.tertiarySystemBackground),
                    Color(.secondarySystemBackground),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    contextHeader

                    if isLoading {
                        ProgressView("Loading weekly recap…")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        recapContent
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Weekly Recap")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRecap() }
    }

    private var contextHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(weekTitleText)
                .font(.largeTitle)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            switch scope {
            case .device(_, let deviceName, let poolName):
                let devicePoolAllocations = WeeklyRecapPoolAllocationBuilder.build(
                    from: poolName,
                    totalHashrate: 0
                )

                Text(deviceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !devicePoolAllocations.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(devicePoolAllocations) { allocation in
                            devicePoolRow(allocation)
                        }
                    }
                    .padding(.top, 2)
                } else if let poolName, !poolName.isEmpty {
                    Text(poolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .fleet(let devices):
                VStack(alignment: .leading, spacing: 10) {
                    let names = fleetMinerNames(from: devices)

                    headerSectionLabel("Miners")

                    VStack(alignment: .leading, spacing: 2) {
                        if names.isEmpty {
                            Text("No miners")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !fleetHeaderPoolAllocations.isEmpty {
                        headerSectionLabel("Pools")

                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(fleetHeaderPoolAllocations) { allocation in
                                poolAllocationRow(allocation)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var recapContent: some View {
        switch scope {
        case .device:
            if let recap {
                recapDetailContent(recap, showDateRange: false)
            } else {
                emptyStateCard(text: emptyStateText)
            }
        case .fleet:
            if fleetRecaps.isEmpty {
                emptyStateCard(text: emptyStateText)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if fleetRecaps.count > 1 {
                        fleetExpansionControl
                    }

                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(fleetRecaps) { deviceRecap in
                            VStack(alignment: .leading, spacing: 12) {
                                let isExpanded = expandedFleetDeviceIDs.contains(deviceRecap.id)

                                Button {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        if isExpanded {
                                            expandedFleetDeviceIDs.remove(deviceRecap.id)
                                        } else {
                                            expandedFleetDeviceIDs.insert(deviceRecap.id)
                                        }
                                    }
                                } label: {
                                    fleetDeviceHeader(
                                        name: deviceRecap.name,
                                        ipAddress: deviceRecap.id,
                                        poolAllocations: WeeklyRecapPoolAllocationBuilder.build(
                                            from: deviceRecap.poolName,
                                            totalHashrate: deviceRecap.recap?.averageHashrate
                                                ?? deviceRecap.currentHashrate
                                        ),
                                        isExpanded: isExpanded
                                    )
                                }
                                .buttonStyle(.plain)

                                if isExpanded {
                                    if let recap = deviceRecap.recap {
                                        recapDetailContent(recap, showDateRange: false)
                                    } else {
                                        emptyStateCard(text: deviceHistoryEmptyStateText)
                                    }
                                }
                            }
                            .id(deviceRecap.id)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var fleetExpansionControl: some View {
        HStack {
            Spacer()
            Button {
                toggleAllFleetSections()
            } label: {
                Text(areAllFleetSectionsExpanded ? "Collapse All" : "Expand All")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.traxeGold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        Color.traxeGold.opacity(0.14),
                        in: Capsule(style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func recapDetailContent(_ recap: WeeklyRecap, showDateRange: Bool) -> some View {
        let weekDates = recap.dailyPoints.map(\.date)
        let hashratePoints = recap.dailyPoints.filter { $0.sampleCount > 0 }
        let hasHashrateData = !hashratePoints.isEmpty
        let temperaturePoints = recap.dailyPoints.filter {
            $0.sampleCount > 0 && $0.averageTemperature > 0
        }
        let hasTemperatureData = !temperaturePoints.isEmpty

        if showDateRange {
            Text(dateRangeText(for: recap))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            WeeklyRecapStatCard(
                title: "Average Hash Rate",
                value: formattedHashrate(recap.averageHashrate),
                subtitle: "Across \(recap.sampleCount) samples"
            )
            WeeklyRecapStatCard(
                title: "Peak Hash Rate",
                value: formattedHashrate(recap.peakHashrate),
                subtitle: "Highest point this week"
            )
            WeeklyRecapStatCard(
                title: "Average Temperature",
                value:
                    hasTemperatureData
                    ? "\(recap.averageTemperature.formatted(.number.precision(.fractionLength(0))))°C"
                    : "--",
                subtitle:
                    hasTemperatureData
                    ? "Range \(recap.minTemperature.formatted(.number.precision(.fractionLength(0))))°C - \(recap.maxTemperature.formatted(.number.precision(.fractionLength(0))))°C"
                    : "No valid temperature samples this week"
            )
            WeeklyRecapStatCard(
                title: "Active Days",
                value: "\(recap.activeDays)/7",
                subtitle: trendSubtitle(from: recap.hashrateChangePercent)
            )
        }
        .padding(.horizontal)

        if hasHashrateData {
            hashrateRangeChartCard(points: hashratePoints, xAxisDates: weekDates)
        } else {
            unavailableChartCard(
                title: "Daily Average Hash Rate",
                message: "No hashrate samples were recorded this week."
            )
        }

        if hasTemperatureData {
            chartCard(
                title: "Daily Average Temperature",
                points: temperaturePoints,
                value: \.averageTemperature,
                formatter: { value in
                    "\(value.formatted(.number.precision(.fractionLength(0))))°C"
                },
                axisFormatter: { value in
                    value.formatted(.number.precision(.fractionLength(0)))
                },
                unitLabel: "°C",
                xAxisDates: weekDates
            )
        } else {
            unavailableChartCard(
                title: "Daily Average Temperature",
                message: "No valid temperature samples were recorded this week."
            )
        }
    }

    private func emptyStateCard(text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal)
    }

    private func unavailableChartCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal)
    }

    private var areAllFleetSectionsExpanded: Bool {
        let allIDs = Set(fleetRecaps.map(\.id))
        return !allIDs.isEmpty && allIDs.isSubset(of: expandedFleetDeviceIDs)
    }

    private func toggleAllFleetSections() {
        let allIDs = Set(fleetRecaps.map(\.id))
        guard !allIDs.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.25)) {
            if allIDs.isSubset(of: expandedFleetDeviceIDs) {
                expandedFleetDeviceIDs.subtract(allIDs)
            } else {
                expandedFleetDeviceIDs.formUnion(allIDs)
            }
        }
    }

    private func fleetDeviceHeader(
        name: String,
        ipAddress: String,
        poolAllocations: [WeeklyRecapPoolAllocation],
        isExpanded: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.traxeGold)
                Text(ipAddress)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !poolAllocations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(poolAllocations) { allocation in
                            poolAllocationRow(allocation)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer()
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var fleetHeaderPoolAllocations: [WeeklyRecapPoolAllocation] {
        let sources: [(poolDisplayName: String?, totalHashrate: Double)]

        if fleetRecaps.isEmpty {
            switch scope {
            case .fleet(let devices):
                sources = devices.map { device in
                    (poolDisplayName: device.poolName, totalHashrate: device.currentHashrate)
                }
            case .device:
                sources = []
            }
        } else {
            sources = fleetRecaps.map { recap in
                (
                    poolDisplayName: recap.poolName,
                    totalHashrate: recap.recap?.averageHashrate ?? recap.currentHashrate
                )
            }
        }

        return WeeklyRecapPoolAllocationBuilder.buildFleetTotals(from: sources)
    }

    private func poolAllocationRow(_ allocation: WeeklyRecapPoolAllocation) -> some View {
        HStack(spacing: 8) {
            poolIcon(for: allocation.logoName)
                .foregroundStyle(.secondary)

            Text(allocation.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text(formattedHashrate(allocation.estimatedHashrate))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private func devicePoolRow(_ allocation: WeeklyRecapPoolAllocation) -> some View {
        HStack(spacing: 8) {
            poolIcon(for: allocation.logoName)
                .foregroundStyle(.secondary)

            Text(devicePoolLabel(for: allocation))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func headerSectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func devicePoolLabel(for allocation: WeeklyRecapPoolAllocation) -> String {
        guard let configuredPercent = allocation.configuredPercent else {
            return allocation.name
        }

        return "\(allocation.name) (\(formattedPoolPercent(configuredPercent))%)"
    }

    private func formattedPoolPercent(_ percent: Double) -> String {
        let precision: FloatingPointFormatStyle<Double>.Configuration.Precision =
            percent == percent.rounded()
            ? .fractionLength(0)
            : .fractionLength(1)
        return percent.formatted(.number.precision(precision))
    }

    @ViewBuilder
    private func poolIcon(for logoName: String?) -> some View {
        if let logoName {
            Image(logoName)
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 12, height: 12)
        } else {
            Image(systemName: "hammer.fill")
                .font(.caption2)
        }
    }

    private func hashrateRangeChartCard(points: [WeeklyRecapPoint], xAxisDates: [Date]) -> some View
    {
        let minHashrate = points.map(\.minHashrate).min() ?? 0
        let maxHashrate = points.map(\.maxHashrate).max() ?? 0
        let averageHashrate =
            points.isEmpty ? 0 : points.map(\.averageHashrate).reduce(0, +) / Double(points.count)
        let latestPoint = points.last
        let rangeValues = points.flatMap { [$0.minHashrate, $0.maxHashrate] }
        let yDomain = chartYDomain(for: rangeValues, enforceZeroBaseline: true)
        let unitLabel = hashrateUnitLabel(for: points.map(\.maxHashrate))
        let xDomain = chartXDomain(for: xAxisDates)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Daily Hash Rate Range")
                .font(.headline)
                .foregroundStyle(.primary)

            HStack {
                metricPair(label: "Min", value: formattedHashrate(minHashrate))
                Spacer()
                metricPair(label: "Avg", value: formattedHashrate(averageHashrate))
                Spacer()
                metricPair(label: "Max", value: formattedHashrate(maxHashrate))
            }

            HStack(alignment: .center) {
                Text(unitLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Color.primary.opacity(0.07),
                        in: Capsule(style: .continuous)
                    )

                Spacer()

                if let latestPoint {
                    Text(
                        "Latest \(formattedHashrate(latestPoint.averageHashrate)) • \(latestPoint.date.formatted(.dateTime.weekday(.abbreviated)))"
                    )
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }

            Chart(points, id: \.date) { point in
                AreaMark(
                    x: .value("Day", point.date, unit: .day),
                    yStart: .value("Min", point.minHashrate),
                    yEnd: .value("Max", point.maxHashrate)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.traxeGold.opacity(0.22),
                            Color.traxeGold.opacity(0.04),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Average", point.averageHashrate)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.traxeGold)

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Average", point.averageHashrate)
                )
                .symbolSize(28)
                .foregroundStyle(Color.traxeGold)

                RuleMark(y: .value("Average", averageHashrate))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.traxeGold.opacity(0.45))

                if point.date == latestPoint?.date {
                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Average", point.averageHashrate)
                    )
                    .symbolSize(50)
                    .annotation(
                        position: .top,
                        alignment: .trailing,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text(formattedHashrate(point.averageHashrate))
                            .font(.caption2)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Color(uiColor: .secondarySystemBackground),
                                in: Capsule(style: .continuous)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                            .foregroundStyle(.primary)
                            .offset(x: -34)
                    }
                }
            }
            .frame(height: 200)
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: xAxisDates) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    AxisTick()
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.08))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisTick()
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                        .foregroundStyle(Color.primary.opacity(0.12))
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(raw.formattedHashRateWithUnit().value)
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.primary.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal)
    }

    @ViewBuilder
    private func chartCard(
        title: String,
        points: [WeeklyRecapPoint],
        value: KeyPath<WeeklyRecapPoint, Double>,
        formatter: @escaping (Double) -> String,
        axisFormatter: @escaping (Double) -> String,
        unitLabel: String,
        xAxisDates: [Date],
        enforceZeroBaseline: Bool = false
    ) -> some View {
        let values = points.map { $0[keyPath: value] }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        let average = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        let latestPoint = points.last
        let latestValue = latestPoint?[keyPath: value]
        let yDomain = chartYDomain(for: values, enforceZeroBaseline: enforceZeroBaseline)
        let xDomain = chartXDomain(for: xAxisDates)

        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            HStack {
                metricPair(label: "Min", value: formatter(minimum))
                Spacer()
                metricPair(label: "Avg", value: formatter(average))
                Spacer()
                metricPair(label: "Max", value: formatter(maximum))
            }

            HStack(alignment: .center) {
                Text(unitLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Color.primary.opacity(0.07),
                        in: Capsule(style: .continuous)
                    )

                Spacer()

                if let latestPoint, let latestValue {
                    Text(
                        "Latest \(formatter(latestValue)) • \(latestPoint.date.formatted(.dateTime.weekday(.abbreviated)))"
                    )
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }

            Chart(points, id: \.date) { point in
                let yValue = point[keyPath: value]
                AreaMark(
                    x: .value("Day", point.date, unit: .day),
                    yStart: .value("Baseline", yDomain.lowerBound),
                    yEnd: .value("Value", yValue)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.traxeGold.opacity(0.2),
                            Color.traxeGold.opacity(0.03),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Value", yValue)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.traxeGold)

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Value", yValue)
                )
                .symbolSize(30)
                .foregroundStyle(Color.traxeGold)

                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.traxeGold.opacity(0.45))

                if point.date == latestPoint?.date {
                    PointMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Value", yValue)
                    )
                    .symbolSize(50)
                    .annotation(
                        position: .top,
                        alignment: .trailing,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text(formatter(yValue))
                            .font(.caption2)
                            .monospacedDigit()
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Color(uiColor: .secondarySystemBackground),
                                in: Capsule(style: .continuous)
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                            .foregroundStyle(.primary)
                            .offset(x: -34)
                    }
                }
            }
            .frame(height: 200)
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: xAxisDates) { value in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    AxisTick()
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.primary.opacity(0.08))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisTick()
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                        .foregroundStyle(Color.primary.opacity(0.12))
                    AxisValueLabel {
                        if let raw = value.as(Double.self) {
                            Text(axisFormatter(raw))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(Color.primary.opacity(0.025))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal)
    }

    private func metricPair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
    }

    @MainActor
    private func loadRecap() async {
        isLoading = true
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)

        guard
            let startDate = calendar.date(byAdding: .day, value: -6, to: todayStart),
            let endDateExclusive = calendar.date(byAdding: .day, value: 1, to: todayStart)
        else {
            recap = nil
            isLoading = false
            return
        }

        let predicate = #Predicate<HistoricalDataPoint> { point in
            point.timestamp >= startDate && point.timestamp < endDateExclusive
        }
        let descriptor = FetchDescriptor<HistoricalDataPoint>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp)]
        )

        do {
            let allWeeklyPoints = try modelContext.fetch(descriptor)
            let sampleRecords = allWeeklyPoints.map { point in
                WeeklyRecapSampleRecord(
                    timestamp: point.timestamp,
                    hashrate: point.hashrate,
                    temperature: point.temperature,
                    deviceID: point.deviceId
                )
            }
            switch scope {
            case .device(let deviceID, _, _):
                let deviceSamples =
                    sampleRecords
                    .filter { $0.deviceID == deviceID }
                    .map { record in
                        WeeklyRecapSample(
                            timestamp: record.timestamp,
                            hashrate: record.hashrate,
                            temperature: record.temperature
                        )
                    }
                recap = await Task.detached(priority: .userInitiated) {
                    WeeklyRecapBuilder.build(from: deviceSamples, now: now, calendar: calendar)
                }.value
                fleetRecaps = []
                expandedFleetDeviceIDs = []
            case .fleet(let devices):
                recap = nil
                let loadedFleetRecaps = await Task.detached(priority: .userInitiated) {
                    let pointsByDeviceID = Dictionary(grouping: sampleRecords) { record in
                        record.deviceID ?? ""
                    }
                    return devices.map { device in
                        let deviceSamples = (pointsByDeviceID[device.id] ?? []).map { record in
                            WeeklyRecapSample(
                                timestamp: record.timestamp,
                                hashrate: record.hashrate,
                                temperature: record.temperature
                            )
                        }
                        let recap = WeeklyRecapBuilder.build(
                            from: deviceSamples,
                            now: now,
                            calendar: calendar
                        )
                        return FleetDeviceRecap(
                            id: device.id,
                            name: device.name,
                            poolName: device.poolName,
                            currentHashrate: device.currentHashrate,
                            recap: recap
                        )
                    }
                }.value
                fleetRecaps = loadedFleetRecaps
                let loadedIDs = Set(loadedFleetRecaps.map(\.id))
                var retainedExpansion = expandedFleetDeviceIDs.intersection(loadedIDs)
                if retainedExpansion.isEmpty, let firstID = loadedFleetRecaps.first?.id {
                    retainedExpansion.insert(firstID)
                }
                expandedFleetDeviceIDs = retainedExpansion
            }
        } catch {
            recap = nil
            fleetRecaps = []
            expandedFleetDeviceIDs = []
        }

        isLoading = false
    }

    private func dateRangeText(for recap: WeeklyRecap) -> String {
        "\(shortDate(recap.startDate)) - \(shortDate(recap.endDate))"
    }

    private var weekTitleText: String {
        switch scope {
        case .device:
            if let recap {
                return dateRangeText(for: recap)
            }
        case .fleet:
            if let recap = fleetRecaps.compactMap(\.recap).first {
                return dateRangeText(for: recap)
            }
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        return "\(shortDate(startDate)) - \(shortDate(todayStart))"
    }

    private func fleetMinerNames(from devices: [WeeklyRecapFleetDevice]) -> [String] {
        devices.map(\.name).filter { !$0.isEmpty }
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func formattedHashrate(_ value: Double) -> String {
        let formatted = value.formattedHashRateWithUnit()
        return "\(formatted.value) \(formatted.unit)"
    }

    private func hashrateUnitLabel(for values: [Double]) -> String {
        let reference = values.max() ?? 0
        return reference.formattedHashRateWithUnit().unit
    }

    private func chartYDomain(
        for values: [Double],
        enforceZeroBaseline: Bool
    ) -> ClosedRange<Double> {
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }

        if minimum == maximum {
            let padding = max(abs(maximum) * 0.1, 1)
            let lower = enforceZeroBaseline ? 0 : minimum - padding
            return lower...(maximum + padding)
        }

        let span = maximum - minimum
        let padding = max(span * 0.18, 1)
        let lower = enforceZeroBaseline ? 0 : minimum - padding
        let upper = maximum + padding
        return lower...upper
    }

    private func chartXDomain(for dates: [Date]) -> ClosedRange<Date> {
        guard let start = dates.first, let end = dates.last else {
            let now = Date()
            return now...now
        }
        // Keep Monday anchored to the left edge and only extend the right side
        // for the latest-point annotation bubble.
        let rightEdgePadding: TimeInterval = 36 * 60 * 60
        return start...end.addingTimeInterval(rightEdgePadding)
    }

    private func trendSubtitle(from percent: Double?) -> String {
        guard let percent else { return "Need more data for trend" }
        if percent == 0 {
            return "Flat week-over-week trend"
        }
        let direction = percent > 0 ? "up" : "down"
        let magnitude = abs(percent).formatted(.number.precision(.fractionLength(1)))
        return "\(magnitude)% \(direction) from first active day"
    }

    private var emptyStateText: String {
        switch scope {
        case .device:
            return
                "Not enough device history yet. Keep the app open while mining to generate weekly recap data."
        case .fleet:
            return
                "Not enough fleet history yet. Open your miners from the main screen to start collecting recap data."
        }
    }

    private var deviceHistoryEmptyStateText: String {
        "Not enough device history yet. Keep the app open while mining to generate weekly recap data."
    }
}

#Preview("Weekly Recap - Fleet Pools") {
    let container = makeWeeklyRecapPreviewContainer()
    seedWeeklyRecapPreviewData(in: container.mainContext)

    return NavigationStack {
        WeeklyRecapView(
            scope: .fleet(
                devices: [
                    WeeklyRecapFleetDevice(
                        id: "192.168.1.101",
                        name: "nerdqaxe++",
                        poolName: "mine.ocean.xyz (65%) • publicpool.io (35%)",
                        currentHashrate: 20_600
                    ),
                    WeeklyRecapFleetDevice(
                        id: "192.168.1.102",
                        name: "bitaxe",
                        poolName: "solo.ckpool.org",
                        currentHashrate: 720
                    ),
                ]
            )
        )
    }
    .modelContainer(container)
}

private func makeWeeklyRecapPreviewContainer() -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)

    do {
        return try ModelContainer(for: HistoricalDataPoint.self, configurations: config)
    } catch {
        fatalError("Failed to create weekly recap preview container: \(error)")
    }
}

private func seedWeeklyRecapPreviewData(in modelContext: ModelContext) {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let previewDevices: [(id: String, baseHashrate: Double, baseTemperature: Double)] = [
        ("192.168.1.101", 20_600, 60),
        ("192.168.1.102", 720, 64),
    ]

    for dayOffset in 0..<7 {
        guard let day = calendar.date(byAdding: .day, value: dayOffset - 6, to: today) else {
            continue
        }

        for device in previewDevices {
            for sampleIndex in 0..<3 {
                let hourOffset = 8 + (sampleIndex * 4)
                let timestamp = calendar.date(byAdding: .hour, value: hourOffset, to: day) ?? day
                let hashrateDrift = Double((dayOffset + sampleIndex) % 3 - 1)
                let temperatureDrift = Double((dayOffset + sampleIndex) % 4 - 1)

                modelContext.insert(
                    HistoricalDataPoint(
                        timestamp: timestamp,
                        hashrate: device.baseHashrate
                            + (hashrateDrift * device.baseHashrate * 0.025),
                        temperature: device.baseTemperature + temperatureDrift,
                        deviceId: device.id
                    )
                )
            }
        }
    }

    try? modelContext.save()
}
