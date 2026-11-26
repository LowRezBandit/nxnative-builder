import SwiftUI
import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers

enum LogFormatter {
    struct ANSIState: Equatable {
        var foreground: NSColor?
        var background: NSColor?
        var isBold = false
        var isDim = false

        static let `default` = ANSIState()
    }

    private static let ansiSGRRegex = try? NSRegularExpression(
        pattern: #"\x1B\[([0-9;]*)m"#
    )
    private static let anyANSIRegex = try? NSRegularExpression(
        pattern: #"\x1B(?:\[[0-9;?]*[ -/]*[@-~]|\][^\x07\x1B]*(?:\x07|\x1B\\))"#
    )
    private static let bannerRegex = try? NSRegularExpression(
        pattern: #"^===\s+.+===$"#,
        options: [.anchorsMatchLines]
    )
    static let errorRegex = try? NSRegularExpression(
        pattern: #"^.*(?:\[RED\]|✗|error:|fatal error:|Failed \(|FAILED).*$"#,
        options: [.anchorsMatchLines, .caseInsensitive]
    )
    static let warningRegex = try? NSRegularExpression(
        pattern: #"^.*\bwarning:.*$"#,
        options: [.anchorsMatchLines, .caseInsensitive]
    )
    static let issueRegex = try? NSRegularExpression(
        pattern: #"^.*(?:\[RED\]|✗|error:|fatal error:|Failed \(|FAILED|\bwarning:).*$"#,
        options: [.anchorsMatchLines, .caseInsensitive]
    )
    private static let noteRegex = try? NSRegularExpression(
        pattern: #"^.*\bnote:.*$"#,
        options: [.anchorsMatchLines, .caseInsensitive]
    )
    private static let runningCmdRegex = try? NSRegularExpression(
        pattern: #"^(Running:\s+)(.+)$"#,
        options: [.anchorsMatchLines]
    )
    private static let stepBracketRegex = try? NSRegularExpression(
        pattern: #"\[\d+/\d+\]"#
    )
    private static let checkMarkRegex = try? NSRegularExpression(
        pattern: #"(?:^|\s)[✓]"#,
        options: [.anchorsMatchLines]
    )

    static func stripANSI(_ text: String) -> String {
        guard let regex = anyANSIRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    static func countIssues(in rawText: String) -> Int {
        let clean = stripANSI(rawText)
        guard !clean.isEmpty, let regex = issueRegex else { return 0 }
        let range = NSRange(location: 0, length: (clean as NSString).length)
        return regex.numberOfMatches(in: clean, range: range)
    }

    static func filterIssueLines(in rawText: String) -> String {
        guard !rawText.isEmpty, let regex = issueRegex else { return "" }
        var matchedLines: [String] = []
        rawText.enumerateLines { line, _ in
            let cleanLine = stripANSI(line)
            let range = NSRange(location: 0, length: (cleanLine as NSString).length)
            if regex.firstMatch(in: cleanLine, range: range) != nil {
                matchedLines.append(line)
            }
        }
        return matchedLines.isEmpty ? "" : matchedLines.joined(separator: "\n") + "\n"
    }

    static func attributedString(
        for rawText: String,
        fontSize: CGFloat,
        initialState: ANSIState = .default
    ) -> (attributed: NSAttributedString, endState: ANSIState) {
        let regularFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.22

        let result = NSMutableAttributedString()
        var state = initialState
        let nsRaw = rawText as NSString
        var cursor = 0

        if let sgrRegex = ansiSGRRegex {
            let fullRange = NSRange(location: 0, length: nsRaw.length)
            for match in sgrRegex.matches(in: rawText, range: fullRange) {
                if match.range.location > cursor {
                    let segment = nsRaw.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                    appendSegment(segment, state: state, regularFont: regularFont, boldFont: boldFont, paragraphStyle: paragraphStyle, to: result)
                }
                let codeString = match.range(at: 1).location != NSNotFound
                    ? nsRaw.substring(with: match.range(at: 1))
                    : ""
                applySGR(codeString, to: &state)
                cursor = match.range.location + match.range.length
            }
        }

        if cursor < nsRaw.length {
            let tail = nsRaw.substring(from: cursor)
            appendSegment(tail, state: state, regularFont: regularFont, boldFont: boldFont, paragraphStyle: paragraphStyle, to: result)
        }

        applySemanticHighlighting(to: result, boldFont: boldFont)
        return (result, state)
    }

    private static func appendSegment(
        _ segment: String,
        state: ANSIState,
        regularFont: NSFont,
        boldFont: NSFont,
        paragraphStyle: NSParagraphStyle,
        to target: NSMutableAttributedString
    ) {
        guard !segment.isEmpty else { return }
        let baseColor = state.foreground ?? NSColor.labelColor
        let fgColor: NSColor
        if state.isDim {
            fgColor = state.foreground != nil ? baseColor.withAlphaComponent(0.72) : NSColor.secondaryLabelColor
        } else {
            fgColor = baseColor
        }

        var attrs: [NSAttributedString.Key: Any] = [
            .font: state.isBold ? boldFont : regularFont,
            .foregroundColor: fgColor,
            .paragraphStyle: paragraphStyle
        ]
        if let bg = state.background {
            attrs[.backgroundColor] = bg
        }
        target.append(NSAttributedString(string: segment, attributes: attrs))
    }

    private static func applySGR(_ codesText: String, to state: inout ANSIState) {
        let codes = codesText.isEmpty ? [0] : codesText.split(separator: ";").compactMap { Int($0) }
        if codes.isEmpty {
            state = .default
            return
        }
        for code in codes {
            switch code {
            case 0:
                state = .default
            case 1:
                state.isBold = true
            case 2:
                state.isDim = true
            case 22:
                state.isBold = false
                state.isDim = false
            case 30:
                state.foreground = NSColor.labelColor.withAlphaComponent(0.75)
            case 31, 91:
                state.foreground = NSColor.systemRed
            case 32, 92:
                state.foreground = NSColor.systemGreen
            case 33, 93:
                state.foreground = NSColor.systemOrange
            case 34, 94:
                state.foreground = NSColor.systemBlue
            case 35, 95:
                state.foreground = NSColor.systemPurple
            case 36, 96:
                state.foreground = NSColor.systemTeal
            case 37, 97:
                state.foreground = NSColor.labelColor
            case 90:
                state.foreground = NSColor.secondaryLabelColor
            case 39:
                state.foreground = nil
            case 40:
                state.background = NSColor.labelColor.withAlphaComponent(0.08)
            case 41, 101:
                state.background = NSColor.systemRed.withAlphaComponent(0.16)
            case 42, 102:
                state.background = NSColor.systemGreen.withAlphaComponent(0.16)
            case 43, 103:
                state.background = NSColor.systemOrange.withAlphaComponent(0.16)
            case 44, 104:
                state.background = NSColor.systemBlue.withAlphaComponent(0.16)
            case 45, 105:
                state.background = NSColor.systemPurple.withAlphaComponent(0.16)
            case 46, 106:
                state.background = NSColor.systemTeal.withAlphaComponent(0.16)
            case 47, 107:
                state.background = NSColor.labelColor.withAlphaComponent(0.12)
            case 49:
                state.background = nil
            default:
                break
            }
        }
    }

    private static func applySemanticHighlighting(to attributed: NSMutableAttributedString, boldFont: NSFont) {
        let plain = attributed.string
        let fullRange = NSRange(location: 0, length: (plain as NSString).length)
        guard fullRange.length > 0 else { return }

        if let regex = runningCmdRegex {
            for match in regex.matches(in: plain, range: fullRange) {
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range(at: 1))
                attributed.addAttribute(.font, value: boldFont, range: match.range(at: 2))
            }
        }

        if let regex = stepBracketRegex {
            for match in regex.matches(in: plain, range: fullRange) {
                attributed.addAttributes([
                    .foregroundColor: NSColor.controlAccentColor,
                    .font: boldFont
                ], range: match.range)
            }
        }

        if let regex = checkMarkRegex {
            for match in regex.matches(in: plain, range: fullRange) {
                attributed.addAttributes([
                    .foregroundColor: NSColor.systemGreen,
                    .font: boldFont
                ], range: match.range)
            }
        }

        if let regex = noteRegex {
            for match in regex.matches(in: plain, range: fullRange) {
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: match.range)
            }
        }

        if let regex = warningRegex {
            for match in regex.matches(in: plain, range: fullRange) {
                attributed.addAttributes([
                    .foregroundColor: NSColor.systemOrange,
                    .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.08)
                ], range: match.range)
            }
        }

        if let regex = errorRegex {
            for match in regex.matches(in: plain, range: fullRange) {
                attributed.addAttributes([
                    .foregroundColor: NSColor.systemRed,
                    .backgroundColor: NSColor.systemRed.withAlphaComponent(0.10)
                ], range: match.range)
            }
        }

        if let regex = bannerRegex {
            let nsPlain = plain as NSString
            for match in regex.matches(in: plain, range: fullRange) {
                let lineText = nsPlain.substring(with: match.range)
                let tint: NSColor
                if lineText.contains("Finished") && lineText.contains("exit 0") {
                    tint = NSColor.systemGreen
                } else if lineText.contains("Failed") {
                    tint = NSColor.systemRed
                } else if lineText.contains("Cancelled") {
                    tint = NSColor.systemOrange
                } else {
                    tint = NSColor.controlAccentColor
                }
                attributed.addAttributes([
                    .font: boldFont,
                    .foregroundColor: tint,
                    .backgroundColor: tint.withAlphaComponent(0.10)
                ], range: match.range)
            }
        }
    }
}

@MainActor
@Observable
final class LogViewerController {
    private static let logger = Logger(subsystem: "com.nxnative.builder", category: "LogViewer")
    var isSearchVisible = false {
        didSet {
            if !isSearchVisible {
                clearSearchHighlights()
            }
        }
    }
    var searchQuery = "" {
        didSet { updateMatches(jumpToFirst: true) }
    }
    var matchRanges: [NSRange] = []
    var currentMatchIndex = 0

    weak var textView: NSTextView?

    func updateMatches(jumpToFirst: Bool = false) {
        clearSearchHighlights()
        guard let textView, !searchQuery.isEmpty else {
            matchRanges = []
            currentMatchIndex = 0
            return
        }

        let content = textView.string as NSString
        var ranges: [NSRange] = []
        var searchStart = 0
        while searchStart < content.length {
            let searchRange = NSRange(location: searchStart, length: content.length - searchStart)
            let found = content.range(of: searchQuery, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound { break }
            ranges.append(found)
            searchStart = found.location + max(found.length, 1)
        }

        matchRanges = ranges
        if ranges.isEmpty {
            currentMatchIndex = 0
        } else if jumpToFirst {
            currentMatchIndex = 0
            applySearchHighlights()
            highlightMatch(at: 0)
        } else {
            currentMatchIndex = min(currentMatchIndex, ranges.count - 1)
            applySearchHighlights()
        }
    }

    func nextMatch() {
        guard !matchRanges.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchRanges.count
        applySearchHighlights()
        highlightMatch(at: currentMatchIndex)
    }

    func previousMatch() {
        guard !matchRanges.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchRanges.count) % matchRanges.count
        applySearchHighlights()
        highlightMatch(at: currentMatchIndex)
    }

    private func clearSearchHighlights() {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        let fullLength = (textView.string as NSString).length
        guard fullLength > 0 else { return }
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: fullLength))
    }

    private func applySearchHighlights() {
        guard let textView, let layoutManager = textView.layoutManager else { return }
        clearSearchHighlights()
        let contentLength = (textView.string as NSString).length
        for (index, range) in matchRanges.enumerated() {
            guard range.location + range.length <= contentLength else { continue }
            let isCurrent = index == currentMatchIndex
            let color = NSColor.systemYellow.withAlphaComponent(isCurrent ? 0.52 : 0.24)
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
    }

    private func highlightMatch(at index: Int) {
        guard let textView, matchRanges.indices.contains(index) else { return }
        let range = matchRanges[index]
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    func jumpToNextError() {
        guard let textView, let regex = LogFormatter.errorRegex else { return }
        let content = textView.string as NSString
        guard content.length > 0 else { return }

        let currentEnd = textView.selectedRange().location + textView.selectedRange().length
        let startLocation = currentEnd < content.length ? currentEnd : 0

        let firstRange = NSRange(location: startLocation, length: content.length - startLocation)
        var match = regex.firstMatch(in: textView.string, range: firstRange)
        if match == nil && startLocation > 0 {
            let wrapRange = NSRange(location: 0, length: content.length)
            match = regex.firstMatch(in: textView.string, range: wrapRange)
        }

        if let match {
            textView.setSelectedRange(match.range)
            textView.scrollRangeToVisible(match.range)
            textView.showFindIndicator(for: match.range)
        } else {
            NSSound.beep()
        }
    }

    func saveLog(_ text: String, defaultName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(defaultName).log"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Self.logger.error("Failed to save log to \(url.path): \(error.localizedDescription)")
                NSSound.beep()
            }
        }
    }
}

struct LogTextView: NSViewRepresentable {
    let text: String
    let sourceKey: String
    let revision: Int
    let autoScroll: Bool
    let fontSize: CGFloat
    let wrapLines: Bool
    let filterIssuesOnly: Bool
    var controller: LogViewerController

    final class Coordinator {
        var lastText: String = ""
        var lastSourceKey: String = ""
        var lastRevision: Int = -1
        var lastFontSize: CGFloat = 11.5
        var lastWrapLines: Bool = true
        var lastFilterIssuesOnly: Bool = false
        var ansiState: LogFormatter.ANSIState = .default
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.isVerticallyResizable = true

        applyWrapConfiguration(wrapLines, to: textView, in: scrollView)

        scrollView.documentView = textView
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if controller.textView !== textView {
            controller.textView = textView
        }

        let coordinator = context.coordinator
        if coordinator.lastWrapLines != wrapLines {
            applyWrapConfiguration(wrapLines, to: textView, in: scrollView)
            coordinator.lastWrapLines = wrapLines
        }

        let needsReload = coordinator.lastSourceKey != sourceKey
            || coordinator.lastRevision != revision
            || coordinator.lastFontSize != fontSize
            || coordinator.lastFilterIssuesOnly != filterIssuesOnly

        guard needsReload else { return }

        let displaySource = filterIssuesOnly ? LogFormatter.filterIssueLines(in: text) : text
        let canAppend = coordinator.lastSourceKey == sourceKey
            && coordinator.lastFontSize == fontSize
            && !filterIssuesOnly
            && !coordinator.lastFilterIssuesOnly
            && !coordinator.lastText.isEmpty
            && displaySource.hasPrefix(coordinator.lastText)

        if canAppend, let storage = textView.textStorage {
            let delta = String(displaySource.dropFirst(coordinator.lastText.count))
            let formatted = LogFormatter.attributedString(
                for: delta,
                fontSize: fontSize,
                initialState: coordinator.ansiState
            )
            storage.beginEditing()
            storage.append(formatted.attributed)
            storage.endEditing()
            coordinator.ansiState = formatted.endState
        } else if let storage = textView.textStorage {
            let formatted = LogFormatter.attributedString(for: displaySource, fontSize: fontSize)
            storage.setAttributedString(formatted.attributed)
            coordinator.ansiState = formatted.endState
        } else {
            textView.string = LogFormatter.stripANSI(displaySource)
            coordinator.ansiState = .default
        }

        coordinator.lastText = displaySource
        coordinator.lastSourceKey = sourceKey
        coordinator.lastRevision = revision
        coordinator.lastFontSize = fontSize
        coordinator.lastFilterIssuesOnly = filterIssuesOnly

        if !controller.searchQuery.isEmpty {
            controller.updateMatches(jumpToFirst: false)
        }
        if autoScroll {
            textView.scrollToEndOfDocument(nil)
        }
    }

    private func applyWrapConfiguration(_ wrap: Bool, to textView: NSTextView, in scrollView: NSScrollView) {
        scrollView.hasHorizontalScroller = !wrap
        textView.isHorizontallyResizable = !wrap
        textView.textContainer?.widthTracksTextView = wrap
        if wrap {
            textView.autoresizingMask = [.width]
            let contentWidth = max(scrollView.contentSize.width, 100)
            textView.frame.size.width = contentWidth
            textView.textContainer?.containerSize = NSSize(width: contentWidth, height: .greatestFiniteMagnitude)
        } else {
            textView.autoresizingMask = []
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
    }
}
