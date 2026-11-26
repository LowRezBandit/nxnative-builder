import SwiftUI
import AppKit
import Observation
import OSLog
import UniformTypeIdentifiers

@MainActor
@Observable
final class LogViewerController {
    private static let logger = Logger(subsystem: "com.nxnative.builder", category: "LogViewer")
    var isSearchVisible = false
    var searchQuery = "" {
        didSet { updateMatches(jumpToFirst: true) }
    }
    var matchRanges: [NSRange] = []
    var currentMatchIndex = 0

    weak var textView: NSTextView?

    private static let errorRegex = try? NSRegularExpression(
        pattern: #"^.*(?:\[RED\]|✗|error:|fatal error:|Failed \(|FAILED).*$"#,
        options: [.anchorsMatchLines, .caseInsensitive]
    )

    func updateMatches(jumpToFirst: Bool = false) {
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
            highlightMatch(at: 0)
        } else {
            currentMatchIndex = min(currentMatchIndex, ranges.count - 1)
        }
    }

    func nextMatch() {
        guard !matchRanges.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % matchRanges.count
        highlightMatch(at: currentMatchIndex)
    }

    func previousMatch() {
        guard !matchRanges.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + matchRanges.count) % matchRanges.count
        highlightMatch(at: currentMatchIndex)
    }

    private func highlightMatch(at index: Int) {
        guard let textView, matchRanges.indices.contains(index) else { return }
        let range = matchRanges[index]
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
        textView.showFindIndicator(for: range)
    }

    func jumpToNextError() {
        guard let textView, let regex = Self.errorRegex else { return }
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
    var controller: LogViewerController

    private static let logFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)

    final class Coordinator {
        var lastText: String = ""
        var lastSourceKey: String = ""
        var lastRevision: Int = -1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = Self.logFont
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if controller.textView !== textView {
            controller.textView = textView
        }

        if context.coordinator.lastSourceKey == sourceKey && context.coordinator.lastRevision == revision {
            return
        }

        let previous = context.coordinator.lastText
        if context.coordinator.lastSourceKey == sourceKey && !previous.isEmpty && text.hasPrefix(previous), let storage = textView.textStorage {
            let delta = String(text.dropFirst(previous.count))
            storage.beginEditing()
            storage.append(Self.attributedLogString(for: delta))
            storage.endEditing()
        } else if let storage = textView.textStorage {
            storage.setAttributedString(Self.attributedLogString(for: text))
        } else {
            textView.string = text
        }

        context.coordinator.lastText = text
        context.coordinator.lastSourceKey = sourceKey
        context.coordinator.lastRevision = revision
        if !controller.searchQuery.isEmpty {
            controller.updateMatches(jumpToFirst: false)
        }
        if autoScroll {
            textView.scrollToEndOfDocument(nil)
        }
    }

    private static let redLineRegex = try? NSRegularExpression(
        pattern: #"^.*\[RED\].*$"#,
        options: [.anchorsMatchLines]
    )

    private static func attributedLogString(for text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: logFont,
                .foregroundColor: NSColor.textColor
            ]
        )
        if let regex = redLineRegex {
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            for match in regex.matches(in: text, range: fullRange) {
                attributed.addAttributes([
                    .foregroundColor: NSColor.systemRed,
                    .backgroundColor: NSColor.systemRed.withAlphaComponent(0.10)
                ], range: match.range)
            }
        }
        return attributed
    }
}
