import Foundation

extension Double {
    func formatted(fractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }

    func formattedDifficulty() -> (value: String, unit: String) {
        let valueM = self
        if valueM == 0 { return ("0", "M") }
        let tera = 1_000_000.0
        let giga = 1_000.0
        let kilo = 0.001
        var displayValue: Double
        var unit: String
        if abs(valueM) >= tera {
            displayValue = valueM / tera
            unit = "T"
        } else if abs(valueM) >= giga {
            displayValue = valueM / giga
            unit = "G"
        } else if abs(valueM) >= 1.0 {
            displayValue = valueM
            unit = "M"
        } else if abs(valueM) >= kilo {
            displayValue = valueM / kilo
            unit = "K"
        } else {
            displayValue = valueM
            unit = "M"
        }
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.usesGroupingSeparator = false
        if unit == "T" || unit == "G" {
            numberFormatter.maximumFractionDigits = 2
        } else if unit == "M" {
            if abs(valueM) >= 1.0 || valueM == 0 {
                numberFormatter.maximumFractionDigits = 1
                if displayValue.truncatingRemainder(dividingBy: 1) == 0 {
                    numberFormatter.maximumFractionDigits = 0
                }
            } else {
                numberFormatter.maximumFractionDigits = 3
            }
        } else {
            numberFormatter.maximumFractionDigits = 0
        }
        numberFormatter.minimumFractionDigits = 0
        let formattedValueString =
            numberFormatter.string(from: NSNumber(value: displayValue)) ?? "\(displayValue)"
        return (value: formattedValueString, unit: unit)
    }

    func formattedHashRateWithUnit() -> (value: String, unit: String) {
        if self >= 1_000 {
            return ((self / 1_000).formatted(.number.precision(.fractionLength(1))), "TH/s")
        } else if self >= 1 {
            return (self.formatted(.number.precision(.fractionLength(1))), "GH/s")
        } else {
            return ((self * 1_000).formatted(.number.precision(.fractionLength(0))), "MH/s")
        }
    }

    func formattedExpectedHashRateWithUnit() -> (value: String, unit: String) {
        let absValue = abs(self)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if absValue >= 1000 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            return (
                formatter.string(from: NSNumber(value: self / 1000)) ?? "\(self / 1000)", "TH/s"
            )
        } else {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
            return (formatter.string(from: NSNumber(value: self)) ?? "\(self)", "GH/s")
        }
    }

    func formattedWithSuffix() -> (value: String, unit: String) {
        let units = ["", "K", "M", "B", "T", "P", "E"]
        var scaledValue = self
        var unitIndex = 0
        var absValue = abs(scaledValue)

        while absValue >= 1000.0, unitIndex < units.count - 1 {
            scaledValue /= 1000.0
            absValue /= 1000.0
            unitIndex += 1
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        switch absValue {
        case 100...:
            formatter.maximumFractionDigits = 0
        case 10...:
            formatter.maximumFractionDigits = 1
        default:
            formatter.maximumFractionDigits = 2
        }
        formatter.minimumFractionDigits = 0

        let formatted = formatter.string(from: NSNumber(value: scaledValue)) ?? "\(scaledValue)"
        return (formatted, units[unitIndex])
    }
}
