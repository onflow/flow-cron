/// FlowCronParser: A Cadence contract for computing next run timestamps 
/// from standard 5-field cron expressions on Flow blockchain.
///
/// CRON FORMAT: minute (0-59) hour (0-23) day-of-month (1-31) month (1-12) day-of-week (0-6, 0=Sun)
/// OPERATORS: * (wildcard), , (lists), - (ranges), / (steps including */n and a-b/n)
/// DOM/DOW SEMANTICS (Vixie rule): If both DOM and DOW constrained, day matches if DOM OR DOW matches
/// TIME BASIS: Flow blockchain canonical time (getCurrentBlock().timestamp), treated as UTC-like chain time
/// HORIZON: +5 years maximum lookahead from any given timestamp
///
access(all) contract FlowCronParser {

    /// Container for parsed cron specification as bitmasks
    access(all) struct CronSpec {
        access(all) let minMask: UInt64      // bits 0-59 for minutes
        access(all) let hourMask: UInt32     // bits 0-23 for hours  
        access(all) let domMask: UInt32      // bits 1-31 for day-of-month
        access(all) let monthMask: UInt16    // bits 1-12 for month
        access(all) let dowMask: UInt8       // bits 0-6 for day-of-week (0=Sunday)
        access(all) let domIsStar: Bool      // true if DOM field was "*"
        access(all) let dowIsStar: Bool      // true if DOW field was "*"

        init(
            minMask: UInt64, 
            hourMask: UInt32, 
            domMask: UInt32,
            monthMask: UInt16, 
            dowMask: UInt8, 
            domIsStar: Bool, 
            dowIsStar: Bool
        ) {
            self.minMask = minMask
            self.hourMask = hourMask
            self.domMask = domMask
            self.monthMask = monthMask
            self.dowMask = dowMask
            self.domIsStar = domIsStar
            self.dowIsStar = dowIsStar
        }
    }

    /// Parse a standard 5-field cron expression into CronSpec
    /// Supports operators: * , - / (including */n and a-b/n)
    access(all) fun parse(expression: String): CronSpec? {
        let fields = expression.split(separator: " ")
        if fields.length != 5 {
            return nil
        }

        // Access array elements safely
        let minField = fields[0]
        let hourField = fields[1]
        let domField = fields[2]
        let monthField = fields[3]
        let dowField = fields[4]

        let minMask = self.parseField(minField, 0, 59)
        let hourMask = self.parseField(hourField, 0, 23) 
        let domMask = self.parseField(domField, 1, 31)
        let monthMask = self.parseField(monthField, 1, 12)
        let dowMask = self.parseField(dowField, 0, 6)

        if minMask == nil || hourMask == nil || domMask == nil || monthMask == nil || dowMask == nil {
            return nil
        }

        return CronSpec(
            minMask: minMask!,
            hourMask: UInt32(hourMask! & 0xFFFFFF), // 24 bits
            domMask: UInt32(domMask! & 0xFFFFFFFE), // clear bit 0, use bits 1-31
            monthMask: UInt16(monthMask! & 0x1FFE), // clear bit 0, use bits 1-12
            dowMask: UInt8(dowMask! & 0x7F), // 7 bits
            domIsStar: domField == "*",
            dowIsStar: dowField == "*"
        )
    }

    /// Parse a single cron field into bitmask
    access(all) fun parseField(_ field: String, _ min: Int, _ max: Int): UInt64? {
        if field == "*" {
            return self.rangeMask(min, max)
        }

        var mask: UInt64 = 0
        let parts = field.split(separator: ",")
        
        for part in parts {
            let partMask = self.parseFieldPart(part, min, max)
            if partMask == nil {
                return nil
            }
            mask = mask | partMask!
        }
        
        return mask
    }

    /// Parse individual part of a field (handles -, /, */n, a-b/n)
    access(all) fun parseFieldPart(_ part: String, _ min: Int, _ max: Int): UInt64? {
        if part.contains("/") {
            let stepParts = part.split(separator: "/")
            if stepParts.length != 2 {
                return nil
            }
            
            let stepStr = stepParts[1]
            let step = self.parseInt(stepStr)
            if step == nil || step! <= 0 {
                return nil
            }

            let rangeStr = stepParts[0]
            var rangeMask: UInt64 = 0
            
            if rangeStr == "*" {
                rangeMask = self.rangeMask(min, max)
            } else if rangeStr.contains("-") {
                let rangeParts = rangeStr.split(separator: "-")
                if rangeParts.length != 2 {
                    return nil
                }
                let startStr = rangeParts[0]
                let endStr = rangeParts[1]
                let start = self.parseInt(startStr)
                let end = self.parseInt(endStr)
                if start == nil || end == nil || start! < min || end! > max {
                    return nil
                }
                rangeMask = self.rangeMask(start!, end!)
            } else {
                let start = self.parseInt(rangeStr)
                if start == nil || start! < min || start! > max {
                    return nil
                }
                rangeMask = UInt64(1) << UInt64(start!)
            }

            // Apply step filter
            var mask: UInt64 = 0
            var i = min
            while i <= max {
                if (rangeMask & (UInt64(1) << UInt64(i))) != 0 {
                    // Find the start of the range for step calculation
                    var rangeStart = min
                    if rangeStr != "*" && rangeStr.contains("-") {
                        let rangeParts = rangeStr.split(separator: "-")
                        let start = self.parseInt(rangeParts[0])
                        if start != nil {
                            rangeStart = start!
                        }
                    } else if rangeStr != "*" {
                        let start = self.parseInt(rangeStr)
                        if start != nil {
                            rangeStart = start!
                        }
                    }
                    
                    if (i - rangeStart) % step! == 0 {
                        mask = mask | (UInt64(1) << UInt64(i))
                    }
                }
                i = i + 1
            }
            return mask
        } else if part.contains("-") {
            let rangeParts = part.split(separator: "-")
            if rangeParts.length != 2 {
                return nil
            }
            let startStr = rangeParts[0]
            let endStr = rangeParts[1]
            let start = self.parseInt(startStr)
            let end = self.parseInt(endStr)
            if start == nil || end == nil || start! < min || end! > max {
                return nil
            }
            return self.rangeMask(start!, end!)
        } else {
            let value = self.parseInt(part)
            if value == nil || value! < min || value! > max {
                return nil
            }
            return UInt64(1) << UInt64(value!)
        }
    }

    /// Create bitmask for range [start, end]
    access(all) fun rangeMask(_ start: Int, _ end: Int): UInt64 {
        var mask: UInt64 = 0
        var i = start
        while i <= end {
            mask = mask | (UInt64(1) << UInt64(i))
            i = i + 1
        }
        return mask
    }

    /// Parse integer from string
    access(all) fun parseInt(_ str: String): Int? {
        if str.length == 0 {
            return nil
        }
        
        var result = 0
        var i = 0
        while i < str.length {
            let char = str[i]
            if char >= "0" && char <= "9" {
                let digit = Int(char.utf8[0]) - Int("0".utf8[0])
                result = result * 10 + digit
            } else {
                return nil
            }
            i = i + 1
        }
        return result
    }

    /// Core function: compute next run timestamp strictly greater than afterUnix
    /// Returns nil if no match found within +5 years horizon
    access(all) fun nextTick(spec: CronSpec, afterUnix: UInt64): UInt64? {
        // Round up to next minute boundary
        let roundedUp = afterUnix + 60 - (afterUnix % 60)
        let dateTime = self.ymdhmFromUnix(t: roundedUp)
        let year = dateTime.year
        let month = dateTime.month
        let day = dateTime.day
        let hour = dateTime.hour
        let minute = dateTime.minute
        
        let horizonYear = year + 5
        var currentY = year
        var currentM = month  
        var currentD = day
        var currentH = hour
        var currentMin = minute

        while currentY <= horizonYear {
            // Month step
            if !self.hasBit(mask: UInt64(spec.monthMask), pos: currentM) {
                let nextM = self.nextSetBit(mask: UInt64(spec.monthMask), pos: currentM, maxPos: 12)
                if nextM != nil && nextM! <= 12 {
                    currentM = nextM!
                    currentD = 1
                    currentH = 0
                    currentMin = 0
                } else {
                    // Carry to next year
                    currentY = currentY + 1
                    currentM = self.nextSetBit(mask: UInt64(spec.monthMask), pos: 1, maxPos: 12) ?? 1
                    currentD = 1
                    currentH = 0
                    currentMin = 0
                    continue
                }
            }

            // Day step with DOM/DOW logic
            let daysInCurrentMonth = self.daysInMonth(year: currentY, month: currentM)
            let allowedDayMask = self.getAllowedDayMask(spec, currentY, currentM, daysInCurrentMonth)
            
            if !self.hasBit(mask: UInt64(allowedDayMask), pos: currentD) {
                let nextD = self.nextSetBit(mask: UInt64(allowedDayMask), pos: currentD, maxPos: daysInCurrentMonth)
                if nextD != nil && nextD! <= daysInCurrentMonth {
                    currentD = nextD!
                    currentH = 0
                    currentMin = 0
                } else {
                    // Carry to next month
                    currentM = currentM + 1
                    currentD = 1
                    currentH = 0
                    currentMin = 0
                    continue
                }
            }

            // Hour step
            if !self.hasBit(mask: UInt64(spec.hourMask), pos: currentH) {
                let nextH = self.nextSetBit(mask: UInt64(spec.hourMask), pos: currentH, maxPos: 23)
                if nextH != nil && nextH! <= 23 {
                    currentH = nextH!
                    currentMin = 0
                } else {
                    // Carry to next day
                    currentD = currentD + 1
                    currentH = 0
                    currentMin = 0
                    continue
                }
            }

            // Minute step
            if !self.hasBit(mask: spec.minMask, pos: currentMin) {
                let nextMin = self.nextSetBit(mask: spec.minMask, pos: currentMin, maxPos: 59)
                if nextMin != nil && nextMin! <= 59 {
                    currentMin = nextMin!
                } else {
                    // Carry to next hour
                    currentH = currentH + 1
                    currentMin = 0
                    continue
                }
            }

            // All fields match - return the timestamp
            return self.unixFromYMDHM(y: currentY, m: currentM, d: currentD, h: currentH, mi: currentMin)
        }

        return nil // Exceeded horizon
    }

    /// Compute allowed day mask combining DOM and DOW per Vixie rule
    access(all) fun getAllowedDayMask(_ spec: CronSpec, _ year: Int, _ month: Int, _ daysInMonth: Int): UInt32 {
        if spec.domIsStar && spec.dowIsStar {
            // Both are *, all days allowed
            return self.rangeMask32(1, daysInMonth)
        } else if spec.domIsStar {
            // Only DOW matters
            return self.getDowMask(spec.dowMask, year, month, daysInMonth)
        } else if spec.dowIsStar {
            // Only DOM matters, clip to month length
            return spec.domMask & self.rangeMask32(1, daysInMonth)
        } else {
            // Both constrained: DOM OR DOW
            let domClipped = spec.domMask & self.rangeMask32(1, daysInMonth)
            let dowMask = self.getDowMask(spec.dowMask, year, month, daysInMonth)
            return domClipped | dowMask
        }
    }

    /// Get DOW mask for given month
    access(all) fun getDowMask(_ dowSpec: UInt8, _ year: Int, _ month: Int, _ daysInMonth: Int): UInt32 {
        var mask: UInt32 = 0
        var d = 1
        while d <= daysInMonth {
            let wd = self.weekday(year: year, month: month, day: d)
            if (dowSpec & (UInt8(1) << UInt8(wd))) != 0 {
                mask = mask | (UInt32(1) << UInt32(d))
            }
            d = d + 1
        }
        return mask
    }

    /// Create range mask for UInt32
    access(all) fun rangeMask32(_ start: Int, _ end: Int): UInt32 {
        var mask: UInt32 = 0
        var i = start
        while i <= end {
            mask = mask | (UInt32(1) << UInt32(i))
            i = i + 1
        }
        return mask
    }

    /// Utility: next run from current chain time
    access(all) fun nextFromChainNow(spec: CronSpec): UInt64? {
        // Note: getCurrentBlock().timestamp returns UFix64, convert to UInt64
        let currentTime = UInt64(getCurrentBlock().timestamp)
        return self.nextTick(spec: spec, afterUnix: currentTime)
    }

    /// Check if bit is set at position
    access(all) fun hasBit(mask: UInt64, pos: Int): Bool {
        return (mask & (UInt64(1) << UInt64(pos))) != 0
    }

    /// Find next set bit starting from pos (inclusive) up to maxPos
    access(all) fun nextSetBit(mask: UInt64, pos: Int, maxPos: Int): Int? {
        var i = pos
        while i <= maxPos {
            if (mask & (UInt64(1) << UInt64(i))) != 0 {
                return i
            }
            i = i + 1
        }
        return nil
    }

    // ===== Calendar helpers (integer-only, UTC-like chain time) =====

    /// DateTime struct for holding date/time components
    access(all) struct DateTime {
        access(all) let year: Int
        access(all) let month: Int
        access(all) let day: Int
        access(all) let hour: Int
        access(all) let minute: Int

        init(year: Int, month: Int, day: Int, hour: Int, minute: Int) {
            self.year = year
            self.month = month
            self.day = day
            self.hour = hour
            self.minute = minute
        }
    }

    /// Check if year is leap year
    access(all) fun isLeap(year: Int): Bool {
        return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
    }

    /// Get number of days in month
    access(all) fun daysInMonth(year: Int, month: Int): Int {
        switch month {
        case 1: return 31
        case 2: return self.isLeap(year: year) ? 29 : 28
        case 3: return 31
        case 4: return 30
        case 5: return 31
        case 6: return 30
        case 7: return 31
        case 8: return 31
        case 9: return 30
        case 10: return 31
        case 11: return 30
        case 12: return 31
        default: return 0
        }
    }

    /// Get weekday (0=Sunday, 1=Monday, ..., 6=Saturday)
    /// Using Doomsday algorithm variant
    access(all) fun weekday(year: Int, month: Int, day: Int): Int {
        // Simplified implementation using known reference point
        // January 1, 2000 was a Saturday (6)
        let refYear = 2000
        let refWeekday = 6
        
        var days = 0
        
        // Add days for complete years
        var y = refYear
        while y < year {
            days = days + (self.isLeap(year: y) ? 366 : 365)
            y = y + 1
        }
        
        // Subtract days if going backwards
        y = year
        while y < refYear {
            days = days - (self.isLeap(year: y) ? 366 : 365)
            y = y + 1
        }
        
        // Add days for complete months in target year
        var m = 1
        while m < month {
            days = days + self.daysInMonth(year: year, month: m)
            m = m + 1
        }
        
        // Add remaining days
        days = days + day - 1
        
        return (refWeekday + days) % 7
    }

    /// Convert Unix timestamp to DateTime struct
    access(all) fun ymdhmFromUnix(t: UInt64): DateTime {
        let secondsPerDay = 86400
        let secondsPerHour = 3600
        let secondsPerMinute = 60
        
        let days = Int(t / UInt64(secondsPerDay))
        let secondsInDay = Int(t % UInt64(secondsPerDay))
        
        let hour = secondsInDay / secondsPerHour
        let minute = (secondsInDay % secondsPerHour) / secondsPerMinute
        
        // Convert days since epoch to date (epoch = Jan 1, 1970)
        // This is a simplified version - for production use a more robust algorithm
        let epochYear = 1970
        var year = epochYear
        var remainingDays = days
        
        // Handle years
        while true {
            let daysInYear = self.isLeap(year: year) ? 366 : 365
            if remainingDays < daysInYear {
                break
            }
            remainingDays = remainingDays - daysInYear
            year = year + 1
        }
        
        // Handle months
        var month = 1
        while month <= 12 {
            let daysInCurrentMonth = self.daysInMonth(year: year, month: month)
            if remainingDays < daysInCurrentMonth {
                break
            }
            remainingDays = remainingDays - daysInCurrentMonth
            month = month + 1
        }
        
        let day = remainingDays + 1
        
        return DateTime(year: year, month: month, day: day, hour: hour, minute: minute)
    }
    
    /// SPECS-compliant function returning [year, month, day, hour, minute] array
    access(all) fun ymdhmFromUnixArray(t: UInt64): [Int] {
        let dt = self.ymdhmFromUnix(t: t)
        return [dt.year, dt.month, dt.day, dt.hour, dt.minute]
    }

    /// Convert (year, month, day, hour, minute) to Unix timestamp
    access(all) fun unixFromYMDHM(y: Int, m: Int, d: Int, h: Int, mi: Int): UInt64 {
        let epochYear = 1970
        var days = 0
        
        // Add days for complete years since epoch
        var year = epochYear
        while year < y {
            days = days + (self.isLeap(year: year) ? 366 : 365)
            year = year + 1
        }
        
        // Add days for complete months in target year
        var month = 1
        while month < m {
            days = days + self.daysInMonth(year: y, month: month)
            month = month + 1
        }
        
        // Add remaining days
        days = days + d - 1
        
        // Convert to seconds and add hour/minute
        let seconds = days * 86400 + h * 3600 + mi * 60
        
        return UInt64(seconds)
    }

    init() {}
}