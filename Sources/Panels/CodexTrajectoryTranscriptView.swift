import AppKit
import CodexTrajectory
import SwiftUI

struct CodexTrajectoryTranscriptView: NSViewRepresentable {
    var items: [CodexAppServerTranscriptItem]

    func makeNSView(context: Context) -> CodexTrajectoryTranscriptScrollView {
        CodexTrajectoryTranscriptScrollView()
    }

    func updateNSView(_ nsView: CodexTrajectoryTranscriptScrollView, context: Context) {
        nsView.update(entries: CodexTrajectoryTranscriptDisplayEntry.entries(from: items))
    }
}

fileprivate enum CodexTrajectoryTranscriptDisplayKind: Hashable {
    case plain
    case toolGroup
}

fileprivate struct CodexTrajectoryTranscriptDisplayEntry: Hashable {
    var id: String
    var kind: CodexTrajectoryTranscriptDisplayKind
    var title: String
    var subtitle: String
    var statusText: String?
    var block: CodexTrajectoryBlock

    var isAccordion: Bool {
        kind == .toolGroup
    }

    static func entries(from items: [CodexAppServerTranscriptItem]) -> [Self] {
        var entries: [Self] = []
        var toolItems: [CodexAppServerTranscriptItem] = []

        func flushToolItems() {
            guard !toolItems.isEmpty else { return }
            if let entry = toolGroup(from: toolItems) {
                entries.append(entry)
            }
            toolItems.removeAll(keepingCapacity: true)
        }

        for item in items {
            if item.isToolTranscriptItem {
                toolItems.append(item)
            } else {
                flushToolItems()
                entries.append(plain(from: item))
            }
        }
        flushToolItems()
        return entries
    }

    private static func plain(from item: CodexAppServerTranscriptItem) -> Self {
        Self(
            id: item.id.uuidString,
            kind: .plain,
            title: item.title,
            subtitle: "",
            statusText: nil,
            block: CodexTrajectoryBlock(
                id: item.id.uuidString,
                kind: item.trajectoryKind,
                title: item.title,
                text: item.body,
                isStreaming: item.isStreaming,
                createdAt: item.date
            )
        )
    }

    private static func toolGroup(from items: [CodexAppServerTranscriptItem]) -> Self? {
        guard let first = items.first else { return nil }
        let runs = CodexTrajectoryToolRun.runs(from: items)
        let detailText = runs.map(\.detailText).filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard !detailText.isEmpty else { return nil }

        let commandCount = runs.filter { !$0.command.isEmpty }.count
        let title: String
        if commandCount == 1 {
            title = String(localized: "codexAppServer.toolGroup.ranCommand.one", defaultValue: "Ran command")
        } else if commandCount > 1 {
            let format = String(
                localized: "codexAppServer.toolGroup.ranCommand.many",
                defaultValue: "Ran %1$ld commands"
            )
            title = String(format: format, locale: Locale.current, commandCount)
        } else if runs.count == 1 {
            title = String(localized: "codexAppServer.toolGroup.ranTool.one", defaultValue: "Ran tool")
        } else {
            let format = String(
                localized: "codexAppServer.toolGroup.ranTool.many",
                defaultValue: "Ran %1$ld tools"
            )
            title = String(format: format, locale: Locale.current, runs.count)
        }

        let subtitle = runs.compactMap(\.summary).first ?? first.title
        return Self(
            id: "toolgroup-\(first.id.uuidString)",
            kind: .toolGroup,
            title: title,
            subtitle: subtitle,
            statusText: statusText(for: runs),
            block: CodexTrajectoryBlock(
                id: "toolgroup-\(first.id.uuidString)-content",
                kind: .commandOutput,
                title: "",
                text: detailText,
                isStreaming: items.contains(where: \.isStreaming),
                createdAt: first.date
            )
        )
    }

    private static func statusText(for runs: [CodexTrajectoryToolRun]) -> String? {
        let exitCodes = runs.compactMap(\.exitCode)
        guard !exitCodes.isEmpty else { return nil }
        if let failingCode = exitCodes.first(where: { $0 != 0 }) {
            let format = String(
                localized: "codexAppServer.toolGroup.exitCode",
                defaultValue: "Exit code %1$ld"
            )
            return String(format: format, locale: Locale.current, failingCode)
        }
        guard exitCodes.count == runs.count else { return nil }
        return String(localized: "codexAppServer.toolGroup.success", defaultValue: "Success")
    }
}

private struct CodexTrajectoryToolRun: Hashable {
    var label: String
    var command: String
    var output: String
    var exitCode: Int?

    var summary: String? {
        if !command.isEmpty {
            return command
        }
        return output.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    var detailText: String {
        var lines: [String] = [label]
        if !command.isEmpty {
            lines.append("")
            lines.append("$ \(command)")
        }
        if !output.isEmpty {
            lines.append("")
            lines.append(output)
        }
        if let exitCode {
            lines.append("")
            let format = String(
                localized: "codexAppServer.toolGroup.exitCode",
                defaultValue: "Exit code %1$ld"
            )
            lines.append(String(format: format, locale: Locale.current, exitCode))
        }
        return lines.joined(separator: "\n")
    }

    static func runs(from items: [CodexAppServerTranscriptItem]) -> [Self] {
        var runs: [Self] = []
        for item in items {
            switch item.presentation {
            case .toolCall(let name):
                if var run = runs.last, run.command.isEmpty, !run.output.isEmpty {
                    run.label = toolLabel(name: name, fallback: item.title)
                    run.command = item.body
                    runs[runs.count - 1] = run
                    continue
                }
                runs.append(
                    Self(
                        label: toolLabel(name: name, fallback: item.title),
                        command: item.body,
                        output: "",
                        exitCode: nil
                    )
                )
            case .toolOutput, .commandOutput:
                let normalized = CodexTrajectoryToolOutput.normalize(item.body)
                if runs.isEmpty {
                    runs.append(
                        Self(
                            label: item.title.isEmpty ? outputLabel : item.title,
                            command: "",
                            output: normalized.text,
                            exitCode: normalized.exitCode
                        )
                    )
                } else {
                    var run = runs.removeLast()
                    if !normalized.text.isEmpty {
                        if run.output.isEmpty {
                            run.output = normalized.text
                        } else {
                            run.output += "\n" + normalized.text
                        }
                    }
                    if let exitCode = normalized.exitCode {
                        run.exitCode = exitCode
                    }
                    runs.append(run)
                }
            case .plain:
                break
            }
        }
        return runs
    }

    private static var outputLabel: String {
        String(localized: "codexAppServer.toolGroup.output", defaultValue: "Output")
    }

    private static func toolLabel(name: String?, fallback: String) -> String {
        let rawCandidate: String
        if let name, !name.isEmpty {
            rawCandidate = name
        } else {
            rawCandidate = fallback
        }
        let candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate == "exec_command" || candidate == "shell" || candidate == "Command" {
            return String(localized: "codexAppServer.toolGroup.shell", defaultValue: "Shell")
        }
        return candidate.isEmpty ? outputLabel : candidate
    }
}

private struct CodexTrajectoryToolOutput {
    var text: String
    var exitCode: Int?

    static func normalize(_ body: String) -> Self {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Self(text: trimmed, exitCode: nil)
        }

        let stdout = stringValue(named: "stdout", in: object)
            ?? stringValue(named: "output", in: object)
            ?? stringValue(named: "text", in: object)
        let stderr = stringValue(named: "stderr", in: object)
        let parts = [stdout, stderr]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let displayText = parts.isEmpty ? prettyJSON(object) : parts.joined(separator: "\n")
        return Self(
            text: displayText,
            exitCode: intValue(named: "exit_code", in: object)
                ?? intValue(named: "exitCode", in: object)
                ?? intValue(named: "status", in: object)
        )
    }

    private static func stringValue(named key: String, in object: [String: Any]) -> String? {
        if let value = object[key] as? String {
            return value
        }
        if let value = object[key] as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func intValue(named key: String, in object: [String: Any]) -> Int? {
        if let value = object[key] as? Int {
            return value
        }
        if let value = object[key] as? NSNumber {
            return value.intValue
        }
        if let value = object[key] as? String {
            return Int(value)
        }
        return nil
    }

    private static func prettyJSON(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }
}

private extension CodexAppServerTranscriptItem {
    var isToolTranscriptItem: Bool {
        switch presentation {
        case .toolCall, .toolOutput, .commandOutput:
            return true
        case .plain:
            return false
        }
    }

    var trajectoryKind: CodexTrajectoryBlockKind {
        switch role {
        case .user:
            return .userText
        case .assistant:
            return .assistantText
        case .event:
            return .systemEvent
        case .stderr:
            return .stderr
        case .error:
            return .stderr
        }
    }
}

final class CodexTrajectoryTranscriptScrollView: NSScrollView {
    private let trajectoryView = CodexTrajectoryTranscriptDocumentView()
    private var entries: [CodexTrajectoryTranscriptDisplayEntry] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        borderType = .noBorder
        documentView = trajectoryView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        reloadPreservingScroll(stickToBottom: isScrolledNearBottom)
    }

    fileprivate func update(entries: [CodexTrajectoryTranscriptDisplayEntry]) {
        let shouldStickToBottom = isScrolledNearBottom || entries.count > self.entries.count
        self.entries = entries
        reloadPreservingScroll(stickToBottom: shouldStickToBottom)
    }

    private var documentWidth: CGFloat {
        max(1, contentView.bounds.width)
    }

    private var isScrolledNearBottom: Bool {
        let visibleMaxY = contentView.bounds.maxY
        let documentHeight = trajectoryView.frame.height
        return documentHeight - visibleMaxY < 48
    }

    private func reloadPreservingScroll(stickToBottom: Bool) {
        guard documentWidth > 1 else { return }
        trajectoryView.update(entries: entries, width: documentWidth)
        if stickToBottom {
            scrollToBottom()
        }
    }

    private func scrollToBottom() {
        let maxY = max(0, trajectoryView.frame.height - contentView.bounds.height)
        contentView.scroll(to: NSPoint(x: 0, y: maxY))
        reflectScrolledClipView(contentView)
    }
}

private final class CodexTrajectoryTranscriptDocumentView: NSView {
    private enum PageChrome {
        case plain
        case accordionHeader
        case accordionContent
    }

    private struct PageEntry {
        var entry: CodexTrajectoryTranscriptDisplayEntry
        var page: CodexTrajectoryLayoutPage?
        var chrome: PageChrome
        var topSpacing: CGFloat
        var bottomSpacing: CGFloat
        var fullContentHeight: CGFloat
    }

    private struct LayoutCacheKey: Hashable {
        var block: CodexTrajectoryBlock
        var width: Int
        var themeIdentifier: String
    }

    private struct CachedLayout {
        var block: CodexTrajectoryBlock
        var layout: CodexTrajectoryBlockLayout
    }

    private struct ExpansionAnimation {
        var from: CGFloat
        var to: CGFloat
        var startTime: TimeInterval
        var duration: TimeInterval
    }

    private let layoutEngine = CodexTrajectoryLayoutEngine()
    private let renderer = CodexTrajectoryRenderer()
    private var entries: [CodexTrajectoryTranscriptDisplayEntry] = []
    private var pageEntries: [PageEntry] = []
    private var heightIndex = CodexTrajectoryHeightIndex()
    private var cachedLayouts: [LayoutCacheKey: CachedLayout] = [:]
    private var expandedAccordionIDs: Set<String> = []
    private var expansionAnimations: [String: ExpansionAnimation] = [:]
    private var animationTimer: Timer?
    private var documentWidth: CGFloat = 1
    private let horizontalInset: CGFloat = 14
    private let rowSpacing: CGFloat = 10
    private let accordionHeaderHeight: CGFloat = 40
    private let accordionContentIndent: CGFloat = 24
    private let accordionContentTopSpacing: CGFloat = 8
    private let accordionAnimationDuration: TimeInterval = 0.18

    override var isFlipped: Bool {
        true
    }

    override var wantsUpdateLayer: Bool {
        false
    }

    deinit {
        animationTimer?.invalidate()
    }

    func update(entries: [CodexTrajectoryTranscriptDisplayEntry], width: CGFloat) {
        let normalizedWidth = max(1, width)
        let activeAccordionIDs = Set(entries.filter(\.isAccordion).map(\.id))
        expandedAccordionIDs.formIntersection(activeAccordionIDs)
        expansionAnimations = expansionAnimations.filter { activeAccordionIDs.contains($0.key) }

        guard entries != self.entries || abs(normalizedWidth - documentWidth) > 0.5 else { return }
        self.entries = entries
        documentWidth = normalizedWidth
        rebuildLayout()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        backgroundColor.setFill()
        NSBezierPath(rect: dirtyRect).fill()

        let range = heightIndex.indexRange(
            intersectingOffset: dirtyRect.minY,
            length: dirtyRect.height,
            overscan: 480
        )
        guard !range.isEmpty else { return }

        let theme = Self.theme(for: effectiveAppearance)
        for index in range {
            let y = heightIndex.prefixSum(upTo: index)
            let pageEntry = pageEntries[index]
            switch pageEntry.chrome {
            case .plain:
                guard let page = pageEntry.page else { continue }
                let pageRect = CGRect(
                    x: horizontalInset,
                    y: y + rowSpacing / 2,
                    width: max(1, documentWidth - horizontalInset * 2),
                    height: page.measuredSize.height
                )
                drawBackground(for: pageEntry.entry.block.kind, in: pageRect, context: context)
                renderer.draw(
                    block: pageEntry.entry.block,
                    page: page,
                    in: context,
                    rect: pageRect,
                    theme: theme,
                    coordinates: .yDown
                )
            case .accordionHeader:
                let rect = accordionHeaderRect(at: y)
                drawAccordionHeader(entry: pageEntry.entry, in: rect, context: context)
            case .accordionContent:
                guard let page = pageEntry.page else { continue }
                let allocatedHeight = heightIndex.height(at: index) ?? 0
                guard allocatedHeight > 0.5 else { continue }
                let progress = max(0.01, expansionProgress(for: pageEntry.entry.id))
                let contentX = horizontalInset + accordionContentIndent
                let contentWidth = max(1, documentWidth - horizontalInset * 2 - accordionContentIndent)
                let pageRect = CGRect(
                    x: contentX,
                    y: y + pageEntry.topSpacing * progress,
                    width: contentWidth,
                    height: page.measuredSize.height
                )
                let clipRect = CGRect(
                    x: contentX,
                    y: y,
                    width: contentWidth,
                    height: allocatedHeight
                )

                context.saveGState()
                context.clip(to: clipRect)
                context.setAlpha(min(1, progress * 1.35))
                drawAccordionContentBackground(in: pageRect, context: context)
                renderer.draw(
                    block: pageEntry.entry.block,
                    page: page,
                    in: context,
                    rect: pageRect,
                    theme: theme,
                    coordinates: .yDown
                )
                context.restoreGState()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = heightIndex.index(containingOffset: point.y),
              pageEntries.indices.contains(index) else {
            super.mouseDown(with: event)
            return
        }

        let pageEntry = pageEntries[index]
        guard case .accordionHeader = pageEntry.chrome else {
            super.mouseDown(with: event)
            return
        }

        let y = heightIndex.prefixSum(upTo: index)
        guard accordionHeaderRect(at: y).contains(point) else {
            super.mouseDown(with: event)
            return
        }

        toggleAccordion(id: pageEntry.entry.id)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let visibleRange = heightIndex.indexRange(
            intersectingOffset: visibleRect.minY,
            length: visibleRect.height,
            overscan: 80
        )
        for index in visibleRange {
            guard pageEntries.indices.contains(index),
                  case .accordionHeader = pageEntries[index].chrome else {
                continue
            }
            let y = heightIndex.prefixSum(upTo: index)
            addCursorRect(accordionHeaderRect(at: y), cursor: .pointingHand)
        }
    }

    private var backgroundColor: NSColor {
        .textBackgroundColor
    }

    private func rebuildLayout() {
        let theme = Self.theme(for: effectiveAppearance)
        let layoutWidth = max(1, documentWidth - horizontalInset * 2)
        pageEntries.removeAll(keepingCapacity: true)
        var heights: [CGFloat] = []

        for entry in entries {
            if entry.isAccordion {
                let progress = expansionProgress(for: entry.id)
                pageEntries.append(
                    PageEntry(
                        entry: entry,
                        page: nil,
                        chrome: .accordionHeader,
                        topSpacing: 0,
                        bottomSpacing: progress > 0 ? 0 : rowSpacing,
                        fullContentHeight: accordionHeaderHeight
                    )
                )
                heights.append(accordionHeaderHeight + (progress > 0 ? 0 : rowSpacing))

                if progress > 0 {
                    let contentWidth = max(1, layoutWidth - accordionContentIndent)
                    let layout = layout(for: entry.block, width: contentWidth, theme: theme)
                    for page in layout.pages {
                        let isFirstPage = page.pageIndex == 0
                        let isLastPage = page.pageIndex == layout.pages.count - 1
                        let topSpacing = isFirstPage ? accordionContentTopSpacing : 0
                        let bottomSpacing = isLastPage ? rowSpacing : 0
                        let fullHeight = topSpacing + page.measuredSize.height + bottomSpacing
                        pageEntries.append(
                            PageEntry(
                                entry: entry,
                                page: page,
                                chrome: .accordionContent,
                                topSpacing: topSpacing,
                                bottomSpacing: bottomSpacing,
                                fullContentHeight: fullHeight
                            )
                        )
                        heights.append(max(0, fullHeight * progress))
                    }
                }
            } else {
                let layout = layout(for: entry.block, width: layoutWidth, theme: theme)
                for page in layout.pages {
                    pageEntries.append(
                        PageEntry(
                            entry: entry,
                            page: page,
                            chrome: .plain,
                            topSpacing: 0,
                            bottomSpacing: rowSpacing,
                            fullContentHeight: page.measuredSize.height
                        )
                    )
                    heights.append(page.measuredSize.height + rowSpacing)
                }
            }
        }

        if cachedLayouts.count > max(256, entries.count * 3) {
            pruneLayoutCache()
        }

        heightIndex.replaceAll(with: heights)
        setFrameSize(NSSize(width: documentWidth, height: max(1, heightIndex.totalHeight)))
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func layout(
        for block: CodexTrajectoryBlock,
        width: CGFloat,
        theme: CodexTrajectoryTheme
    ) -> CodexTrajectoryBlockLayout {
        let cacheKey = LayoutCacheKey(
            block: block,
            width: Int(width.rounded()),
            themeIdentifier: theme.identifier
        )
        if let cached = cachedLayouts[cacheKey] {
            return cached.layout
        }

        let layout = layoutEngine.layout(
            block: block,
            configuration: CodexTrajectoryLayoutConfiguration(width: width),
            theme: theme
        )
        cachedLayouts[cacheKey] = CachedLayout(block: block, layout: layout)
        return layout
    }

    private func toggleAccordion(id: String) {
        let current = expansionProgress(for: id)
        let shouldExpand = !expandedAccordionIDs.contains(id)
        if shouldExpand {
            expandedAccordionIDs.insert(id)
        } else {
            expandedAccordionIDs.remove(id)
        }

        expansionAnimations[id] = ExpansionAnimation(
            from: current,
            to: shouldExpand ? 1 : 0,
            startTime: Self.animationTime,
            duration: accordionAnimationDuration
        )
        startAnimationTimer()
        rebuildLayout()
    }

    private func expansionProgress(for id: String) -> CGFloat {
        guard let animation = expansionAnimations[id] else {
            return expandedAccordionIDs.contains(id) ? 1 : 0
        }
        let elapsed = max(0, Self.animationTime - animation.startTime)
        let linear = min(1, elapsed / animation.duration)
        let eased = linear * linear * (3 - 2 * linear)
        return animation.from + (animation.to - animation.from) * eased
    }

    private func startAnimationTimer() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.animationTick()
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func animationTick() {
        let now = Self.animationTime
        let completedIDs = expansionAnimations.compactMap { id, animation -> String? in
            now - animation.startTime >= animation.duration ? id : nil
        }
        for id in completedIDs {
            expansionAnimations.removeValue(forKey: id)
        }
        rebuildLayout()

        if expansionAnimations.isEmpty {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private static var animationTime: TimeInterval {
        Date.timeIntervalSinceReferenceDate
    }

    private func accordionHeaderRect(at y: CGFloat) -> CGRect {
        CGRect(
            x: horizontalInset,
            y: y + rowSpacing / 2,
            width: max(1, documentWidth - horizontalInset * 2),
            height: accordionHeaderHeight
        )
    }

    private func drawAccordionHeader(
        entry: CodexTrajectoryTranscriptDisplayEntry,
        in rect: CGRect,
        context: CGContext
    ) {
        let fill = Self.color(.controlBackgroundColor, appearance: effectiveAppearance)
        let stroke = Self.color(.separatorColor, appearance: effectiveAppearance)
        let primary = Self.color(.labelColor, appearance: effectiveAppearance)
        let secondary = Self.color(.secondaryLabelColor, appearance: effectiveAppearance)
        let tertiary = Self.color(.tertiaryLabelColor, appearance: effectiveAppearance)

        context.saveGState()
        context.setFillColor(fill.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        context.setStrokeColor(stroke.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.strokePath()
        context.restoreGState()

        drawChevron(
            progress: expansionProgress(for: entry.id),
            center: CGPoint(x: rect.minX + 18, y: rect.midY),
            color: secondary.cgColor,
            context: context
        )

        let titleFont = CTFontCreateUIFontForLanguage(.system, 13, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let subtitleFont = CTFontCreateUIFontForLanguage(.system, 12, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let statusFont = CTFontCreateUIFontForLanguage(.system, 12, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 12, nil)

        let textX = rect.minX + 34
        let statusWidth: CGFloat = entry.statusText == nil ? 0 : 112
        let titleWidth = max(1, rect.maxX - textX - statusWidth - 12)
        drawTruncatedLine(
            entry.title,
            font: titleFont,
            color: primary.cgColor,
            rect: CGRect(x: textX, y: rect.minY + 6, width: titleWidth, height: 16),
            context: context
        )
        drawTruncatedLine(
            entry.subtitle,
            font: subtitleFont,
            color: tertiary.cgColor,
            rect: CGRect(x: textX, y: rect.minY + 22, width: titleWidth, height: 14),
            context: context
        )

        if let statusText = entry.statusText {
            drawTruncatedLine(
                statusText,
                font: statusFont,
                color: secondary.cgColor,
                rect: CGRect(x: rect.maxX - statusWidth - 12, y: rect.minY + 13, width: statusWidth, height: 15),
                context: context
            )
        }
    }

    private func drawChevron(
        progress: CGFloat,
        center: CGPoint,
        color: CGColor,
        context: CGContext
    ) {
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: CGFloat.pi / 2 * progress)
        context.setStrokeColor(color)
        context.setLineWidth(1.7)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.move(to: CGPoint(x: -3.5, y: -5))
        context.addLine(to: CGPoint(x: 3, y: 0))
        context.addLine(to: CGPoint(x: -3.5, y: 5))
        context.strokePath()
        context.restoreGState()
    }

    private func drawAccordionContentBackground(in rect: CGRect, context: CGContext) {
        let fill = Self.color(.windowBackgroundColor, appearance: effectiveAppearance)
        let stroke = Self.color(.separatorColor, appearance: effectiveAppearance)
        context.saveGState()
        context.setFillColor(fill.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        context.setStrokeColor(stroke.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.strokePath()
        context.restoreGState()
    }

    private func drawBackground(
        for kind: CodexTrajectoryBlockKind,
        in rect: CGRect,
        context: CGContext
    ) {
        let fill = Self.backgroundColor(for: kind, appearance: effectiveAppearance)
        context.saveGState()
        context.setFillColor(fill.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil))
        context.fillPath()
        context.restoreGState()
    }

    private func drawTruncatedLine(
        _ text: String,
        font: CTFont,
        color: CGColor,
        rect: CGRect,
        context: CGContext
    ) {
        guard rect.width > 1, rect.height > 1, !text.isEmpty else { return }
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        let attributed = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attributed)
        let tokenAttributed = CFAttributedStringCreate(kCFAllocatorDefault, "..." as CFString, attributes as CFDictionary)!
        let token = CTLineCreateWithAttributedString(tokenAttributed)
        let displayLine = CTLineCreateTruncatedLine(line, Double(rect.width), .end, token) ?? line
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let leading = CTFontGetLeading(font)
        let lineHeight = ascent + descent + leading
        let baseline = max(descent, (rect.height - lineHeight) / 2 + descent)

        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: 0, y: baseline)
        CTLineDraw(displayLine, context)
        context.restoreGState()
    }

    private func pruneLayoutCache() {
        let activeIDs = Set(entries.map(\.block.id))
        cachedLayouts = cachedLayouts.filter { _, value in
            activeIDs.contains(value.block.id)
        }
    }

    private static func theme(for appearance: NSAppearance) -> CodexTrajectoryTheme {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let textFont = CTFontCreateUIFontForLanguage(.system, 13, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let monoFont = CTFontCreateUIFontForLanguage(.userFixedPitch, 12, nil)
            ?? CTFontCreateWithName("Menlo" as CFString, 12, nil)
        let primary = color(.labelColor, appearance: appearance)
        let muted = color(.secondaryLabelColor, appearance: appearance)
        let error = color(isDark ? NSColor.systemRed : NSColor.systemRed, appearance: appearance)
        let fallback = CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary.cgColor)

        return CodexTrajectoryTheme(
            identifier: isDark ? "cmux-dark" : "cmux-light",
            contentInsets: CodexTrajectoryInsets(top: 9, left: 10, bottom: 9, right: 10),
            stylesByKind: [
                .userText: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary.cgColor),
                .assistantText: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary.cgColor),
                .commandOutput: CodexTrajectoryBlockStyle(font: monoFont, foregroundColor: primary.cgColor),
                .toolCall: CodexTrajectoryBlockStyle(font: monoFont, foregroundColor: muted.cgColor),
                .fileChange: CodexTrajectoryBlockStyle(font: monoFont, foregroundColor: primary.cgColor),
                .approvalRequest: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: primary.cgColor),
                .status: CodexTrajectoryBlockStyle(font: textFont, foregroundColor: muted.cgColor),
                .stderr: CodexTrajectoryBlockStyle(font: monoFont, foregroundColor: error.cgColor),
                .systemEvent: CodexTrajectoryBlockStyle(font: monoFont, foregroundColor: muted.cgColor),
            ],
            fallbackStyle: fallback
        )
    }

    private static func backgroundColor(
        for kind: CodexTrajectoryBlockKind,
        appearance: NSAppearance
    ) -> NSColor {
        switch kind {
        case .userText:
            return color(NSColor.controlAccentColor.withAlphaComponent(0.10), appearance: appearance)
        case .assistantText:
            return color(.controlBackgroundColor, appearance: appearance)
        case .stderr:
            return color(NSColor.systemRed.withAlphaComponent(0.10), appearance: appearance)
        case .commandOutput, .toolCall, .fileChange, .systemEvent, .status, .approvalRequest:
            return color(.windowBackgroundColor, appearance: appearance)
        }
    }

    private static func color(_ color: NSColor, appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved.usingColorSpace(.sRGB) ?? resolved
    }
}
