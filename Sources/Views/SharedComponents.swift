import AppKit
import SwiftUI

enum DesignSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
}

enum DesignLayout {
    static let gameCardHeight: CGFloat = 252
}

struct PanelHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    var badgeCount: Int?
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        systemImage: String,
        badgeCount: Int? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.systemImage = systemImage
        self.badgeCount = badgeCount
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: DesignSpacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.caption.weight(.semibold))

                if let badgeCount, badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.14), in: Capsule())
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: DesignSpacing.sm)

            trailing()
        }
        .padding(.horizontal, DesignSpacing.md)
        .padding(.vertical, 6)
        .frame(minHeight: 36)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
}

extension View {
    func panelToolbarStyle(hasBackground: Bool = false) -> some View {
        self
            .padding(.horizontal, DesignSpacing.md)
            .padding(.vertical, 5)
            .frame(minHeight: 34)
            .background(hasBackground ? Color(nsColor: .controlBackgroundColor).opacity(0.6) : Color.clear)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(CGFloat(0)) { partial, row in
            partial + row.height + (partial > 0 ? rowSpacing : 0)
        }
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let itemY = y + (row.height - item.size.height) / 2
                item.subview.place(
                    at: CGPoint(x: x, y: itemY),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let neededWidth = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty && neededWidth > maxWidth {
                rows.append(current)
                current = Row(items: [RowItem(subview: subview, size: size)], width: size.width, height: size.height)
            } else {
                current.items.append(RowItem(subview: subview, size: size))
                current.width = neededWidth
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

extension Notification.Name {
    static let resetLayout = Notification.Name("NXNativeBuilderResetLayout")
}

struct PersistentSplitView<First: View, Second: View>: NSViewControllerRepresentable {
    let isVertical: Bool
    let autosaveName: String
    let defaultPosition: (CGSize) -> CGFloat
    let minFirstThickness: CGFloat
    let minSecondThickness: CGFloat
    @ViewBuilder let first: () -> First
    @ViewBuilder let second: () -> Second

    func makeNSViewController(context: Context) -> SplitController {
        SplitController(
            isVertical: isVertical,
            autosaveName: autosaveName,
            defaultPosition: defaultPosition,
            minFirstThickness: minFirstThickness,
            minSecondThickness: minSecondThickness,
            firstView: first(),
            secondView: second()
        )
    }

    func updateNSViewController(_ controller: SplitController, context: Context) {
        controller.firstHosting.rootView = first()
        controller.secondHosting.rootView = second()
    }

    final class SplitController: NSSplitViewController {
        let isVertical: Bool
        let autosaveName: String
        let defaultPosition: (CGSize) -> CGFloat
        let minFirstThickness: CGFloat
        let minSecondThickness: CGFloat
        let firstHosting: NSHostingController<First>
        let secondHosting: NSHostingController<Second>
        private var hasAppliedInitialPosition = false

        init(
            isVertical: Bool,
            autosaveName: String,
            defaultPosition: @escaping (CGSize) -> CGFloat,
            minFirstThickness: CGFloat,
            minSecondThickness: CGFloat,
            firstView: First,
            secondView: Second
        ) {
            self.isVertical = isVertical
            self.autosaveName = autosaveName
            self.defaultPosition = defaultPosition
            self.minFirstThickness = minFirstThickness
            self.minSecondThickness = minSecondThickness
            self.firstHosting = NSHostingController(rootView: firstView)
            self.secondHosting = NSHostingController(rootView: secondView)
            self.firstHosting.sizingOptions = []
            self.secondHosting.sizingOptions = []
            super.init(nibName: nil, bundle: nil)

            let firstItem = NSSplitViewItem(viewController: firstHosting)
            firstItem.minimumThickness = minFirstThickness
            firstItem.canCollapse = false
            let secondItem = NSSplitViewItem(viewController: secondHosting)
            secondItem.minimumThickness = minSecondThickness
            secondItem.canCollapse = false

            addSplitViewItem(firstItem)
            addSplitViewItem(secondItem)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            splitView.isVertical = isVertical
            splitView.dividerStyle = .thin
            super.viewDidLoad()
            splitView.autosaveName = autosaveName
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleResetLayout),
                name: .resetLayout,
                object: nil
            )
        }

        private func clampedPosition(_ proposed: CGFloat) -> CGFloat {
            let total = isVertical ? splitView.bounds.width : splitView.bounds.height
            let maxAllowed = total - minSecondThickness - splitView.dividerThickness
            guard maxAllowed >= minFirstThickness else {
                return proposed
            }
            return min(max(proposed, minFirstThickness), maxAllowed)
        }

        @objc private func handleResetLayout() {
            let defaultsKey = "NSSplitView Subview Frames \(autosaveName)"
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            splitView.layoutSubtreeIfNeeded()
            splitView.setPosition(clampedPosition(defaultPosition(splitView.bounds.size)), ofDividerAt: 0)
        }

        override func viewDidAppear() {
            super.viewDidAppear()
            guard !hasAppliedInitialPosition else { return }
            hasAppliedInitialPosition = true
            let defaultsKey = "NSSplitView Subview Frames \(autosaveName)"
            splitView.layoutSubtreeIfNeeded()
            if UserDefaults.standard.array(forKey: defaultsKey) == nil {
                splitView.setPosition(clampedPosition(defaultPosition(splitView.bounds.size)), ofDividerAt: 0)
            } else {
                let currentThickness = isVertical ? firstHosting.view.frame.width : firstHosting.view.frame.height
                let clamped = clampedPosition(currentThickness)
                if abs(clamped - currentThickness) > 1 {
                    splitView.setPosition(clamped, ofDividerAt: 0)
                }
            }
        }
    }
}
