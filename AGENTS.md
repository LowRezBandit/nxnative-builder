## Code Modification & Approval Gate

**Default Mode: Read-Only.** You must not create, edit, delete, or rename any application files without explicit user approval through the workflow below.

Whenever a user requests code changes, features, or refactoring, you must follow these steps in strict order:

1. **Review User Request:** Inspect the relevant codebase files in read-only mode to understand the context, dependencies, and scope of the request. Ensure Forbidden Anti-Patterns are strictly adhered to.
2. **Grill User for Details:** Ask concise, targeted clarifying questions to resolve any ambiguities, edge cases, architectural choices, or missing requirements before drafting a plan. Do not proceed until the user answers. _(Skip this step only if the request is already 100% unambiguous.)_
3. **Build Execution Plan:** Draft a structured execution plan outlining:
   - Summary of the goal and confirmed requirements.
   - Main changes to be made (grouped by file path, including key logic/functions affected).
   - Potential risks, edge cases, or verification steps.
4. **Display Plan & Request Decision:** Present the execution plan to the user and halt execution. Prompt the user to choose one of the following options:
   - **1) Proceed to Build:** Approve the plan and begin modifying files.
   - **2) Save Execution Plan for Handoff:** Save the plan as a Markdown file inside `/docs` (e.g., `/docs/plan-<feature-or-task-name>.md`) without modifying any source code, then stop.
   - **3) Write in Additional Changes:** Incorporate user feedback/adjustments and repeat Steps 3–4.
   - **4) Cancel Planning and Execution:** Discard the plan and make no changes.
5. **Execute Build & Display Results:** Only after the user explicitly selects **Option 1**, apply the code changes according to the approved plan. Upon completion, display a clear summary of all modified/created files and any test or verification results.

### Permitted Read-Only Actions (No Approval Required)

- Reading files, searching the codebase, and checking git status or history.
- Running non-destructive read-only checks (linters, type-checks, or tests that do not alter files).

### High-Risk Actions (Always Require Separate Confirmation)

Even during Step 5 (Build), pause and ask for explicit confirmation before:

- Deleting existing files or directories.
- Modifying environment variables, secrets, CI/CD pipelines, or dependency lockfiles.
- Running database migrations or destructive git commands (`reset`, `clean`, `push --force`).

## Anti-Patterns (Forbidden)

Do not generate code matching the "Wrong" examples below. Always use the "Right" idiomatic Swift 6+ / modern macOS equivalents.

### 1. Swift Concurrency & Data Races

- **Never** use `DispatchQueue.main.async` or completion handlers for new asynchronous code.
- **Never** use `@unchecked Sendable` to silence compiler warnings without a verified lock/synchronization mechanism.
- **Never** mark an entire class `@MainActor` if only UI-bound properties need main-thread isolation.

// ❌ Wrong
DispatchQueue.global().async {
let data = fetchItems()
DispatchQueue.main.async {
self.items = data
}
}

// ✅ Right
Task {
let data = await fetchItems()
await MainActor.run {
self.items = data
}
}

### 2. Legacy Observation & State Management

- **Never** use `ObservableObject`, `@Published`, `@StateObject`, or `@ObservedObject` in new SwiftUI views.
- **Never** initialize an `@Observable` model inside a view body without `@State`.

// ❌ Wrong
class ViewModel: ObservableObject {
@Published var count = 0
}
struct CounterView: View {
@StateObject private var vm = ViewModel()
var body: some View { Text("\(vm.count)") }
}

// ✅ Right
@Observable
final class ViewModel {
var count = 0
}
struct CounterView: View {
@State private var vm = ViewModel()
var body: some View { Text("\(vm.count)") }
}

### 3. Deprecated SwiftUI Modifiers & Navigation

- **Never** use `NavigationView`; always use `NavigationStack` or `NavigationSplitView`.
- **Never** use `.foregroundColor(...)` or `.cornerRadius(...)`; use `.foregroundStyle(...)` and `.clipShape(.rect(cornerRadius:))`.
- **Never** use `GeometryReader` just to read screen bounds or proportional sizing when `containerRelativeFrame()` or `VisualEffect` suffices.

### 4. Error Swallowing & Force Unwrapping

- **Never** force-unwrap (`!`) optionals or use `try!` in production targets.
- **Never** write empty `catch {}` blocks that silently discard errors.

// ❌ Wrong
let url = URL(string: endpoint)!
do {
try save(data)
} catch {}

// ✅ Right
guard let url = URL(string: endpoint) else {
throw NetworkError.invalidURL(endpoint)
}
do {
try save(data)
} catch {
logger.error("Failed to save data: \(error.localizedDescription)")
throw error
}

### 5. Legacy Testing Frameworks

- **Never** write new unit tests using `import XCTest` or `XCTAssert*` assertions unless testing UI (`XCUIApplication`).
- **Always** use the `Testing` framework (`@Test`, `#expect`, `#require`).

### 6. Hardcoded Styling & Missing Semantic Tokens

- **Never** use hardcoded hex colors, `Color(red:green:blue:)`, or fixed `.font(.system(size:))` in UI views.
- **Never** use arbitrary magic numbers for padding, spacing, or radii when a semantic token or 4pt/8pt scale applies.
- **Always** use `DesignSpacing` (`xs`, `sm`, `md`, `lg`) from `SharedComponents.swift`, semantic colors (`Color.primary`, `.secondary`, `Color.accentColor`, `Color(nsColor: .controlBackgroundColor)`), and Dynamic Type text styles (`.caption`, `.callout`, `.body`, `.headline`).

```swift
// ❌ Wrong
Text("Build Ready")
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(Color(red: 0.2, green: 0.2, blue: 0.2))
    .padding(10)

// ✅ Right
Text("Build Ready")
    .font(.callout.weight(.medium))
    .foregroundStyle(.primary)
    .padding(DesignSpacing.sm)
```

### 7. macOS Native Feel & iOS-isms

- **Never** apply iOS-only conventions to macOS views (e.g., 44×44pt touch-target minimums, mobile bottom tab bars, or custom window/navigation chrome when native macOS controls exist).
- **Always** prefer native macOS containers and patterns (`NavigationSplitView`, `Settings`, `.toolbar`, `.sheet`, `.inspector`, and `PersistentSplitView` / `PanelHeader` where established).
- **Always** support standard macOS desktop ergonomics: resizable panes with sensible minimum widths/heights, `.help(...)` tooltips on icon-only controls, and native context menus.

### 8. UX States, Destructive Actions & Accessibility

- **Never** execute destructive actions (deleting files, clearing caches, cancelling active builds) without a `.confirmationDialog` or explicit user confirmation.
- **Never** leave views without explicit empty (`ContentUnavailableView`), loading (`ProgressView`), and actionable error states.
- **Never** rely on color alone to communicate state (pair color with an SF Symbol, label, or badge).
- **Always** provide `.accessibilityLabel(...)`, `.accessibilityHint(...)`, or `.accessibilityElement(children: .combine)` on icon-only buttons and composite rows, plus keyboard shortcuts (`.keyboardShortcut(...)`) and `@FocusState` where appropriate.

```swift
// ❌ Wrong
Button(role: .destructive) {
    clearAllLogs()
} label: {
    Image(systemName: "trash")
}

// ✅ Right
Button(role: .destructive) {
    isConfirmingClear = true
} label: {
    Label("Clear Logs", systemImage: "trash")
}
.labelStyle(.iconOnly)
.help("Clear all build logs")
.accessibilityLabel("Clear all build logs")
.confirmationDialog("Clear all build logs?", isPresented: $isConfirmingClear) {
    Button("Clear Logs", role: .destructive) { clearAllLogs() }
}
```

### 9. SwiftUI View Performance & Previews

- **Never** perform heavy computation, sorting, file I/O, or state mutation inside a view's `body`.
- **Never** render large or unbounded collections with `ForEach` inside a plain `VStack`/`HStack`; use `List`, `Table`, or `LazyVStack`/`LazyHStack`.
- **Always** extract complex `body` sections into focused subviews or `ViewModifier`s, and include `#Preview` blocks covering edge cases (empty state, long/truncating text, and light/dark appearance).
