import AppKit
import AVKit
import Foundation

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

func jsonDisplay(_ value: JSONValue) -> String {
    switch value {
    case .string(let string):
        return string
    case .number(let number):
        if number.rounded() == number {
            return String(Int(number))
        }
        return String(number)
    case .bool(let bool):
        return bool ? "true" : "false"
    case .object(let object):
        let parts = object.keys.sorted().prefix(6).map { key in "\(key): \(jsonDisplay(object[key]!))" }
        return "{\(parts.joined(separator: ", "))}"
    case .array(let array):
        return array.prefix(6).map(jsonDisplay).joined(separator: ", ")
    case .null:
        return ""
    }
}

struct SessionLoadError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

func jsonObject(_ value: JSONValue?) -> [String: JSONValue]? {
    guard let value = value else { return nil }
    if case .object(let object) = value {
        return object
    }
    return nil
}

struct ImageItem: Codable {
    var id: String
    var index: Int
    var path: String
    var realPath: String?
    var filename: String
    var `extension`: String
    var label: String
    var relativePath: String
    var note: String?
    var groupId: String?
    var groupLabel: String?
    var order: Int?
    var metadata: [String: JSONValue]?
}

struct Decision: Codable {
    var status: String
    var note: String
    var reviewedAt: String?
}

struct ReviewGroup: Codable {
    var id: String
    var index: Int
    var label: String
    var reviewType: String?
    var metadata: [String: JSONValue]?
    var constraints: [String: JSONValue]?
    var itemIds: [String]
}

struct GroupDecision: Codable {
    var status: String
    var note: String
    var reviewedAt: String?
    var itemOrder: [String]?
}

struct ReviewSession: Codable {
    var version: Int
    var id: String
    var kind: String?
    var reviewType: String?
    var actions: [String]?
    var itemActions: [String]?
    var groupActions: [String]?
    var metadata: [String: JSONValue]?
    var title: String
    var prompt: String
    var rootDir: String
    var createdAt: String
    var updatedAt: String
    var finishedAt: String?
    var currentIndex: Int
    var batchSize: Int
    var items: [ImageItem]
    var groups: [ReviewGroup]?
    var decisions: [String: Decision]
    var groupDecisions: [String: GroupDecision]?
}

struct ProgressCounts {
    var total = 0
    var reviewed = 0
    var unreviewed = 0
    var use = 0
    var reject = 0
    var maybe = 0
}

enum ReviewIssueFocus {
    case itemNote
    case groupNote
    case group
}

enum GroupActionKind {
    case approve
    case reject
    case changes
}

struct ReviewIssue {
    var groupId: String?
    var itemId: String?
    var message: String
    var blocking: Bool
    var skippable: Bool
    var focus: ReviewIssueFocus
}

let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

func nowISO() -> String {
    isoFormatter.string(from: Date())
}

func statusLabel(_ status: String) -> String {
    switch status {
    case "use":
        return "Use this"
    case "reject":
        return "Disregard"
    case "maybe":
        return "Maybe"
    case "skipped":
        return "Skipped"
    default:
        if status == "unreviewed" {
            return "Unreviewed"
        }
        return status
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

func loadSession(path: String) throws -> ReviewSession {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let session = try JSONDecoder().decode(ReviewSession.self, from: data)
    try validateSessionForOpen(session)
    return session
}

func validateSessionForOpen(_ session: ReviewSession) throws {
    if session.version > 1 {
        throw SessionLoadError(message: "Unsupported session version \(session.version). Update SwipeSheet before opening this session.")
    }

    var itemIds = Set<String>()
    for item in session.items {
        if itemIds.contains(item.id) {
            throw SessionLoadError(message: "Duplicate item id in session: \(item.id)")
        }
        itemIds.insert(item.id)
    }

    var groupIds = Set<String>()
    for group in session.groups ?? [] {
        if groupIds.contains(group.id) {
            throw SessionLoadError(message: "Duplicate group id in session: \(group.id)")
        }
        groupIds.insert(group.id)
    }
}

func saveSession(_ session: ReviewSession, path: String) throws {
    var copy = session
    copy.updatedAt = nowISO()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(copy)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

func progress(for session: ReviewSession) -> ProgressCounts {
    var counts = ProgressCounts()
    counts.total = session.items.count
    for item in session.items {
        let status = session.decisions[item.id]?.status ?? "unreviewed"
        switch status {
        case "use":
            counts.reviewed += 1
            counts.use += 1
        case "reject":
            counts.reviewed += 1
            counts.reject += 1
        case "maybe":
            counts.reviewed += 1
            counts.maybe += 1
        case "unreviewed":
            counts.unreviewed += 1
        default:
            counts.reviewed += 1
        }
    }
    return counts
}

func lineFor(item: ImageItem, decision: Decision) -> String {
    let number = String(format: "#%04d", item.index)
    var line = "- \(number) | \(item.label) | \(item.filename)\n   path: \(item.path)"
    let trimmed = decision.note.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
        line += "\n   note: \(trimmed)"
    }
    return line
}

func buildExport(session: ReviewSession) -> String {
    var use: [(ImageItem, Decision)] = []
    var maybe: [(ImageItem, Decision)] = []
    var reject: [(ImageItem, Decision)] = []
    var other: [(ImageItem, Decision)] = []
    var unreviewed = 0

    for item in session.items {
        let decision = session.decisions[item.id] ?? Decision(status: "unreviewed", note: "", reviewedAt: nil)
        switch decision.status {
        case "use":
            use.append((item, decision))
        case "maybe":
            maybe.append((item, decision))
        case "reject":
            reject.append((item, decision))
        case "unreviewed":
            unreviewed += 1
        default:
            other.append((item, decision))
        }
    }

    var lines: [String] = []
    lines.append("# Image review export: \(session.title)")
    lines.append("")
    lines.append("Session: \(session.id)")
    lines.append("Reviewed: \(use.count + maybe.count + reject.count + other.count)/\(session.items.count)")
    lines.append("Use: \(use.count)")
    lines.append("Maybe / needs notes: \(maybe.count)")
    lines.append("Reject: \(reject.count)")
    lines.append("Unreviewed: \(unreviewed)")

    let prompt = session.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    if !prompt.isEmpty {
        lines.append("")
        lines.append("Original review prompt:")
        lines.append(prompt)
    }

    lines.append("")
    lines.append("Instructions for the AI agent:")
    lines.append("- Use the images in the Selected section as approved source material.")
    lines.append("- Treat Maybe items as conditional: follow the note before using them.")
    lines.append("- Do not use rejected images unless I explicitly mention their number later.")
    lines.append("- Preserve the full original paths when copying or wiring assets into another project.")

    lines.append("")
    lines.append("Selected images:")
    if use.isEmpty {
        lines.append("- None")
    } else {
        for entry in use {
            lines.append(lineFor(item: entry.0, decision: entry.1))
        }
    }

    lines.append("")
    lines.append("Maybe / needs changes:")
    if maybe.isEmpty {
        lines.append("- None")
    } else {
        for entry in maybe {
            lines.append(lineFor(item: entry.0, decision: entry.1))
        }
    }

    if !other.isEmpty {
        lines.append("")
        lines.append("Other item decisions:")
        for entry in other {
            lines.append(lineFor(item: entry.0, decision: entry.1))
            lines.append("   status: \(entry.1.status)")
        }
    }

    let rejectedWithNotes = reject.filter { !$0.1.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if !rejectedWithNotes.isEmpty {
        lines.append("")
        lines.append("Rejected images with notes:")
        for entry in rejectedWithNotes {
            lines.append(lineFor(item: entry.0, decision: entry.1))
        }
    }

    lines.append("")
    lines.append("Rejected image numbers:")
    if reject.isEmpty {
        lines.append("- None")
    } else {
        lines.append(reject.map { String(format: "#%04d", $0.0.index) }.joined(separator: ", "))
    }

    if let reviewGroups = session.groups, !reviewGroups.isEmpty {
        let itemsById = Dictionary(uniqueKeysWithValues: session.items.map { ($0.id, $0) })
        lines.append("")
        lines.append("Groups:")
        for group in reviewGroups {
            let decision = session.groupDecisions?[group.id] ?? GroupDecision(status: "unreviewed", note: "", reviewedAt: nil, itemOrder: group.itemIds)
            let order = decision.itemOrder ?? group.itemIds
            let itemNumbers = order.compactMap { itemsById[$0] }.map { String(format: "#%04d", $0.index) }
            lines.append("- \(group.id) | \(group.label) | status: \(decision.status)")
            if let reviewType = group.reviewType ?? session.reviewType {
                lines.append("   reviewType: \(reviewType)")
            }
            let trimmedNote = decision.note.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedNote.isEmpty {
                lines.append("   note: \(trimmedNote)")
            }
            lines.append("   ordered items: \(itemNumbers.joined(separator: ", "))")
        }
    }

    return lines.joined(separator: "\n") + "\n"
}

final class ReviewWindow: NSWindow {
    weak var reviewController: ReviewViewController?

    override func keyDown(with event: NSEvent) {
        if reviewController?.handleKey(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

final class PaddedTextFieldCell: NSTextFieldCell {
    var contentInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let base = super.drawingRect(forBounds: rect)
        return NSRect(
            x: base.origin.x + contentInsets.left,
            y: base.origin.y + contentInsets.top,
            width: base.width - contentInsets.left - contentInsets.right,
            height: base.height - contentInsets.top - contentInsets.bottom
        )
    }
}

final class PaddedLabel: NSTextField {
    var contentInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10) {
        didSet {
            (cell as? PaddedTextFieldCell)?.contentInsets = contentInsets
            invalidateIntrinsicContentSize()
        }
    }

    convenience init(labelWithString stringValue: String) {
        self.init(frame: .zero)
        self.stringValue = stringValue
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        let paddedCell = PaddedTextFieldCell(textCell: stringValue)
        paddedCell.contentInsets = contentInsets
        cell = paddedCell
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + contentInsets.left + contentInsets.right, height: size.height + contentInsets.top + contentInsets.bottom)
    }
}

let storyboardPasteboardType = NSPasteboard.PasteboardType("com.swipesheet.storyboard-item-id")

enum StoryboardInsertionPosition {
    case before
    case after
}

final class StoryboardItemButton: NSButton, NSDraggingSource {
    var itemId = ""

    override func mouseDragged(with event: NSEvent) {
        guard !itemId.isEmpty else { return }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(itemId, forType: storyboardPasteboardType)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let dragImage = image ?? placeholderImage(text: title)
        draggingItem.setDraggingFrame(bounds, contents: dragImage)
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .move
    }
}

final class StoryboardDropSlotView: NSView {
    weak var controller: ReviewViewController?
    var targetItemId: String?
    var insertion: StoryboardInsertionPosition = .before

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor
        registerForDraggedTypes([storyboardPasteboardType])
    }

    private func sourceId(from sender: NSDraggingInfo) -> String? {
        sender.draggingPasteboard.string(forType: storyboardPasteboardType)
    }

    private func setActive(_ active: Bool) {
        layer?.backgroundColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
            : NSColor.separatorColor.withAlphaComponent(0.22).cgColor
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let sourceId = sourceId(from: sender), controller?.canMoveStoryboardItem(sourceId, relativeTo: targetItemId) == true else {
            return []
        }
        setActive(true)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setActive(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let sourceId = sourceId(from: sender) else { return false }
        return controller?.canMoveStoryboardItem(sourceId, relativeTo: targetItemId) == true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setActive(false)
        guard let sourceId = sourceId(from: sender) else { return false }
        controller?.moveStoryboardItem(sourceId, relativeTo: targetItemId, insertion: insertion)
        return true
    }
}

final class ReviewViewController: NSViewController, NSTextViewDelegate, NSWindowDelegate {
    private var session: ReviewSession
    private let sessionPath: String

    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let contentTypeStack = NSStackView()
    private let contentTypeLabel = PaddedLabel(labelWithString: "")
    private let contentTypeDetailLabel = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private let videoPlayerView = AVPlayerView()
    private let imageFrame = NSView()
    private let storyboardHeader = NSStackView()
    private let storyboardTitleLabel = NSTextField(labelWithString: "Storyboard sequence")
    private let storyboardStatusLabel = NSTextField(labelWithString: "")
    private let storyboardScroll = NSScrollView()
    private let storyboardStack: NSStackView = FlippedStackView()
    private let thumbScroll = NSScrollView()
    private let thumbnailStack = NSStackView()
    private let positionLabel = NSTextField(labelWithString: "")
    private let statusLabelView = PaddedLabel(labelWithString: "")
    private let groupRailScroll = NSScrollView()
    private let groupRailStack: NSStackView = FlippedStackView()
    private let consequenceBanner = PaddedLabel(labelWithString: "")
    private let groupActionLabel = NSTextField(labelWithString: "Group review")
    private let filenameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let fileBlock = NSStackView()
    private let metadataHeaderLabel = NSTextField(labelWithString: "What gets posted")
    private let detailsToggleButton = NSButton(title: "More details", target: nil, action: nil)
    private let metadataScroll = NSScrollView()
    private let metadataTextView = NSTextView()
    private let warningLabel = PaddedLabel(labelWithString: "")
    private let groupActionStack = NSStackView()
    private let groupNoteLabel = NSTextField(labelWithString: "Group note")
    private let groupNoteScroll = NSScrollView()
    private let groupNoteTextView = NSTextView()
    private let itemActionRows = NSStackView()
    private let extraItemActionStack = NSStackView()
    private let noteLabel = NSTextField(labelWithString: "Image note")
    private let noteScroll = NSScrollView()
    private let noteTextView = NSTextView()
    private let useCountLabel = NSTextField(labelWithString: "0\nUse")
    private let maybeCountLabel = NSTextField(labelWithString: "0\nMaybe")
    private let rejectCountLabel = NSTextField(labelWithString: "0\nReject")
    private let openMediaButton = NSButton(title: "Open media", target: nil, action: nil)
    private var finishButton: NSButton?
    private var decisionButtons: [String: NSButton] = [:]
    private var groupActionButtons: [String: NSButton] = [:]
    private var latestExportText = ""
    private var isRendering = false
    private var showMoreDetails = false
    private var videoQueuePlayer: AVQueuePlayer?
    private var videoLooper: AVPlayerLooper?
    private var currentVideoPath: String?
    private var videoVisible = false

    init(session: ReviewSession, sessionPath: String) {
        self.session = session
        self.sessionPath = sessionPath
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        noteTextView.delegate = self
        groupNoteTextView.delegate = self
        render()
    }

    func handleKey(_ event: NSEvent) -> Bool {
        if noteTextView.window?.firstResponder === noteTextView ||
            noteTextView.window?.firstResponder === noteTextView.textStorage ||
            groupNoteTextView.window?.firstResponder === groupNoteTextView ||
            groupNoteTextView.window?.firstResponder === groupNoteTextView.textStorage {
            if event.keyCode == 53 {
                view.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }

        switch event.keyCode {
        case 123:
            move(delta: -1)
            return true
        case 124:
            move(delta: 1)
            return true
        default:
            break
        }

        let key = event.charactersIgnoringModifiers?.lowercased()
        if key == " " {
            toggleVideoPlayback()
            return true
        }
        if key == "o" {
            openCurrentMedia()
            return true
        }
        if isPostReviewMode() {
            if key == "a" || key == "y" || event.keyCode == 36 {
                triggerGroupAction(kind: .approve)
                return true
            }
            if key == "r" || key == "x" {
                triggerGroupAction(kind: .reject)
                return true
            }
            if key == "c" || key == "m" {
                triggerGroupAction(kind: .changes)
                return true
            }
        }
        if key == "x" {
            setDecision("reject", advance: true)
            return true
        }
        if event.keyCode == 36 {
            if isCanonicalMode() {
                move(delta: 1)
            } else {
                setDecision("use", advance: true)
            }
            return true
        }
        if key == "y" {
            setDecision("use", advance: true)
            return true
        }
        if key == "m" {
            setDecision("maybe", advance: false)
            noteTextView.window?.makeFirstResponder(noteTextView)
            return true
        }
        if key == "n" {
            noteTextView.window?.makeFirstResponder(noteTextView)
            return true
        }
        return false
    }

    func textDidChange(_ notification: Notification) {
        if isRendering {
            return
        }
        if let textView = notification.object as? NSTextView, textView === groupNoteTextView {
            saveCurrentGroupNote()
            session.finishedAt = nil
            persist()
            return
        }
        guard let item = currentItem() else { return }
        var decision = session.decisions[item.id] ?? Decision(status: "unreviewed", note: "", reviewedAt: nil)
        decision.note = noteTextView.string
        session.decisions[item.id] = decision
        session.finishedAt = nil
        persist()
    }

    private func buildLayout() {
        let root = NSStackView()
        root.orientation = .horizontal
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        let reviewPane = NSStackView()
        reviewPane.orientation = .vertical
        reviewPane.alignment = .width
        reviewPane.spacing = 14
        reviewPane.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        reviewPane.translatesAutoresizingMaskIntoConstraints = false

        let sidePane: NSStackView = FlippedStackView()
        sidePane.orientation = .vertical
        sidePane.alignment = .width
        sidePane.spacing = 14
        sidePane.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        sidePane.translatesAutoresizingMaskIntoConstraints = false
        sidePane.wantsLayer = true
        sidePane.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let sideScroll = NSScrollView()
        sideScroll.hasVerticalScroller = true
        sideScroll.hasHorizontalScroller = false
        sideScroll.borderType = .noBorder
        sideScroll.drawsBackground = false
        sideScroll.translatesAutoresizingMaskIntoConstraints = false
        sideScroll.documentView = sidePane

        root.addArrangedSubview(reviewPane)
        root.addArrangedSubview(sideScroll)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sideScroll.widthAnchor.constraint(equalToConstant: 420),
            sidePane.widthAnchor.constraint(equalTo: sideScroll.contentView.widthAnchor)
        ])

        let top = NSStackView()
        top.orientation = .horizontal
        top.alignment = .bottom
        top.distribution = .fill
        top.spacing = 20

        let titleBlock = NSStackView()
        titleBlock.orientation = .vertical
        titleBlock.spacing = 4
        titleLabel.font = NSFont.boldSystemFont(ofSize: 20)
        metaLabel.font = NSFont.systemFont(ofSize: 13)
        metaLabel.textColor = .secondaryLabelColor
        metaLabel.lineBreakMode = .byTruncatingMiddle
        titleBlock.addArrangedSubview(titleLabel)
        titleBlock.addArrangedSubview(metaLabel)

        progressLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.alignment = .right

        contentTypeStack.orientation = .vertical
        contentTypeStack.alignment = .leading
        contentTypeStack.spacing = 4
        contentTypeLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        contentTypeLabel.textColor = .controlAccentColor
        contentTypeLabel.maximumNumberOfLines = 2
        contentTypeLabel.lineBreakMode = .byWordWrapping
        contentTypeLabel.wantsLayer = true
        contentTypeLabel.layer?.cornerRadius = 8
        contentTypeLabel.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        contentTypeStack.addArrangedSubview(contentTypeLabel)
        contentTypeDetailLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        contentTypeDetailLabel.textColor = .secondaryLabelColor
        contentTypeDetailLabel.maximumNumberOfLines = 2
        contentTypeDetailLabel.lineBreakMode = .byWordWrapping
        contentTypeStack.addArrangedSubview(contentTypeDetailLabel)
        reviewPane.addArrangedSubview(contentTypeStack)

        top.addArrangedSubview(titleBlock)
        top.addArrangedSubview(progressLabel)
        reviewPane.addArrangedSubview(top)

        imageFrame.wantsLayer = true
        imageFrame.layer?.backgroundColor = NSColor.black.cgColor
        imageFrame.layer?.cornerRadius = 8
        imageFrame.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageFrame.addSubview(imageView)
        videoPlayerView.controlsStyle = .minimal
        videoPlayerView.isHidden = true
        videoPlayerView.translatesAutoresizingMaskIntoConstraints = false
        imageFrame.addSubview(videoPlayerView)
        reviewPane.addArrangedSubview(imageFrame)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: imageFrame.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageFrame.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: imageFrame.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageFrame.bottomAnchor),
            videoPlayerView.leadingAnchor.constraint(equalTo: imageFrame.leadingAnchor),
            videoPlayerView.trailingAnchor.constraint(equalTo: imageFrame.trailingAnchor),
            videoPlayerView.topAnchor.constraint(equalTo: imageFrame.topAnchor),
            videoPlayerView.bottomAnchor.constraint(equalTo: imageFrame.bottomAnchor),
            imageFrame.heightAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])

        openMediaButton.target = self
        openMediaButton.action = #selector(primaryMediaButtonPressed)
        openMediaButton.bezelStyle = .rounded
        openMediaButton.controlSize = .large
        openMediaButton.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        openMediaButton.translatesAutoresizingMaskIntoConstraints = false
        openMediaButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        openMediaButton.isHidden = true
        reviewPane.addArrangedSubview(openMediaButton)

        storyboardHeader.orientation = .horizontal
        storyboardHeader.alignment = .centerY
        storyboardHeader.distribution = .fill
        storyboardHeader.spacing = 12
        storyboardTitleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        storyboardStatusLabel.font = NSFont.systemFont(ofSize: 12)
        storyboardStatusLabel.textColor = .secondaryLabelColor
        storyboardStatusLabel.alignment = .right
        storyboardHeader.addArrangedSubview(storyboardTitleLabel)
        storyboardHeader.addArrangedSubview(storyboardStatusLabel)
        reviewPane.addArrangedSubview(storyboardHeader)

        storyboardScroll.hasHorizontalScroller = true
        storyboardScroll.hasVerticalScroller = false
        storyboardScroll.borderType = .bezelBorder
        storyboardScroll.translatesAutoresizingMaskIntoConstraints = false
        storyboardStack.orientation = .horizontal
        storyboardStack.spacing = 8
        storyboardStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        storyboardStack.alignment = .centerY
        storyboardStack.translatesAutoresizingMaskIntoConstraints = true
        storyboardScroll.documentView = storyboardStack
        reviewPane.addArrangedSubview(storyboardScroll)
        storyboardScroll.heightAnchor.constraint(equalToConstant: 112).isActive = true

        thumbScroll.hasHorizontalScroller = true
        thumbScroll.hasVerticalScroller = false
        thumbScroll.borderType = .noBorder
        thumbScroll.translatesAutoresizingMaskIntoConstraints = false
        thumbnailStack.orientation = .horizontal
        thumbnailStack.spacing = 8
        thumbnailStack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        thumbScroll.documentView = thumbnailStack
        reviewPane.addArrangedSubview(thumbScroll)
        thumbScroll.heightAnchor.constraint(equalToConstant: 82).isActive = true

        let counterRow = NSStackView()
        counterRow.orientation = .horizontal
        counterRow.distribution = .equalSpacing
        positionLabel.textColor = .secondaryLabelColor
        statusLabelView.font = NSFont.boldSystemFont(ofSize: 12)
        statusLabelView.alignment = .center
        statusLabelView.wantsLayer = true
        statusLabelView.layer?.cornerRadius = 6
        statusLabelView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        counterRow.addArrangedSubview(positionLabel)
        counterRow.addArrangedSubview(statusLabelView)
        sidePane.addArrangedSubview(counterRow)

        groupRailStack.orientation = .vertical
        groupRailStack.alignment = .width
        groupRailStack.spacing = 6
        groupRailStack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        groupRailScroll.documentView = groupRailStack
        groupRailScroll.hasVerticalScroller = true
        groupRailScroll.hasHorizontalScroller = false
        groupRailScroll.borderType = .bezelBorder
        sidePane.addArrangedSubview(groupRailScroll)
        groupRailScroll.heightAnchor.constraint(equalToConstant: 118).isActive = true

        consequenceBanner.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        consequenceBanner.textColor = .labelColor
        consequenceBanner.maximumNumberOfLines = 4
        consequenceBanner.lineBreakMode = .byWordWrapping
        consequenceBanner.wantsLayer = true
        consequenceBanner.layer?.cornerRadius = 6
        consequenceBanner.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.18).cgColor
        consequenceBanner.isHidden = true
        sidePane.addArrangedSubview(consequenceBanner)

        groupActionLabel.font = NSFont.boldSystemFont(ofSize: 13)
        groupActionLabel.maximumNumberOfLines = 2
        sidePane.addArrangedSubview(groupActionLabel)

        groupActionStack.orientation = .vertical
        groupActionStack.alignment = .width
        groupActionStack.spacing = 6
        sidePane.addArrangedSubview(groupActionStack)

        filenameLabel.font = NSFont.boldSystemFont(ofSize: 15)
        filenameLabel.maximumNumberOfLines = 3
        pathLabel.font = NSFont.systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.maximumNumberOfLines = 5
        fileBlock.orientation = .vertical
        fileBlock.spacing = 5
        fileBlock.addArrangedSubview(filenameLabel)
        fileBlock.addArrangedSubview(pathLabel)
        fileBlock.isHidden = true
        sidePane.addArrangedSubview(fileBlock)

        let metadataHeaderRow = NSStackView()
        metadataHeaderRow.orientation = .horizontal
        metadataHeaderRow.alignment = .centerY
        metadataHeaderRow.distribution = .fill
        metadataHeaderRow.spacing = 10
        metadataHeaderLabel.font = NSFont.boldSystemFont(ofSize: 13)
        metadataHeaderRow.addArrangedSubview(metadataHeaderLabel)
        let headerSpacer = NSView()
        metadataHeaderRow.addArrangedSubview(headerSpacer)
        detailsToggleButton.target = self
        detailsToggleButton.action = #selector(toggleDetails)
        detailsToggleButton.bezelStyle = .inline
        detailsToggleButton.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        metadataHeaderRow.addArrangedSubview(detailsToggleButton)
        sidePane.addArrangedSubview(metadataHeaderRow)

        metadataTextView.font = NSFont.systemFont(ofSize: 12)
        metadataTextView.isEditable = false
        metadataTextView.isRichText = false
        metadataTextView.textColor = .labelColor
        metadataTextView.textContainerInset = NSSize(width: 8, height: 8)
        metadataTextView.isHorizontallyResizable = false
        metadataTextView.textContainer?.widthTracksTextView = true
        metadataScroll.documentView = metadataTextView
        metadataScroll.hasVerticalScroller = true
        metadataScroll.borderType = .bezelBorder
        sidePane.addArrangedSubview(metadataScroll)
        metadataScroll.heightAnchor.constraint(equalToConstant: 178).isActive = true

        warningLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        warningLabel.textColor = .labelColor
        warningLabel.maximumNumberOfLines = 4
        warningLabel.lineBreakMode = .byWordWrapping
        warningLabel.wantsLayer = true
        warningLabel.layer?.cornerRadius = 6
        warningLabel.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor
        warningLabel.isHidden = true
        sidePane.addArrangedSubview(warningLabel)

        itemActionRows.orientation = .vertical
        itemActionRows.alignment = .width
        itemActionRows.spacing = 8
        let primaryActionRow = NSStackView()
        primaryActionRow.orientation = .horizontal
        primaryActionRow.distribution = .fillEqually
        primaryActionRow.spacing = 8
        primaryActionRow.addArrangedSubview(makeDecisionButton(title: "X  Disregard", status: "reject"))
        primaryActionRow.addArrangedSubview(makeDecisionButton(title: "Y  Use this", status: "use"))
        let secondaryActionRow = NSStackView()
        secondaryActionRow.orientation = .horizontal
        secondaryActionRow.distribution = .fillEqually
        secondaryActionRow.spacing = 8
        secondaryActionRow.addArrangedSubview(makeDecisionButton(title: "M  Maybe", status: "maybe"))
        secondaryActionRow.addArrangedSubview(makeButton(title: "N  Notes", action: #selector(focusNotes)))
        itemActionRows.addArrangedSubview(primaryActionRow)
        itemActionRows.addArrangedSubview(secondaryActionRow)
        sidePane.addArrangedSubview(itemActionRows)

        extraItemActionStack.orientation = .horizontal
        extraItemActionStack.spacing = 6
        extraItemActionStack.distribution = .fillEqually
        sidePane.addArrangedSubview(extraItemActionStack)

        groupNoteTextView.font = NSFont.systemFont(ofSize: 13)
        groupNoteTextView.isRichText = false
        groupNoteTextView.isAutomaticQuoteSubstitutionEnabled = false
        groupNoteTextView.isAutomaticDashSubstitutionEnabled = false
        groupNoteScroll.documentView = groupNoteTextView
        groupNoteScroll.hasVerticalScroller = true
        groupNoteScroll.borderType = .bezelBorder
        groupNoteLabel.font = NSFont.boldSystemFont(ofSize: 13)
        sidePane.addArrangedSubview(groupNoteLabel)
        sidePane.addArrangedSubview(groupNoteScroll)
        groupNoteScroll.heightAnchor.constraint(equalToConstant: 80).isActive = true

        noteLabel.font = NSFont.boldSystemFont(ofSize: 13)
        sidePane.addArrangedSubview(noteLabel)

        noteTextView.font = NSFont.systemFont(ofSize: 13)
        noteTextView.isRichText = false
        noteTextView.isAutomaticQuoteSubstitutionEnabled = false
        noteTextView.isAutomaticDashSubstitutionEnabled = false
        noteScroll.documentView = noteTextView
        noteScroll.hasVerticalScroller = true
        noteScroll.borderType = .bezelBorder
        sidePane.addArrangedSubview(noteScroll)
        noteScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        let stats = NSStackView()
        stats.orientation = .horizontal
        stats.distribution = .fillEqually
        stats.spacing = 8
        for label in [useCountLabel, maybeCountLabel, rejectCountLabel] {
            label.alignment = .center
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            label.maximumNumberOfLines = 2
            label.wantsLayer = true
            label.layer?.cornerRadius = 6
            label.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            stats.addArrangedSubview(label)
        }
        sidePane.addArrangedSubview(stats)

        let spacer = NSView()
        sidePane.addArrangedSubview(spacer)
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)

        let finishButton = makeButton(title: "Finish and export", action: #selector(finishAndExport))
        finishButton.bezelStyle = .rounded
        finishButton.controlSize = .large
        self.finishButton = finishButton
        sidePane.addArrangedSubview(finishButton)
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    private func makeDecisionButton(title: String, status: String) -> NSButton {
        let button = makeButton(title: title, action: #selector(decisionButtonPressed(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(status)
        decisionButtons[status] = button
        return button
    }

    @objc private func decisionButtonPressed(_ sender: NSButton) {
        guard let status = sender.identifier?.rawValue else { return }
        setDecision(status, advance: status != "maybe")
        if status == "maybe" {
            noteTextView.window?.makeFirstResponder(noteTextView)
        }
    }

    @objc private func groupActionPressed(_ sender: NSButton) {
        guard let status = sender.identifier?.rawValue else { return }
        setGroupDecision(status)
    }

    @objc private func extraItemActionPressed(_ sender: NSButton) {
        guard let status = sender.identifier?.rawValue else { return }
        setDecision(status, advance: false)
    }

    @objc private func openCurrentMedia() {
        guard let url = currentMediaURL() else {
            showError("No media URL found", detail: "This review group does not provide videoPath, publicMediaUrl, mediaUrl, url, oneLink, or onelink metadata.")
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func primaryMediaButtonPressed() {
        if videoVisible {
            toggleVideoPlayback()
            return
        }
        openCurrentMedia()
    }

    @objc private func toggleDetails() {
        showMoreDetails.toggle()
        render()
    }

    @objc private func focusNotes() {
        noteTextView.window?.makeFirstResponder(noteTextView)
    }

    @objc private func thumbnailPressed(_ sender: NSButton) {
        session.currentIndex = sender.tag
        render()
        persist()
    }

    @objc private func groupRailPressed(_ sender: NSButton) {
        guard let groupId = sender.identifier?.rawValue,
              let group = session.groups?.first(where: { $0.id == groupId }),
              let firstItem = orderedItemIds(for: group).first,
              let index = sessionIndex(for: firstItem) else { return }
        saveCurrentNote()
        saveCurrentGroupNote()
        session.currentIndex = index
        render()
        persist()
    }

    @objc private func finishAndExport() {
        saveCurrentNote()
        saveCurrentGroupNote()
        let issues = validationIssues()
        if !issues.isEmpty {
            showValidationSummary(issues)
            return
        }

        if !confirmReadyToFinish() {
            return
        }

        finishValidatedReview()
    }

    private func finishValidatedReview() {
        session.finishedAt = nowISO()
        persist()

        if isAutogenReview() {
            showCompletionAlert()
            return
        }

        let export = buildExport(session: session)
        latestExportText = export
        print(export)
        showExportWindow(export)
    }

    private func showCompletionAlert() {
        let alert = NSAlert()
        alert.messageText = "Review saved"
        alert.informativeText = "The session passed validation and was written to disk for aut0gen to import."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Done")
        alert.runModal()
    }

    private func showValidationSummary(_ issues: [ReviewIssue]) {
        let alert = NSAlert()
        alert.messageText = "Review is not ready to finish"
        alert.informativeText = issues.prefix(10).map { "• \($0.message)" }.joined(separator: "\n")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Fix issues")
        if issues.contains(where: { $0.skippable }) {
            alert.addButton(withTitle: "Skip unresolved groups")
        }

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            jumpToIssue(issues.first)
            return
        }

        if markIssueGroupsSkipped(issues) {
            persist()
        }

        let remainingIssues = validationIssues()
        if !remainingIssues.isEmpty {
            showValidationSummary(remainingIssues)
            return
        }

        finishValidatedReview()
    }

    private func confirmReadyToFinish() -> Bool {
        let groups = session.groups ?? []
        guard !groups.isEmpty else { return true }
        let rows = groups.map { group -> String in
            let decision = groupDecision(for: group)
            let selected = selectedUseCount(for: group)
            return "• \(group.label): \(actionLabel(decision.status, group: group)), \(selected) \(itemActionLabel("use", group: group))"
        }

        let alert = NSAlert()
        alert.messageText = "Confirm and finish review?"
        alert.informativeText = rows.joined(separator: "\n")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Confirm and finish")
        alert.addButton(withTitle: "Keep reviewing")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func markIssueGroupsSkipped(_ issues: [ReviewIssue]) -> Bool {
        if session.groupDecisions == nil {
            session.groupDecisions = [:]
        }
        var changed = false
        let issueGroupIds = Set(issues.filter { $0.skippable }.compactMap { $0.groupId })
        for group in session.groups ?? [] where issueGroupIds.contains(group.id) {
            var decision = session.groupDecisions?[group.id] ?? GroupDecision(status: "unreviewed", note: "", reviewedAt: nil, itemOrder: group.itemIds)
            guard decision.status == "unreviewed" else { continue }
            decision.status = "skipped"
            decision.reviewedAt = nowISO()
            if decision.itemOrder == nil {
                decision.itemOrder = group.itemIds
            }
            session.groupDecisions?[group.id] = decision
            session.finishedAt = nil
            changed = true
        }
        return changed
    }

    private func jumpToIssue(_ issue: ReviewIssue?) {
        guard let issue = issue else { return }
        if let itemId = issue.itemId, let index = sessionIndex(for: itemId) {
            session.currentIndex = index
        } else if let groupId = issue.groupId,
                  let group = session.groups?.first(where: { $0.id == groupId }),
                  let firstItem = orderedItemIds(for: group).first,
                  let index = sessionIndex(for: firstItem) {
            session.currentIndex = index
        }
        render()
        if issue.focus == .groupNote {
            groupNoteTextView.window?.makeFirstResponder(groupNoteTextView)
        } else if issue.focus == .itemNote {
            noteTextView.window?.makeFirstResponder(noteTextView)
        }
        persist()
    }

    private func currentItem() -> ImageItem? {
        guard !session.items.isEmpty else { return nil }
        session.currentIndex = max(0, min(session.currentIndex, session.items.count - 1))
        return session.items[session.currentIndex]
    }

    private func currentGroup() -> ReviewGroup? {
        guard let item = currentItem(), let groupId = item.groupId, let groups = session.groups else { return nil }
        return groups.first { $0.id == groupId }
    }

    private func currentDecision() -> Decision {
        guard let item = currentItem() else {
            return Decision(status: "unreviewed", note: "", reviewedAt: nil)
        }
        return session.decisions[item.id] ?? Decision(status: "unreviewed", note: item.note ?? "", reviewedAt: nil)
    }

    private func currentGroupDecision() -> GroupDecision? {
        guard let group = currentGroup() else { return nil }
        return groupDecision(for: group)
    }

    private func groupDecision(for group: ReviewGroup) -> GroupDecision {
        if let decision = session.groupDecisions?[group.id] { return decision }
        return GroupDecision(status: "unreviewed", note: "", reviewedAt: nil, itemOrder: group.itemIds)
    }

    private func reviewType(for group: ReviewGroup?) -> String {
        group?.reviewType ?? session.reviewType ?? "multi_select"
    }

    private func isCanonicalMode(group: ReviewGroup? = nil) -> Bool {
        reviewType(for: group ?? currentGroup()) == "single_select_per_group"
    }

    private func isPostReviewMode(group: ReviewGroup? = nil) -> Bool {
        let type = reviewType(for: group ?? currentGroup())
        return type == "post_review" || type == "content_set"
    }

    private func intValue(_ value: JSONValue?) -> Int? {
        guard let value = value else { return nil }
        switch value {
        case .number(let number):
            return Int(number)
        case .string(let string):
            return Int(string)
        default:
            return nil
        }
    }

    private func boolValue(_ value: JSONValue?) -> Bool? {
        guard let value = value else { return nil }
        switch value {
        case .bool(let bool):
            return bool
        case .string(let string):
            if ["true", "yes", "1"].contains(string.lowercased()) { return true }
            if ["false", "no", "0"].contains(string.lowercased()) { return false }
            return nil
        case .number(let number):
            return number != 0
        default:
            return nil
        }
    }

    private func selectedUseCount(for group: ReviewGroup) -> Int {
        group.itemIds.filter { (session.decisions[$0]?.status ?? "unreviewed") == "use" }.count
    }

    private func progressText(counts: ProgressCounts) -> String {
        guard let groups = session.groups, !groups.isEmpty else {
            return "\(counts.reviewed) / \(counts.total) reviewed"
        }

        let done = groups.filter { group in
            let status = groupDecision(for: group).status
            return status != "unreviewed"
        }.count
        let unit: String
        let resultWord: String
        if groups.contains(where: { isPostReviewMode(group: $0) }) {
            unit = "posts"
            resultWord = "decided"
        } else if groups.contains(where: { isCanonicalMode(group: $0) }) {
            unit = "personas"
            resultWord = "done"
        } else {
            unit = "groups"
            resultWord = "decided"
        }
        return "\(done) of \(groups.count) \(unit) \(resultWord)"
    }

    private func statusChipPayload(itemDecision: Decision, group: ReviewGroup?) -> (status: String, label: String) {
        guard let group = group, isPostReviewMode(group: group) else {
            return (itemDecision.status, statusLabel(itemDecision.status))
        }

        let decision = groupDecision(for: group)
        if decision.status == "unreviewed" {
            return (decision.status, "Awaiting your decision")
        }
        return (decision.status, actionLabel(decision.status, group: group))
    }

    private func items(for group: ReviewGroup) -> [ImageItem] {
        group.itemIds.compactMap { item(for: $0) }
    }

    private func isGroupFullyReviewed(_ group: ReviewGroup) -> Bool {
        group.itemIds.allSatisfy { (session.decisions[$0]?.status ?? "unreviewed") != "unreviewed" }
    }

    private func metadataContains(_ metadata: [String: JSONValue]?, keys: [String]) -> Bool {
        guard let metadata = metadata else { return false }
        return keys.contains { metadata[$0] != nil }
    }

    private func noteRequiredStatuses(for group: ReviewGroup? = nil) -> Set<String> {
        let keys = ["noteRequiredStatuses", "requireNotesForStatuses"]
        if metadataContains(group?.metadata, keys: keys) {
            return Set(metadataList(group?.metadata, keys: keys))
        }
        if metadataContains(session.metadata, keys: keys) {
            return Set(metadataList(session.metadata, keys: keys))
        }
        return Set(["maybe", "replace", "request_changes", "needs_reorder"])
    }

    private func sessionIndex(for itemId: String) -> Int? {
        session.items.firstIndex { $0.id == itemId }
    }

    private func item(for itemId: String) -> ImageItem? {
        guard let index = sessionIndex(for: itemId) else { return nil }
        return session.items[index]
    }

    private func isAutogenReview() -> Bool {
        session.kind == "autogen_review"
    }

    private func currentMediaURL() -> URL? {
        guard let group = currentGroup() else { return nil }
        let value = metadataString(group.metadata, keys: ["videoPath", "publicMediaUrl", "mediaUrl", "mediaURL", "url", "oneLink", "onelink"])
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("http://") || raw.lowercased().hasPrefix("https://") {
            return URL(string: raw)
        }
        return URL(fileURLWithPath: NSString(string: raw).expandingTildeInPath)
    }

    private func expandedLocalPath(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return NSString(string: raw).expandingTildeInPath
    }

    private func localVideoPath(for group: ReviewGroup?) -> String? {
        guard let path = expandedLocalPath(metadataString(group?.metadata, keys: ["videoPath"])) else { return nil }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }

    private func metadataLooksVideo(_ metadata: [String: JSONValue]?) -> Bool {
        let values = [
            metadataString(metadata, keys: ["mediaType", "contentType", "assetType", "postType"]),
            metadataString(metadata, keys: ["contentTypeLabel"])
        ].compactMap { $0?.lowercased() }
        return values.contains { $0.contains("video") || $0.contains("tiktok") || $0.contains("reel") }
    }

    private func isVideoGroup(_ group: ReviewGroup?) -> Bool {
        guard let group = group else { return false }
        return localVideoPath(for: group) != nil || metadataLooksVideo(group.metadata)
    }

    private func pauseVideo() {
        videoQueuePlayer?.pause()
    }

    private func toggleVideoPlayback() {
        guard videoVisible, let player = videoQueuePlayer else {
            openCurrentMedia()
            return
        }

        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    private func updateMediaView(item: ImageItem, group: ReviewGroup?) {
        if let videoPath = localVideoPath(for: group) {
            showInlineVideo(path: videoPath)
            return
        }

        pauseVideo()
        videoVisible = false
        videoPlayerView.isHidden = true
        imageView.isHidden = false
        imageView.image = NSImage(contentsOfFile: item.path)
        if imageView.image == nil {
            imageView.image = placeholderImage(text: "Preview unavailable\n\(item.filename)")
        }
    }

    private func showInlineVideo(path: String) {
        let wasVisible = videoVisible
        imageView.isHidden = true
        videoPlayerView.isHidden = false
        videoVisible = true

        if currentVideoPath == path, videoPlayerView.player != nil {
            if !wasVisible {
                videoQueuePlayer?.play()
            }
            return
        }

        let item = AVPlayerItem(url: URL(fileURLWithPath: path))
        let player = AVQueuePlayer()
        player.isMuted = true
        videoLooper = AVPlayerLooper(player: player, templateItem: item)
        videoQueuePlayer = player
        videoPlayerView.player = player
        currentVideoPath = path
        player.play()
    }

    private func groupAction(for kind: GroupActionKind, group: ReviewGroup?) -> String? {
        let actions = session.groupActions ?? []
        guard !actions.isEmpty else { return nil }

        let preferred: [String]
        switch kind {
        case .approve:
            preferred = ["approve_sequence", "approve", "use"]
        case .reject:
            preferred = ["reject"]
        case .changes:
            preferred = ["request_changes", "needs_reorder", "replace", "maybe"]
        }

        for action in preferred where actions.contains(action) {
            return action
        }

        return nil
    }

    private func triggerGroupAction(kind: GroupActionKind) {
        guard let status = groupAction(for: kind, group: currentGroup()) else {
            NSSound.beep()
            return
        }
        setGroupDecision(status)
    }

    private func orderedItemIds(for group: ReviewGroup) -> [String] {
        let groupSet = Set(group.itemIds)
        let savedOrder = session.groupDecisions?[group.id]?.itemOrder ?? group.itemIds
        var ordered = savedOrder.filter { groupSet.contains($0) }
        for itemId in group.itemIds where !ordered.contains(itemId) {
            ordered.append(itemId)
        }
        return ordered
    }

    private func orderedItems(for group: ReviewGroup) -> [ImageItem] {
        orderedItemIds(for: group).compactMap { item(for: $0) }
    }

    private func setGroupItemOrder(_ order: [String], for group: ReviewGroup) {
        if session.groupDecisions == nil {
            session.groupDecisions = [:]
        }
        var decision = session.groupDecisions?[group.id] ?? GroupDecision(status: "unreviewed", note: groupNoteTextView.string, reviewedAt: nil, itemOrder: group.itemIds)
        decision.itemOrder = order
        decision.note = groupNoteTextView.string
        session.groupDecisions?[group.id] = decision
        session.finishedAt = nil
    }

    func canMoveStoryboardItem(_ sourceId: String, relativeTo targetId: String?) -> Bool {
        guard let group = currentGroup(), group.itemIds.contains(sourceId) else { return false }
        if group.itemIds.count < 2 { return false }
        if boolValue(group.constraints?["requiresOrder"]) == false { return false }
        if let targetId = targetId {
            return group.itemIds.contains(targetId) && sourceId != targetId
        }
        return true
    }

    func moveStoryboardItem(_ sourceId: String, relativeTo targetId: String?, insertion: StoryboardInsertionPosition) {
        guard let group = currentGroup(), canMoveStoryboardItem(sourceId, relativeTo: targetId) else { return }
        saveCurrentNote()
        saveCurrentGroupNote()

        var order = orderedItemIds(for: group).filter { $0 != sourceId }
        var insertionIndex = order.count
        if let targetId = targetId, let targetIndex = order.firstIndex(of: targetId) {
            insertionIndex = insertion == .before ? targetIndex : targetIndex + 1
        }
        insertionIndex = max(0, min(insertionIndex, order.count))
        order.insert(sourceId, at: insertionIndex)
        setGroupItemOrder(order, for: group)

        if let index = sessionIndex(for: sourceId) {
            session.currentIndex = index
        }
        render()
        persist()
    }

    private func saveCurrentNote() {
        guard let item = currentItem() else { return }
        var decision = session.decisions[item.id] ?? Decision(status: "unreviewed", note: "", reviewedAt: nil)
        decision.note = noteTextView.string
        session.decisions[item.id] = decision
    }

    private func saveCurrentGroupNote() {
        guard let group = currentGroup() else { return }
        if session.groupDecisions == nil {
            session.groupDecisions = [:]
        }
        var decision = session.groupDecisions?[group.id] ?? GroupDecision(status: "unreviewed", note: "", reviewedAt: nil, itemOrder: group.itemIds)
        decision.note = groupNoteTextView.string
        session.groupDecisions?[group.id] = decision
    }

    private func setGroupDecision(_ status: String) {
        guard let group = currentGroup() else { return }
        if session.groupDecisions == nil {
            session.groupDecisions = [:]
        }
        var decision = session.groupDecisions?[group.id] ?? GroupDecision(status: "unreviewed", note: groupNoteTextView.string, reviewedAt: nil, itemOrder: group.itemIds)
        decision.status = status
        decision.note = groupNoteTextView.string
        decision.reviewedAt = status == "unreviewed" ? nil : nowISO()
        if decision.itemOrder == nil {
            decision.itemOrder = group.itemIds
        }
        session.groupDecisions?[group.id] = decision
        session.finishedAt = nil
        render()
        persist()
    }

    private func setDecision(_ status: String, advance: Bool) {
        guard let item = currentItem() else { return }
        if status == "use", let group = currentGroup(), isCanonicalMode(group: group) {
            for itemId in group.itemIds where itemId != item.id {
                if session.decisions[itemId]?.status == "use" {
                    let previous = session.decisions[itemId] ?? Decision(status: "unreviewed", note: "", reviewedAt: nil)
                    session.decisions[itemId] = Decision(status: "maybe", note: previous.note, reviewedAt: nowISO())
                }
            }
        }
        session.decisions[item.id] = Decision(status: status, note: noteTextView.string, reviewedAt: status == "unreviewed" ? nil : nowISO())
        session.finishedAt = nil
        if advance {
            session.currentIndex = nextUnreviewedIndex(after: session.currentIndex)
        }
        render()
        persist()
    }

    private func nextUnreviewedIndex(after index: Int) -> Int {
        guard !session.items.isEmpty else { return 0 }
        if index < session.items.count - 1 {
            for candidate in (index + 1)..<session.items.count {
                let item = session.items[candidate]
                if (session.decisions[item.id]?.status ?? "unreviewed") == "unreviewed" {
                    return candidate
                }
            }
            return min(index + 1, session.items.count - 1)
        }
        return index
    }

    private func move(delta: Int) {
        saveCurrentNote()
        saveCurrentGroupNote()
        session.currentIndex = max(0, min(session.currentIndex + delta, session.items.count - 1))
        render()
        persist()
    }

    private func render() {
        isRendering = true
        defer { isRendering = false }

        guard let item = currentItem() else {
            titleLabel.stringValue = session.title
            metaLabel.stringValue = "No images"
            return
        }

        let group = currentGroup()
        let decision = currentDecision()
        let counts = progress(for: session)
        titleLabel.stringValue = session.title
        metaLabel.stringValue = "\(item.label) / \(item.filename)"
        progressLabel.stringValue = progressText(counts: counts)
        positionLabel.stringValue = "\(item.index) of \(session.items.count)"
        let statusPayload = statusChipPayload(itemDecision: decision, group: group)
        statusLabelView.stringValue = statusPayload.label
        updateStatusChip(status: statusPayload.status)
        filenameLabel.stringValue = item.filename
        pathLabel.stringValue = item.path
        metadataHeaderLabel.stringValue = "What gets posted"
        detailsToggleButton.title = showMoreDetails ? "Less details ▴" : "More details ▾"
        noteTextView.string = decision.note
        metadataTextView.string = metadataSummary(item: item, group: group)
        groupNoteTextView.string = currentGroupDecision()?.note ?? ""
        updateContentType(item: item, group: group)
        updateConsequenceBanner(group: group)
        updateModeControls(group: group)
        updateWarningLabel(item: item, group: group)
        updateStatsLabels(counts: counts, group: group)
        updateMediaView(item: item, group: group)

        for (status, button) in decisionButtons {
            button.state = decision.status == status ? .on : .off
        }

        updateActionButtonLabels()
        renderGroupRail()
        renderStoryboard()
        renderGroupActions()
        renderExtraItemActions()
        renderThumbnails()
    }

    private func updateContentType(item: ImageItem, group: ReviewGroup?) {
        let explicit = metadataString(group?.metadata, keys: ["contentTypeLabel"])
        let label = explicit ?? fallbackContentTypeLabel(item: item, group: group)
        contentTypeLabel.stringValue = label

        if isVideoGroup(group) {
            contentTypeDetailLabel.stringValue = "The strip below shows PREVIEW FRAMES of this one video — it is not a slideshow."
            contentTypeDetailLabel.isHidden = false
        } else {
            contentTypeDetailLabel.stringValue = ""
            contentTypeDetailLabel.isHidden = true
        }
    }

    private func fallbackContentTypeLabel(item: ImageItem, group: ReviewGroup?) -> String {
        if let mediaType = metadataString(group?.metadata, keys: ["mediaType", "contentType", "assetType", "postType"]) {
            return mediaType.uppercased()
        }

        let type = reviewType(for: group)
        if isVideoGroup(group) || ["mp4", "mov", "m4v"].contains(item.extension.lowercased()) {
            if isPostReviewMode(group: group) {
                return "ONE VIDEO POST"
            }
            return "VIDEO REVIEW"
        }

        if type == "single_select_per_group" {
            if metadataString(group?.metadata, keys: ["personaId"]) != nil || group?.metadata?["personaContext"] != nil {
                return "PERSONA PHOTO REVIEW"
            }
            return "PICK ONE IMAGE"
        }

        if type == "storyboard" || type == "slideshow_content_set" {
            return "ORDERED IMAGE SEQUENCE"
        }

        if isPostReviewMode(group: group) {
            return "POST REVIEW"
        }

        return "IMAGE REVIEW"
    }

    private func updateConsequenceBanner(group: ReviewGroup?) {
        guard let group = group else {
            consequenceBanner.isHidden = true
            consequenceBanner.stringValue = ""
            return
        }

        var parts: [String] = []
        if let consequence = metadataString(group.metadata, keys: ["consequence"]) {
            parts.append(consequence)
        }

        let facts = [
            metadataString(group.metadata, keys: ["accountHandles", "accountHandle"]).map { "Account: \($0)" },
            metadataString(group.metadata, keys: ["scheduledLocal", "scheduled_at_local", "scheduledAtLocal"]).map { "Slot: \($0)" },
            metadataString(group.metadata, keys: ["creditCostEstimate"]).map { "Cost: \($0)" },
            metadataString(group.metadata, keys: ["creditsRemaining"]).map { "Remaining: \($0)" },
        ].compactMap { $0 }

        if !facts.isEmpty {
            parts.append(facts.joined(separator: " · "))
        }

        consequenceBanner.stringValue = parts.isEmpty ? "" : "Publish impact\n" + parts.joined(separator: "\n")
        consequenceBanner.isHidden = parts.isEmpty
    }

    private func statusColor(_ status: String) -> NSColor {
        switch status {
        case "use", "approve", "approve_sequence":
            return .systemGreen
        case "maybe", "replace", "request_changes", "needs_reorder":
            return .systemYellow
        case "reject":
            return .systemRed
        case "skipped":
            return .systemGray
        default:
            return .separatorColor
        }
    }

    private func updateStatusChip(status: String) {
        let color = statusColor(status)
        statusLabelView.layer?.backgroundColor = color.withAlphaComponent(0.14).cgColor
        statusLabelView.textColor = status == "unreviewed" ? .secondaryLabelColor : .labelColor
    }

    private func updateModeControls(group: ReviewGroup?) {
        let postReview = isPostReviewMode(group: group)
        itemActionRows.isHidden = postReview
        extraItemActionStack.isHidden = postReview || extraItemActionStack.isHidden
        openMediaButton.isHidden = currentMediaURL() == nil
        openMediaButton.title = mediaButtonTitle(group: group)
        finishButton?.title = isAutogenReview() ? "Finish review" : "Finish and export"
        groupActionLabel.stringValue = postReview ? "Publish decision" : "Group review"
        groupNoteLabel.stringValue = postReview ? "Decision note" : "Group note"
        noteLabel.stringValue = postReview ? "Frame note" : "Image note"
    }

    private func mediaButtonTitle(group: ReviewGroup?) -> String {
        guard let group = group else { return "Open media" }
        if localVideoPath(for: group) != nil {
            return "▶ Watch the video (Space)"
        }
        if isVideoGroup(group) {
            return "Open video (O)"
        }
        if metadataString(group.metadata, keys: ["publicMediaUrl", "mediaUrl", "mediaURL", "url"]) != nil {
            return "Open media URL (O)"
        }
        if metadataString(group.metadata, keys: ["oneLink", "onelink"]) != nil {
            return "Open OneLink (O)"
        }
        return "Open media (O)"
    }

    private func updateStatsLabels(counts: ProgressCounts, group: ReviewGroup?) {
        useCountLabel.stringValue = "\(counts.use)\n\(compactActionLabel("use", group: group))"
        maybeCountLabel.stringValue = "\(counts.maybe)\n\(compactActionLabel("maybe", group: group))"
        rejectCountLabel.stringValue = "\(counts.reject)\n\(compactActionLabel("reject", group: group))"
        useCountLabel.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.10).cgColor
        maybeCountLabel.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.12).cgColor
        rejectCountLabel.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.10).cgColor
    }

    private func compactActionLabel(_ action: String, group: ReviewGroup?) -> String {
        let label = itemActionLabel(action, group: group)
        if label.count <= 12 { return label }
        return String(label.prefix(11)) + "."
    }

    private func actionLabel(_ action: String, group: ReviewGroup? = nil, scope: String? = "group") -> String {
        let labelKeys: [String]
        switch scope {
        case "item":
            labelKeys = ["itemActionLabels"]
        case "group":
            labelKeys = ["groupActionLabels", "actionLabels"]
        default:
            labelKeys = ["actionLabels"]
        }

        for key in labelKeys {
            if let labels = jsonObject(group?.metadata?[key]),
               let label = labels[action] {
                let display = jsonDisplay(label).trimmingCharacters(in: .whitespacesAndNewlines)
                if !display.isEmpty { return display }
            }
        }

        for key in labelKeys {
            if let labels = jsonObject(session.metadata?[key]),
               let label = labels[action] {
                let display = jsonDisplay(label).trimmingCharacters(in: .whitespacesAndNewlines)
                if !display.isEmpty { return display }
            }
        }

        return statusLabel(action)
    }

    private func itemActionLabel(_ action: String, group: ReviewGroup? = nil) -> String {
        actionLabel(action, group: group, scope: "item")
    }

    private func itemActionTitle(_ action: String, group: ReviewGroup? = nil) -> String {
        let label = itemActionLabel(action, group: group)
        switch action {
        case "reject":
            return "X  \(label)"
        case "use":
            return "Y  \(label)"
        case "maybe":
            return "M  \(label)"
        default:
            return label
        }
    }

    private func groupActionTitle(_ action: String, group: ReviewGroup? = nil) -> String {
        if action == "skipped", let group = group, isPostReviewMode(group: group) {
            return "Skip — do nothing with this post"
        }

        let label = actionLabel(action, group: group)
        if groupAction(for: .approve, group: group) == action {
            return "A  \(label)"
        }
        if groupAction(for: .reject, group: group) == action {
            return "R  \(label)"
        }
        if groupAction(for: .changes, group: group) == action {
            return "C  \(label)"
        }
        return label
    }

    private func updateActionButtonLabels() {
        let group = currentGroup()
        for (status, button) in decisionButtons {
            button.title = itemActionTitle(status, group: group)
        }
    }

    private func metadataString(_ metadata: [String: JSONValue]?, keys: [String]) -> String? {
        guard let metadata = metadata else { return nil }
        for key in keys {
            if let value = metadata[key] {
                let display = jsonDisplay(value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !display.isEmpty {
                    return display
                }
            }
        }
        return nil
    }

    private func metadataList(_ metadata: [String: JSONValue]?, keys: [String]) -> [String] {
        guard let metadata = metadata else { return [] }
        for key in keys {
            guard let value = metadata[key] else { continue }
            switch value {
            case .array(let array):
                let values = array.map(jsonDisplay).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !values.isEmpty { return values }
            case .object(let object):
                let values = object.keys.sorted().map { key in "\(key): \(jsonDisplay(object[key]!))" }
                if !values.isEmpty { return values }
            default:
                let display = jsonDisplay(value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !display.isEmpty {
                    return display
                        .split(whereSeparator: \.isNewline)
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
            }
        }
        return []
    }

    private func appendSection(_ lines: inout [String], _ title: String, _ body: String?) {
        guard let body = body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return }
        if !lines.isEmpty { lines.append("") }
        lines.append(title)
        lines.append(body)
    }

    private func appendBullets(_ lines: inout [String], _ title: String, _ values: [String]) {
        let clean = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !clean.isEmpty else { return }
        if !lines.isEmpty { lines.append("") }
        lines.append(title)
        for value in clean {
            lines.append("- \(value)")
        }
    }

    private func appendFacts(_ lines: inout [String], _ title: String, _ facts: [(String, String?)]) {
        let clean = facts.compactMap { label, value -> String? in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return "\(label): \(value)"
        }
        appendBullets(&lines, title, clean)
    }

    private func reviewModeGuidance(_ reviewType: String?, group: ReviewGroup?) -> String {
        let type = reviewType ?? "multi_select"
        switch type {
        case "single_select_per_group":
            return "Pick the single best asset for this group. Use item decisions for each candidate, then approve or request changes for the group."
        case "storyboard", "slideshow_content_set":
            return "Review the sequence as a set. Drag the storyboard strip to change order, mark weak slides for replacement, then approve or request changes for the group."
        case "post_review":
            return "Review the media and publishing payload together. Check the creative, caption, CTA, links, platform fit, and readiness before approving."
        case "negative_reference_review":
            return "Identify why rejected assets should not be used. Note prompt misses, identity drift, artifacts, bad hands, weak styling, or other failure reasons."
        default:
            if group != nil {
                return "Review the current group as a structured set. Use item decisions for individual assets and group actions for the final state."
            }
            return "Review each asset and mark it as use, maybe, or reject. Add notes when the decision needs context."
        }
    }

    private func constraintLines(for group: ReviewGroup) -> [String] {
        guard let constraints = group.constraints else { return [] }
        var lines: [String] = []
        if let minSelected = constraints["minSelected"] {
            lines.append("Minimum selected: \(jsonDisplay(minSelected))")
        }
        if let maxSelected = constraints["maxSelected"] ?? constraints["maxImages"] ?? constraints["accountMaxImages"] {
            lines.append("Maximum selected: \(jsonDisplay(maxSelected))")
        }
        if let requiresOrder = constraints["requiresOrder"] {
            lines.append("Requires order: \(jsonDisplay(requiresOrder))")
        }
        if let requiredAspect = constraints["requiredAspect"] {
            lines.append("Required aspect: \(jsonDisplay(requiredAspect))")
        }
        for key in constraints.keys.sorted() where !["minSelected", "maxSelected", "maxImages", "accountMaxImages", "requiresOrder", "requiredAspect"].contains(key) {
            lines.append("\(key): \(jsonDisplay(constraints[key]!))")
        }
        return lines
    }

    private func appendMetadata(_ lines: inout [String], title: String, metadata: [String: JSONValue]?, preferredKeys: [String]) {
        guard let metadata = metadata, !metadata.isEmpty else { return }
        lines.append(title)
        var used = Set<String>()
        for key in preferredKeys {
            if let value = metadata[key] {
                let display = jsonDisplay(value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !display.isEmpty {
                    lines.append("\(key): \(display)")
                    used.insert(key)
                }
            }
        }
        for key in metadata.keys.sorted() where !used.contains(key) {
            let display = jsonDisplay(metadata[key]!).trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                lines.append("\(key): \(display)")
            }
        }
    }

    private func reviewWarnings(item: ImageItem, group: ReviewGroup?) -> [String] {
        guard let group = group else { return [] }
        let metadata = group.metadata ?? [:]
        let reviewType = group.reviewType ?? session.reviewType ?? ""
        let contentLike = reviewType.contains("storyboard") || reviewType.contains("post") || metadata["platform"] != nil
        var warnings: [String] = []
        let selected = selectedUseCount(for: group)

        if contentLike {
            let mediaURL = metadataString(metadata, keys: ["publicMediaUrl", "mediaUrl", "mediaURL", "url", "oneLink", "onelink"])
            if mediaURL == nil {
                warnings.append("Missing public media URL")
            } else if mediaURL?.lowercased().hasPrefix("https://") == false {
                warnings.append("Public media URL is not HTTPS")
            }
            if metadataString(metadata, keys: ["cta", "CTA", "callToAction"]) == nil {
                warnings.append("Missing CTA")
            }
        }

        if let constraints = group.constraints {
            if let minCount = intValue(constraints["minSelected"]), selected < minCount {
                warnings.append("\(itemActionLabel("use", group: group)) \(selected)/\(minCount)")
            }
            if let maxCount = intValue(constraints["maxSelected"] ?? constraints["maxImages"] ?? constraints["accountMaxImages"]), selected > maxCount {
                warnings.append("\(itemActionLabel("use", group: group)) \(selected)/\(maxCount)")
            }
            if groupDecision(for: group).status == "unreviewed", isGroupFullyReviewed(group) {
                warnings.append("Group reviewed but not confirmed")
            }

            if let requiredValue = constraints["requiredAspect"] {
                let required = jsonDisplay(requiredValue)
                let actual = metadataString(item.metadata, keys: ["aspectRatio", "aspect", "requiredAspect"])
                if let actual = actual, !actual.isEmpty, actual != required {
                    warnings.append("Aspect \(actual) does not match \(required)")
                }
            }
        }

        let requiredStatuses = noteRequiredStatuses(for: group)
        for item in items(for: group) {
            let decision = session.decisions[item.id] ?? Decision(status: "unreviewed", note: "", reviewedAt: nil)
            if requiredStatuses.contains(decision.status) && decision.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append("\(item.label): note required for \(itemActionLabel(decision.status, group: group))")
            }
        }

        let groupDecision = groupDecision(for: group)
        if requiredStatuses.contains(groupDecision.status) && groupDecision.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            warnings.append("Group note required for \(actionLabel(groupDecision.status, group: group))")
        }

        if metadataString(item.metadata, keys: ["personaApproval", "personaApproved"]) == "false" {
            warnings.append("Persona reference is not approved")
        }

        return warnings
    }

    private func validationIssues(includeSkipped: Bool = false) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        let groups = session.groups ?? []

        for group in groups {
            let groupDecision = groupDecision(for: group)
            if groupDecision.status == "skipped" && !includeSkipped {
                continue
            }

            let selected = selectedUseCount(for: group)
            if let constraints = group.constraints {
                if let minCount = intValue(constraints["minSelected"]), selected < minCount {
                    issues.append(ReviewIssue(groupId: group.id, itemId: nil, message: "\(group.label): \(itemActionLabel("use", group: group)) \(selected)/\(minCount)", blocking: true, skippable: groupDecision.status == "unreviewed", focus: .group))
                }
                if let maxCount = intValue(constraints["maxSelected"] ?? constraints["maxImages"] ?? constraints["accountMaxImages"]), selected > maxCount {
                    issues.append(ReviewIssue(groupId: group.id, itemId: nil, message: "\(group.label): \(itemActionLabel("use", group: group)) \(selected)/\(maxCount)", blocking: true, skippable: groupDecision.status == "unreviewed", focus: .group))
                }
            }

            if groupDecision.status == "unreviewed" {
                issues.append(ReviewIssue(groupId: group.id, itemId: nil, message: "\(group.label): group decision is still unreviewed", blocking: true, skippable: true, focus: .group))
            }

            let requiredStatuses = noteRequiredStatuses(for: group)
            for item in items(for: group) {
                let decision = session.decisions[item.id] ?? Decision(status: "unreviewed", note: "", reviewedAt: nil)
                if requiredStatuses.contains(decision.status) && decision.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(ReviewIssue(groupId: group.id, itemId: item.id, message: "\(group.label) / \(item.label): note required for \(itemActionLabel(decision.status, group: group))", blocking: true, skippable: false, focus: .itemNote))
                }
            }
            if requiredStatuses.contains(groupDecision.status) && groupDecision.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(ReviewIssue(groupId: group.id, itemId: nil, message: "\(group.label): group note required for \(actionLabel(groupDecision.status, group: group))", blocking: true, skippable: false, focus: .groupNote))
            }
        }

        return issues
    }

    private func updateWarningLabel(item: ImageItem, group: ReviewGroup?) {
        let warnings = reviewWarnings(item: item, group: group)
        if warnings.isEmpty {
            warningLabel.isHidden = true
            warningLabel.stringValue = ""
            return
        }
        warningLabel.isHidden = false
        warningLabel.stringValue = "Needs attention\n" + warnings.prefix(4).map { "- \($0)" }.joined(separator: "\n")
    }

    private func metadataSummary(item: ImageItem, group: ReviewGroup?) -> String {
        if showMoreDetails {
            return detailedMetadataSummary(item: item, group: group)
        }
        return compactMetadataSummary(item: item, group: group)
    }

    private func appendCompactLine(_ lines: inout [String], _ label: String, _ value: String?) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return }
        lines.append("\(label): \(value)")
    }

    private func compactMetadataSummary(item: ImageItem, group: ReviewGroup?) -> String {
        guard let group = group else {
            var lines: [String] = []
            appendCompactLine(&lines, "Review", item.label)
            appendCompactLine(&lines, "Instruction", session.prompt)
            appendCompactLine(&lines, "Decision", statusLabel(currentDecision().status))
            return lines.prefix(8).joined(separator: "\n")
        }

        var lines: [String] = []
        appendCompactLine(&lines, "Hook", metadataString(group.metadata, keys: ["hook"]))
        appendCompactLine(&lines, "Caption", metadataString(group.metadata, keys: ["caption"]))
        appendCompactLine(&lines, "CTA", metadataString(group.metadata, keys: ["cta", "CTA", "callToAction"]))

        let postsTo = [
            metadataString(group.metadata, keys: ["accountHandles", "accountHandle"]),
            metadataString(group.metadata, keys: ["platform"]),
            metadataString(group.metadata, keys: ["accountGroup", "account_group"])
        ].compactMap { $0 }.joined(separator: " · ")
        appendCompactLine(&lines, "Posts to", postsTo)
        appendCompactLine(&lines, "When", metadataString(group.metadata, keys: ["scheduledLocal", "scheduled_at_local", "scheduledAtLocal"]))

        let cost = metadataString(group.metadata, keys: ["creditCostEstimate"])
        let remaining = metadataString(group.metadata, keys: ["creditsRemaining"])
        let costLine: String?
        if let cost = cost, let remaining = remaining {
            costLine = "\(cost) credits, \(remaining) left"
        } else {
            costLine = cost ?? remaining
        }
        appendCompactLine(&lines, "Cost", costLine)

        if lines.isEmpty {
            appendCompactLine(&lines, "Review", group.label)
            appendCompactLine(&lines, "Instruction", reviewModeGuidance(group.reviewType ?? session.reviewType, group: group))
        }

        return lines.prefix(8).joined(separator: "\n")
    }

    private func detailedMetadataSummary(item: ImageItem, group: ReviewGroup?) -> String {
        var lines: [String] = []
        let groupMetadata = group?.metadata ?? [:]
        let itemMetadata = item.metadata ?? [:]
        let reviewType = group?.reviewType ?? session.reviewType

        appendSection(&lines, "What you are reviewing", group?.label ?? item.label)
        appendSection(&lines, "How to decide", reviewModeGuidance(reviewType, group: group))
        appendSection(&lines, "Session prompt", session.prompt)

        if let group = group {
            let groupDecision = currentGroupDecision()

            appendSection(
                &lines,
                "Agent description",
                metadataString(group.metadata, keys: ["description", "briefDescription", "summary", "context", "creativeBrief"])
            )
            appendSection(
                &lines,
                "Goal",
                metadataString(group.metadata, keys: ["objective", "goal", "reviewGoal", "desiredOutcome"])
            )
            appendBullets(
                &lines,
                "Selection criteria",
                metadataList(group.metadata, keys: ["selectionCriteria", "criteria", "qualityBar", "acceptanceCriteria"])
            )
            appendBullets(
                &lines,
                "Review instructions",
                metadataList(group.metadata, keys: ["reviewInstructions", "instructions", "directions", "notesForReviewer"])
            )
            appendBullets(
                &lines,
                "Checklist",
                metadataList(group.metadata, keys: ["checklist", "reviewChecklist", "briefChecklist"])
            )
            appendFacts(
                &lines,
                "Content context",
                [
                    ("Hook", metadataString(group.metadata, keys: ["hook"])),
                    ("Caption", metadataString(group.metadata, keys: ["caption"])),
                    ("CTA", metadataString(group.metadata, keys: ["cta", "CTA", "callToAction"])),
                    ("Platform", metadataString(group.metadata, keys: ["platform"])),
                    ("Account group", metadataString(group.metadata, keys: ["accountGroup", "account_group"])),
                    ("OneLink", metadataString(group.metadata, keys: ["oneLink", "onelink"])),
                ]
            )

            if let personaContext = jsonObject(group.metadata?["personaContext"]) {
                appendFacts(
                    &lines,
                    "Persona context",
                    [
                        ("Name", metadataString(personaContext, keys: ["name"])),
                        ("Status", metadataString(personaContext, keys: ["status"])),
                        ("Market", metadataString(personaContext, keys: ["market"])),
                        ("Current canonical", metadataString(personaContext, keys: ["currentCanonical"])),
                    ]
                )
                appendBullets(&lines, "Identity traits", metadataList(personaContext, keys: ["identityTraits"]))
                appendBullets(&lines, "Realism rules", metadataList(personaContext, keys: ["realismRules"]))
                appendBullets(&lines, "Approved references", metadataList(personaContext, keys: ["approvedReferences"]))
            }

            appendFacts(
                &lines,
                "Publish readiness",
                [
                    ("Account handles", metadataString(group.metadata, keys: ["accountHandles", "accountHandle"])),
                    ("Scheduled", metadataString(group.metadata, keys: ["scheduledLocal", "scheduled_at_local", "scheduledAtLocal"])),
                    ("Credit cost", metadataString(group.metadata, keys: ["creditCostEstimate"])),
                    ("Credits remaining", metadataString(group.metadata, keys: ["creditsRemaining"])),
                    ("Public media URL", metadataString(group.metadata, keys: ["publicMediaUrl", "mediaUrl", "mediaURL", "url"])),
                    ("Video", metadataString(group.metadata, keys: ["videoPath"])),
                    ("Duration", metadataString(group.metadata, keys: ["videoDurationSec"])),
                ]
            )
            appendFacts(
                &lines,
                "Group state",
                [
                    ("Status", groupDecision?.status ?? "unreviewed"),
                    ("Review type", reviewType),
                    ("Items", String(group.itemIds.count)),
                ]
            )
            appendBullets(&lines, "Requirements", constraintLines(for: group))

            let warnings = reviewWarnings(item: item, group: group)
            if !warnings.isEmpty {
                appendBullets(&lines, "Warnings", warnings)
            }

            appendFacts(
                &lines,
                "IDs",
                [
                    ("Group", group.id),
                    ("Persona", metadataString(group.metadata, keys: ["personaId"])),
                    ("Content set", metadataString(group.metadata, keys: ["contentSetId"])),
                    ("Brief", metadataString(group.metadata, keys: ["briefId"])),
                    ("External", metadataString(group.metadata, keys: ["externalId"])),
                ]
            )
        }

        appendFacts(
            &lines,
            "Current asset",
            [
                ("Label", item.label),
                ("Role", metadataString(item.metadata, keys: ["role", "slideRole"])),
                ("Slide", metadataString(item.metadata, keys: ["slideIndex", "index"])),
                ("Aspect", metadataString(item.metadata, keys: ["aspectRatio", "aspect"])),
                ("File", item.filename),
                ("Path", item.path),
            ]
        )
        appendSection(
            &lines,
            "Asset description",
            metadataString(item.metadata, keys: ["description", "summary", "rationale", "generationPrompt", "prompt"])
        )
        appendBullets(
            &lines,
            "Asset checklist",
            metadataList(item.metadata, keys: ["checklist", "reviewChecklist"])
        )
        appendFacts(
            &lines,
            "Asset IDs",
            [
                ("Item", item.id),
                ("Persona", metadataString(item.metadata, keys: ["personaId"])),
                ("External", metadataString(item.metadata, keys: ["externalId"])),
            ]
        )

        let knownGroupKeys = Set([
            "description", "briefDescription", "summary", "context", "creativeBrief", "objective", "goal", "reviewGoal", "desiredOutcome",
            "selectionCriteria", "criteria", "qualityBar", "acceptanceCriteria", "reviewInstructions", "instructions", "directions",
            "notesForReviewer", "checklist", "reviewChecklist", "briefChecklist", "hook", "caption", "cta", "CTA", "callToAction",
            "platform", "accountGroup", "account_group", "oneLink", "onelink", "personaId", "contentSetId", "briefId", "externalId",
            "personaContext", "consequence", "accountHandles", "accountHandle", "scheduledLocal", "scheduled_at_local", "scheduledAtLocal",
            "creditCostEstimate", "creditsRemaining", "publicMediaUrl", "mediaUrl", "mediaURL", "url", "videoPath", "videoDurationSec",
            "contentTypeLabel", "mediaType", "contentType", "assetType", "postType", "actionLabels", "itemActionLabels", "groupActionLabels",
            "noteRequiredStatuses", "requireNotesForStatuses"
        ])
        let additionalGroup = groupMetadata
            .filter { !knownGroupKeys.contains($0.key) }
            .map { "\($0.key): \(jsonDisplay($0.value))" }
            .sorted()
        appendBullets(&lines, "Additional group metadata", additionalGroup)

        let knownItemKeys = Set([
            "role", "slideRole", "slideIndex", "index", "aspectRatio", "aspect", "description", "summary", "rationale",
            "generationPrompt", "prompt", "checklist", "reviewChecklist", "personaId", "externalId"
        ])
        let additionalItem = itemMetadata
            .filter { !knownItemKeys.contains($0.key) }
            .map { "\($0.key): \(jsonDisplay($0.value))" }
            .sorted()
        appendBullets(&lines, "Additional asset metadata", additionalItem)

        return lines.joined(separator: "\n")
    }

    private func groupRailStatus(for group: ReviewGroup) -> (badge: String, detail: String) {
        let decision = groupDecision(for: group)
        let selected = selectedUseCount(for: group)
        let selectedText = "\(selected) \(itemActionLabel("use", group: group))"

        if decision.status == "skipped" {
            return ("Skip", "Skipped, \(selectedText)")
        }

        if decision.status != "unreviewed" {
            return ("Done", "\(actionLabel(decision.status, group: group)), \(selectedText)")
        }

        if selected > 0 || isGroupFullyReviewed(group) {
            return ("Picked", "Picked but unconfirmed, \(selectedText)")
        }

        return ("TO DO", "Undecided, \(selectedText)")
    }

    private func renderGroupRail() {
        for view in groupRailStack.arrangedSubviews {
            groupRailStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard let groups = session.groups, groups.count > 1 else {
            groupRailScroll.isHidden = true
            return
        }

        groupRailScroll.isHidden = false
        let activeGroupId = currentGroup()?.id
        for group in groups {
            let status = groupRailStatus(for: group)
            let button = NSButton(title: "\(status.badge) \(group.label)", target: self, action: #selector(groupRailPressed(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(group.id)
            button.toolTip = "\(group.label): \(status.detail)"
            button.alignment = .left
            button.lineBreakMode = .byTruncatingTail
            button.bezelStyle = group.id == activeGroupId ? .regularSquare : .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            groupRailStack.addArrangedSubview(button)
        }

        groupRailStack.layoutSubtreeIfNeeded()
        let fittingSize = groupRailStack.fittingSize
        let viewport = groupRailScroll.contentView.bounds
        groupRailStack.frame = NSRect(
            x: 0,
            y: 0,
            width: max(viewport.width, fittingSize.width),
            height: max(viewport.height, fittingSize.height)
        )
    }

    private func makeStoryboardDropSlot(targetItemId: String?, insertion: StoryboardInsertionPosition) -> StoryboardDropSlotView {
        let slot = StoryboardDropSlotView()
        slot.controller = self
        slot.targetItemId = targetItemId
        slot.insertion = insertion
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.widthAnchor.constraint(equalToConstant: 12).isActive = true
        slot.heightAnchor.constraint(equalToConstant: 88).isActive = true
        return slot
    }

    private func renderStoryboard() {
        for view in storyboardStack.arrangedSubviews {
            storyboardStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard let group = currentGroup() else {
            storyboardHeader.isHidden = true
            storyboardScroll.isHidden = true
            return
        }

        let items = orderedItems(for: group)
        storyboardHeader.isHidden = false
        storyboardScroll.isHidden = false
        if isVideoGroup(group) {
            storyboardTitleLabel.stringValue = "Preview frames (from the video above)"
            storyboardStatusLabel.stringValue = "\(items.count) frames · not separate posts"
        } else {
            storyboardTitleLabel.stringValue = group.label
            storyboardStatusLabel.stringValue = "\(items.count) items"
        }

        if let first = items.first {
            storyboardStack.addArrangedSubview(makeStoryboardDropSlot(targetItemId: first.id, insertion: .before))
        }

        for (sequenceIndex, item) in items.enumerated() {
            let button = StoryboardItemButton()
            button.itemId = item.id
            button.tag = sessionIndex(for: item.id) ?? item.index - 1
            button.target = self
            button.action = #selector(thumbnailPressed(_:))
            let role = metadataString(item.metadata, keys: ["role"]) ?? item.label
            button.title = ""
            let status = session.decisions[item.id]?.status ?? "unreviewed"
            button.toolTip = "\(sequenceIndex + 1). \(role) · #\(item.index) \(item.filename) · \(statusLabel(status))"
            button.bezelStyle = item.id == currentItem()?.id ? .regularSquare : .shadowlessSquare
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            button.image = storyboardThumbnailImage(path: item.path, number: sequenceIndex + 1, status: status)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 92).isActive = true
            button.heightAnchor.constraint(equalToConstant: 88).isActive = true
            storyboardStack.addArrangedSubview(button)
            storyboardStack.addArrangedSubview(makeStoryboardDropSlot(targetItemId: item.id, insertion: .after))
        }

        storyboardStack.layoutSubtreeIfNeeded()
        let fittingSize = storyboardStack.fittingSize
        let viewport = storyboardScroll.contentView.bounds
        storyboardStack.frame = NSRect(
            x: 0,
            y: 0,
            width: max(viewport.width, fittingSize.width),
            height: max(viewport.height, fittingSize.height)
        )
        storyboardScroll.contentView.scroll(to: NSPoint(x: 0, y: 0))
        storyboardScroll.reflectScrolledClipView(storyboardScroll.contentView)
    }

    private func renderGroupActions() {
        for view in groupActionStack.arrangedSubviews {
            groupActionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        groupActionButtons.removeAll()

        guard currentGroup() != nil else {
            let label = NSTextField(labelWithString: "No group for this image")
            label.textColor = .secondaryLabelColor
            groupActionStack.addArrangedSubview(label)
            return
        }

        let actions = session.groupActions ?? []
        let currentStatus = currentGroupDecision()?.status ?? "unreviewed"
        if actions.isEmpty {
            let label = NSTextField(labelWithString: "Status: \(statusLabel(currentStatus))")
            label.textColor = .secondaryLabelColor
            groupActionStack.addArrangedSubview(label)
            return
        }

        let group = currentGroup()
        let prominent = isPostReviewMode(group: group)
        for action in actions {
            let button = NSButton(title: groupActionTitle(action, group: group), target: self, action: #selector(groupActionPressed(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(action)
            button.bezelStyle = action == currentStatus ? .regularSquare : .rounded
            button.controlSize = prominent ? .large : .regular
            button.font = NSFont.systemFont(ofSize: prominent ? 13 : 12, weight: action == currentStatus ? .semibold : .regular)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: prominent ? 36 : 30).isActive = true
            groupActionButtons[action] = button
            groupActionStack.addArrangedSubview(button)
        }
    }

    private func renderExtraItemActions() {
        for view in extraItemActionStack.arrangedSubviews {
            extraItemActionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if isPostReviewMode() {
            extraItemActionStack.isHidden = true
            return
        }

        let defaultActions = Set(["use", "maybe", "reject"])
        let actions = (session.itemActions ?? []).filter { !defaultActions.contains($0) }
        if actions.isEmpty {
            extraItemActionStack.isHidden = true
            return
        }

        extraItemActionStack.isHidden = false
        let currentStatus = currentDecision().status
        for action in actions {
            let button = NSButton(title: itemActionTitle(action, group: currentGroup()), target: self, action: #selector(extraItemActionPressed(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(action)
            button.bezelStyle = action == currentStatus ? .regularSquare : .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            extraItemActionStack.addArrangedSubview(button)
        }
    }

    private func renderThumbnails() {
        for view in thumbnailStack.arrangedSubviews {
            thumbnailStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if let groups = session.groups, !groups.isEmpty {
            thumbScroll.isHidden = true
            return
        }

        thumbScroll.isHidden = false
        let batchSize = max(1, session.batchSize)
        let half = batchSize / 2
        var start = max(0, session.currentIndex - half)
        start = min(start, max(0, session.items.count - batchSize))
        let end = min(session.items.count, start + batchSize)
        guard start < end else { return }

        for index in start..<end {
            let item = session.items[index]
            let button = NSButton()
            button.tag = index
            button.target = self
            button.action = #selector(thumbnailPressed(_:))
            button.bezelStyle = index == session.currentIndex ? .regularSquare : .shadowlessSquare
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            let status = session.decisions[item.id]?.status ?? "unreviewed"
            button.toolTip = "#\(item.index) \(item.filename) · \(statusLabel(status))"
            button.image = storyboardThumbnailImage(path: item.path, number: item.index, status: status)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 88).isActive = true
            button.heightAnchor.constraint(equalToConstant: 72).isActive = true
            thumbnailStack.addArrangedSubview(button)
        }
    }

    private func persist() {
        do {
            try saveSession(session, path: sessionPath)
        } catch {
            showError("Could not save session", detail: error.localizedDescription)
        }
    }

    private func showExportWindow(_ export: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Copy export"

        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = 12
        container.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Paste this into your AI CLI or another project.")
        label.textColor = .secondaryLabelColor
        container.addArrangedSubview(label)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView()
        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = export
        scroll.documentView = textView
        container.addArrangedSubview(scroll)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.distribution = .fill
        let flexible = NSView()
        let copyButton = NSButton(title: "Copy text", target: self, action: #selector(copyExportText(_:)))
        let closeButton = NSButton(title: "Close", target: panel, action: #selector(NSWindow.close))
        buttons.addArrangedSubview(flexible)
        buttons.addArrangedSubview(copyButton)
        buttons.addArrangedSubview(closeButton)
        container.addArrangedSubview(buttons)

        panel.contentView = NSView()
        panel.contentView?.addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            container.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            container.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 420)
        ])

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func copyExportText(_ sender: NSButton) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(latestExportText, forType: .string)
        sender.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            sender.title = "Copy text"
        }
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        pauseVideo()
        guard isAutogenReview() else { return true }
        if session.finishedAt != nil { return true }

        saveCurrentNote()
        saveCurrentGroupNote()
        let issues = validationIssues()
        if !issues.isEmpty {
            showValidationSummary(issues)
            return false
        }

        guard confirmCloseAndCommit() else {
            return false
        }

        session.finishedAt = nowISO()
        persist()
        return true
    }

    private func confirmCloseAndCommit() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Close and finish aut0gen review?"
        alert.informativeText = closeSummaryText()
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Close and finish")
        alert.addButton(withTitle: "Keep reviewing")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func closeSummaryText() -> String {
        guard let groups = session.groups, !groups.isEmpty else {
            return "The session has no review groups."
        }

        let rows = groups.map { group -> String in
            let decision = groupDecision(for: group)
            let status = actionLabel(decision.status, group: group)
            let consequence = metadataString(group.metadata, keys: ["consequence"])
            if let consequence = consequence, !consequence.isEmpty {
                return "• \(group.label): \(status) — \(consequence)"
            }
            return "• \(group.label): \(status)"
        }

        return rows.joined(separator: "\n")
    }
}

func placeholderImage(text: String) -> NSImage {
    let size = NSSize(width: 800, height: 600)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.black.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.white,
        .font: NSFont.systemFont(ofSize: 28),
        .paragraphStyle: paragraph
    ]
    let rect = NSRect(x: 80, y: 250, width: 640, height: 120)
    text.draw(in: rect, withAttributes: attributes)
    image.unlockFocus()
    return image
}

func decisionBadgeText(_ status: String) -> String {
    switch status {
    case "use":
        return "Use"
    case "maybe":
        return "Keep"
    case "reject":
        return "Drop"
    case "replace":
        return "Swap"
    case "unreviewed":
        return "TO DO"
    default:
        return statusLabel(status)
    }
}

func storyboardThumbnailImage(path: String, number: Int, status: String) -> NSImage {
    let size = NSSize(width: 184, height: 176)
    let output = NSImage(size: size)
    output.lockFocus()

    NSColor.black.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

    if let source = NSImage(contentsOfFile: path), source.size.width > 0, source.size.height > 0 {
        let scale = min(size.width / source.size.width, size.height / source.size.height)
        let drawSize = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let drawRect = NSRect(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 28),
            .paragraphStyle: paragraph
        ]
        "\(number)".draw(in: NSRect(x: 0, y: 66, width: size.width, height: 42), withAttributes: attributes)
    }

    let badgeRect = NSRect(x: 10, y: size.height - 34, width: 30, height: 24)
    NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
    NSBezierPath(roundedRect: badgeRect, xRadius: 8, yRadius: 8).fill()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let badgeAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.labelColor,
        .font: NSFont.boldSystemFont(ofSize: 13),
        .paragraphStyle: paragraph
    ]
    "\(number)".draw(in: NSRect(x: badgeRect.minX, y: badgeRect.minY + 4, width: badgeRect.width, height: 16), withAttributes: badgeAttributes)

    let statusText = decisionBadgeText(status)
    let statusRect = NSRect(x: size.width - 72, y: size.height - 34, width: 62, height: 24)
    NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
    NSBezierPath(roundedRect: statusRect, xRadius: 8, yRadius: 8).fill()
    let statusAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: status == "unreviewed" ? NSColor.secondaryLabelColor : NSColor.controlAccentColor,
        .font: NSFont.boldSystemFont(ofSize: 11),
        .paragraphStyle: paragraph
    ]
    statusText.draw(in: NSRect(x: statusRect.minX + 2, y: statusRect.minY + 5, width: statusRect.width - 4, height: 14), withAttributes: statusAttributes)

    output.unlockFocus()
    return output
}

func reviewWindowContentRect() -> NSRect {
    let visibleFrame = screenUnderMouse().visibleFrame
    let width = min(1080, max(720, visibleFrame.width * 0.86))
    let height = min(720, max(560, visibleFrame.height * 0.84))
    return NSRect(x: 0, y: 0, width: width, height: height)
}

func reviewWindowMinimumSize() -> NSSize {
    let visibleFrame = screenUnderMouse().visibleFrame
    return NSSize(
        width: min(900, max(680, visibleFrame.width * 0.72)),
        height: min(620, max(520, visibleFrame.height * 0.72))
    )
}

func screenUnderMouse() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { screen in
        screen.frame.contains(mouse)
    } ?? NSScreen.main ?? NSScreen.screens.first!
}

func positionReviewWindow(_ window: NSWindow) {
    let visible = screenUnderMouse().visibleFrame
    var frame = window.frame
    frame.size.width = min(frame.width, visible.width)
    frame.size.height = min(frame.height, visible.height)
    frame.origin.x = visible.midX - frame.width / 2
    frame.origin.y = visible.midY - frame.height / 2
    frame.origin.x = min(max(frame.origin.x, visible.minX), max(visible.minX, visible.maxX - frame.width))
    frame.origin.y = min(max(frame.origin.y, visible.minY), max(visible.minY, visible.maxY - frame.height))
    window.setFrame(frame, display: true)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessionPath: String
    private var window: ReviewWindow?

    init(sessionPath: String) {
        self.sessionPath = sessionPath
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let session = try loadSession(path: sessionPath)
            let controller = ReviewViewController(session: session, sessionPath: sessionPath)
            let window = ReviewWindow(
                contentRect: reviewWindowContentRect(),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SwipeSheet"
            window.minSize = reviewWindowMinimumSize()
            window.contentViewController = controller
            window.reviewController = controller
            window.delegate = controller
            positionReviewWindow(window)
            window.makeKeyAndOrderFront(nil)
            self.window = window
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not open review session"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let args = CommandLine.arguments
guard args.count == 2 else {
    fputs("Usage: swipesheet-macos <session-json>\n", stderr)
    exit(2)
}

let app = NSApplication.shared
let delegate = AppDelegate(sessionPath: args[1])
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
