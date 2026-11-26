import SwiftUI

enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case codeBlock(language: String?, code: String)
    case bulletList(items: [String])
    case numberedList(items: [String])
    case blockquote(text: String)
    case table(headers: [String], rows: [[String]])
    case divider
    case paragraph(text: String)
}

enum MarkdownBlockParser {
    /// Parses Markdown text into block-level elements for read-only rendering.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count {
                    if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        index += 1
                        break
                    }
                    codeLines.append(lines[index])
                    index += 1
                }
                blocks.append(.codeBlock(language: language.isEmpty ? nil : language, code: codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                blocks.append(.divider)
                index += 1
                continue
            }

            if index + 1 < lines.count,
               let headers = parseTableRow(trimmed),
               isTableSeparator(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let rowTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    guard !rowTrimmed.isEmpty, let cells = parseTableRow(rowTrimmed) else { break }
                    let padded = (0..<headers.count).map { $0 < cells.count ? cells[$0] : "" }
                    rows.append(padded)
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let qTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    guard qTrimmed.hasPrefix(">") else { break }
                    var content = String(qTrimmed.dropFirst())
                    if content.hasPrefix(" ") { content = String(content.dropFirst()) }
                    quoteLines.append(content)
                    index += 1
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: " ")))
                continue
            }

            if bulletItemText(trimmed) != nil {
                var items: [String] = []
                while index < lines.count,
                      let item = bulletItemText(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            if numberedItemText(trimmed) != nil {
                var items: [String] = []
                while index < lines.count,
                      let item = numberedItemText(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.numberedList(items: items))
                continue
            }

            var paragraphLines: [String] = []
            while index < lines.count {
                let pTrimmed = lines[index].trimmingCharacters(in: .whitespaces)
                if pTrimmed.isEmpty
                    || pTrimmed.hasPrefix("```")
                    || pTrimmed.hasPrefix(">")
                    || parseHeading(pTrimmed) != nil
                    || isHorizontalRule(pTrimmed)
                    || bulletItemText(pTrimmed) != nil
                    || numberedItemText(pTrimmed) != nil
                    || (index + 1 < lines.count
                        && parseTableRow(pTrimmed) != nil
                        && isTableSeparator(lines[index + 1].trimmingCharacters(in: .whitespaces))) {
                    break
                }
                paragraphLines.append(pTrimmed)
                index += 1
            }
            blocks.append(.paragraph(text: paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    private static func parseHeading(_ line: String) -> MarkdownBlock? {
        var hashes = 0
        for ch in line {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard (1...4).contains(hashes) else { return nil }
        let remainder = line.dropFirst(hashes)
        guard remainder.first == " " else { return nil }
        let title = remainder.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return .heading(level: hashes, text: title)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3 else { return false }
        return compact.allSatisfy { $0 == "-" } || compact.allSatisfy { $0 == "*" } || compact.allSatisfy { $0 == "_" }
    }

    private static func bulletItemText(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func numberedItemText(_ line: String) -> String? {
        guard let dotIndex = line.firstIndex(of: ".") else { return nil }
        let numberPart = line[..<dotIndex]
        guard !numberPart.isEmpty, numberPart.allSatisfy(\.isNumber) else { return nil }
        let afterDot = line.index(after: dotIndex)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...])
    }

    private static func parseTableRow(_ line: String) -> [String]? {
        guard line.contains("|") else { return nil }
        var body = line
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        let cells = body
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard !cells.isEmpty else { return nil }
        return cells
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard let cells = parseTableRow(line), !cells.isEmpty else { return false }
        let validChars = CharacterSet(charactersIn: "-: ")
        return cells.allSatisfy { cell in
            cell.contains("-") && cell.unicodeScalars.allSatisfy { validChars.contains($0) }
        }
    }
}

struct GameReadmeSheet: View {
    let game: GameEntry
    let manager: BuildManager

    @Environment(\.dismiss) private var dismiss
    @State private var markdownContent: String?
    @State private var readmeURL: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var titleID: String? {
        manager.effectiveTitleID(for: game)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.md) {
            headerView

            Divider()

            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footerView
        }
        .padding(DesignSpacing.lg)
        .frame(minWidth: 680, idealWidth: 820, minHeight: 480, idealHeight: 640)
        .task(id: game.id) {
            loadReadme()
        }
    }

    private var headerView: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.sm) {
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                Text("NXNative README — \(manager.effectiveAppName(for: game))")
                    .font(.headline)
                    .lineLimit(1)

                if let readmeURL {
                    Text(readmeURL.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            if let titleID {
                Text("Title ID: \(titleID)")
                    .font(.caption.weight(.medium).monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignSpacing.sm)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if isLoading {
            VStack(spacing: DesignSpacing.sm) {
                ProgressView()
                Text("Loading README…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Unable to Read README", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") {
                    loadReadme()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let markdownContent, !markdownContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ScrollView {
                MarkdownDocumentView(markdown: markdownContent)
                    .padding(DesignSpacing.md)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        } else {
            ContentUnavailableView {
                Label("No NXNative README", systemImage: "doc.text")
            } description: {
                Text("No readme.md was found in the nxnative repository for this game.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footerView: some View {
        HStack {
            if let readmeURL {
                Button {
                    manager.revealInFinder(readmeURL)
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .help("Show readme.md in Finder")
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.cancelAction)
        }
    }

    private func loadReadme() {
        isLoading = true
        errorMessage = nil
        guard let titleID else {
            readmeURL = nil
            markdownContent = nil
            isLoading = false
            return
        }
        readmeURL = manager.readmeFileURL(for: titleID)
        do {
            markdownContent = try manager.readGameReadme(for: titleID)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct MarkdownDocumentView: View {
    let blocks: [MarkdownBlock]

    init(markdown: String) {
        self.blocks = MarkdownBlockParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSpacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineText(text)
                .font(headingFont(for: level))
                .padding(.top, level == 1 ? DesignSpacing.xs : DesignSpacing.sm)
        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                if let language {
                    Text(language)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(code)
                        .font(.callout.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(DesignSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1), in: .rect(cornerRadius: 6))
        case .bulletList(let items):
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.sm) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        inlineText(item)
                            .font(.body)
                    }
                }
            }
        case .numberedList(let items):
            VStack(alignment: .leading, spacing: DesignSpacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: DesignSpacing.sm) {
                        Text("\(idx + 1).")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        inlineText(item)
                            .font(.body)
                    }
                }
            }
        case .blockquote(let text):
            HStack(spacing: DesignSpacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.6))
                    .frame(width: 3)
                inlineText(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        case .table(let headers, let rows):
            markdownTable(headers: headers, rows: rows)
        case .divider:
            Divider()
                .padding(.vertical, DesignSpacing.xs)
        case .paragraph(let text):
            inlineText(text)
                .font(.body)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title2.weight(.bold)
        case 2: return .title3.weight(.semibold)
        case 3: return .headline
        default: return .subheadline.weight(.semibold)
        }
    }

    private func markdownTable(headers: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        inlineText(header)
                            .font(.callout.weight(.semibold))
                            .padding(.horizontal, DesignSpacing.sm)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(Color.secondary.opacity(0.1))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    Divider()
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            inlineText(cell)
                                .font(.callout)
                                .padding(.horizontal, DesignSpacing.sm)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .background(rowIdx.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.04))
                }
            }
            .clipShape(.rect(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            )
        }
    }

    private func inlineText(_ raw: String) -> Text {
        if var attributed = try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            for run in attributed.runs {
                if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                    attributed[run.range].font = .callout.monospaced()
                    attributed[run.range].backgroundColor = Color.secondary.opacity(0.18)
                }
            }
            return Text(attributed)
        }
        return Text(raw)
    }
}

#if DEBUG
#Preview("Markdown Document") {
    ScrollView {
        MarkdownDocumentView(markdown: """
        # Super Mario Odyssey

        Tested on **macOS** with `nxnative`.

        ## Known Issues
        - Disable vsync if frame pacing stutters
        - Requires `env.txt` override for docked mode

        > Note: Use a clean Base + Update dump.

        ```ini
        NXNATIVE_DOCKED=1
        ```
        """)
        .padding(16)
    }
    .frame(width: 560, height: 360)
}

#Preview("Missing README — Dark") {
    let manager = BuildManager(previewGames: [])
    if let sample = BuildManager.previewSample().games.first {
        GameReadmeSheet(game: sample, manager: manager)
            .preferredColorScheme(.dark)
    }
}
#endif
