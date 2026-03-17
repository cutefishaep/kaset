import Foundation

// MARK: - SyncedLyricLine

/// Represents a single line of synchronized lyrics
struct SyncedLyricLine: Identifiable, Equatable, Sendable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

// MARK: - SyncedLyrics

/// Represents synchronized lyrics with timing information.
struct SyncedLyrics: Equatable, Sendable {
    let lines: [SyncedLyricLine]
    let isSynced: Bool

    var isAvailable: Bool {
        !self.lines.isEmpty
    }

    /// Creates an empty lyrics instance.
    static let unavailable = SyncedLyrics(lines: [], isSynced: false)

    /// Parses LRC format text into `SyncedLyrics`.
    static func parse(lrc: String, offset: Double = 0.0) -> SyncedLyrics {
        var parsedLines: [SyncedLyricLine] = []
        let lines = lrc.components(separatedBy: .newlines)
        
        // Regex to match [mm:ss.xx] or [mm:ss:xx] or [mm:ss.xxx]
        let regex = try? NSRegularExpression(pattern: "\\[(\\d{2,}):(\\d{2})[\\.:](\\d{2,3})\\](.*)")
        
        var isSynced = false

        for line in lines {
            let nsString = line as NSString
            let results = regex?.matches(in: line, range: NSRange(location: 0, length: nsString.length)) ?? []
            
            if let match = results.first {
                isSynced = true
                let minStr = nsString.substring(with: match.range(at: 1))
                let secStr = nsString.substring(with: match.range(at: 2))
                let msStr = nsString.substring(with: match.range(at: 3))
                let text = nsString.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)

                if let minutes = Double(minStr),
                   let seconds = Double(secStr),
                   let milliseconds = Double(msStr) {
                    
                    // Milliseconds could be 2 or 3 digits
                    let msMultiplier = msStr.count == 2 ? 0.01 : 0.001
                    let time = max(0, ((minutes * 60.0) + seconds + (milliseconds * msMultiplier)) + offset)
                    
                    if !text.isEmpty {
                        parsedLines.append(SyncedLyricLine(time: time, text: text))
                    } else if !parsedLines.isEmpty {
                        // Empty line for spacing
                        parsedLines.append(SyncedLyricLine(time: time, text: " "))
                    }
                }
            } else if !isSynced {
                // If we haven't found any synced lines yet, just treat it as plain text at time 0
                let text = line.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    parsedLines.append(SyncedLyricLine(time: 0, text: text))
                }
            }
        }
        
        // Sort by time just in case
        parsedLines.sort { $0.time < $1.time }
        return SyncedLyrics(lines: parsedLines, isSynced: isSynced)
    }
}
