import Foundation

struct WeeklyRecapSample: Sendable {
    let timestamp: Date
    let hashrate: Double
    let temperature: Double
}

struct WeeklyRecapPoint: Sendable {
    let date: Date
    let averageHashrate: Double
    let minHashrate: Double
    let maxHashrate: Double
    let averageTemperature: Double
    let sampleCount: Int
}

struct WeeklyRecap: Sendable {
    let startDate: Date
    let endDate: Date
    let dailyPoints: [WeeklyRecapPoint]
    let averageHashrate: Double
    let peakHashrate: Double
    let averageTemperature: Double
    let minTemperature: Double
    let maxTemperature: Double
    let activeDays: Int
    let sampleCount: Int
    let hashrateChangePercent: Double?
    let bestDayDate: Date?
}

enum WeeklyRecapBuilder {
    static func build(
        from historicalData: [HistoricalDataPoint],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyRecap? {
        let samples = historicalData.map { point in
            WeeklyRecapSample(
                timestamp: point.timestamp,
                hashrate: point.hashrate,
                temperature: point.temperature
            )
        }
        return build(from: samples, now: now, calendar: calendar)
    }

    static func build(
        from samples: [WeeklyRecapSample],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyRecap? {
        let todayStart = calendar.startOfDay(for: now)
        guard
            let startDate = calendar.date(byAdding: .day, value: -6, to: todayStart),
            let endDateExclusive = calendar.date(byAdding: .day, value: 1, to: todayStart)
        else {
            return nil
        }

        let weeklySamples = samples.filter {
            $0.timestamp >= startDate && $0.timestamp < endDateExclusive
        }

        guard !weeklySamples.isEmpty else { return nil }

        let samplesByDay = Dictionary(grouping: weeklySamples) { sample in
            calendar.startOfDay(for: sample.timestamp)
        }

        var dailyPoints: [WeeklyRecapPoint] = []
        dailyPoints.reserveCapacity(7)

        for dayOffset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startDate) else {
                continue
            }
            let daySamples = samplesByDay[day] ?? []
            let dayHashrates = daySamples.map(\.hashrate)
            let averageHashrate = average(daySamples.map(\.hashrate))
            let averageTemperature = average(validTemperatures(from: daySamples))
            dailyPoints.append(
                WeeklyRecapPoint(
                    date: day,
                    averageHashrate: averageHashrate,
                    minHashrate: dayHashrates.min() ?? 0,
                    maxHashrate: dayHashrates.max() ?? 0,
                    averageTemperature: averageTemperature,
                    sampleCount: daySamples.count
                )
            )
        }

        let weeklyTemperatures = validTemperatures(from: weeklySamples)
        let averageHashrate = average(weeklySamples.map(\.hashrate))
        let peakHashrate = weeklySamples.map(\.hashrate).max() ?? 0
        let averageTemperature = average(weeklyTemperatures)
        let minTemperature = weeklyTemperatures.min() ?? 0
        let maxTemperature = weeklyTemperatures.max() ?? 0
        let activeDays = dailyPoints.filter { $0.averageHashrate > 0 }.count

        let firstActiveHashrate = dailyPoints.first(where: { $0.averageHashrate > 0 })?
            .averageHashrate
        let lastActiveHashrate = dailyPoints.last(where: { $0.averageHashrate > 0 })?
            .averageHashrate
        let hashrateChangePercent: Double?
        if let firstActiveHashrate, let lastActiveHashrate, firstActiveHashrate > 0 {
            hashrateChangePercent =
                ((lastActiveHashrate - firstActiveHashrate) / firstActiveHashrate) * 100
        } else {
            hashrateChangePercent = nil
        }

        let bestDayDate = dailyPoints.max { lhs, rhs in
            lhs.averageHashrate < rhs.averageHashrate
        }?.date

        return WeeklyRecap(
            startDate: startDate,
            endDate: todayStart,
            dailyPoints: dailyPoints,
            averageHashrate: averageHashrate,
            peakHashrate: peakHashrate,
            averageTemperature: averageTemperature,
            minTemperature: minTemperature,
            maxTemperature: maxTemperature,
            activeDays: activeDays,
            sampleCount: weeklySamples.count,
            hashrateChangePercent: hashrateChangePercent,
            bestDayDate: bestDayDate
        )
    }

    private static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func validTemperatures(from samples: [WeeklyRecapSample]) -> [Double] {
        samples
            .map(\.temperature)
            .filter { $0 > 0 }
    }
}
