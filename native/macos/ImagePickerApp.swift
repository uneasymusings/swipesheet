import AppKit
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
    return try JSONDecoder().decode(ReviewSession.self, from: data)
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
        default:
            unreviewed += 1
        }
    }

    var lines: [String] = []
    lines.append("# Image review export: \(session.title)")
    lines.append("")
    lines.append("Session: \(session.id)")
    lines.append("Reviewed: \(use.count + maybe.count + reject.count)/\(session.items.count)")
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

final class ReviewViewController: NSViewController, NSTextViewDelegate {
    private var session: ReviewSession
    private let sessionPath: String

    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private let imageFrame = NSView()
    private let storyboardHeader = NSStackView()
    private let storyboardTitleLabel = NSTextField(labelWithString: "Storyboard sequence")
    private let storyboardStatusLabel = NSTextField(labelWithString: "")
    private let storyboardScroll = NSScrollView()
    private let storyboardStack = NSStackView()
    private let thumbnailStack = NSStackView()
    private let positionLabel = NSTextField(labelWithString: "")
    private let statusLabelView = NSTextField(labelWithString: "")
    private let filenameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let metadataScroll = NSScrollView()
    private let metadataTextView = NSTextView()
    private let groupActionStack = NSStackView()
    private let groupNoteScroll = NSScrollView()
    private let groupNoteTextView = NSTextView()
    private let extraItemActionStack = NSStackView()
    private let noteScroll = NSScrollView()
    private let noteTextView = NSTextView()
    private let useCountLabel = NSTextField(labelWithString: "0\nUse")
    private let maybeCountLabel = NSTextField(labelWithString: "0\nMaybe")
    private let rejectCountLabel = NSTextField(labelWithString: "0\nReject")
    private var decisionButtons: [String: NSButton] = [:]
    private var groupActionButtons: [String: NSButton] = [:]
    private var latestExportText = ""
    private var isRendering = false

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
        if key == "x" {
            setDecision("reject", advance: true)
            return true
        }
        if key == "y" || event.keyCode == 36 {
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
            persist()
            return
        }
        guard let item = currentItem() else { return }
        var decision = session.decisions[item.id] ?? Decision(status: "unreviewed", note: "", reviewedAt: nil)
        decision.note = noteTextView.string
        session.decisions[item.id] = decision
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
        reviewPane.spacing = 14
        reviewPane.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        reviewPane.translatesAutoresizingMaskIntoConstraints = false

        let sidePane = NSStackView()
        sidePane.orientation = .vertical
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
            sideScroll.widthAnchor.constraint(equalToConstant: 380),
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
        reviewPane.addArrangedSubview(imageFrame)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: imageFrame.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageFrame.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: imageFrame.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageFrame.bottomAnchor),
            imageFrame.heightAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])

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
        storyboardScroll.documentView = storyboardStack
        reviewPane.addArrangedSubview(storyboardScroll)
        storyboardScroll.heightAnchor.constraint(equalToConstant: 132).isActive = true

        let thumbScroll = NSScrollView()
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
        counterRow.addArrangedSubview(positionLabel)
        counterRow.addArrangedSubview(statusLabelView)
        sidePane.addArrangedSubview(counterRow)

        filenameLabel.font = NSFont.boldSystemFont(ofSize: 15)
        filenameLabel.maximumNumberOfLines = 3
        pathLabel.font = NSFont.systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.maximumNumberOfLines = 5
        let fileBlock = NSStackView()
        fileBlock.orientation = .vertical
        fileBlock.spacing = 5
        fileBlock.addArrangedSubview(filenameLabel)
        fileBlock.addArrangedSubview(pathLabel)
        sidePane.addArrangedSubview(fileBlock)

        let metadataLabel = NSTextField(labelWithString: "Review metadata")
        metadataLabel.font = NSFont.boldSystemFont(ofSize: 13)
        sidePane.addArrangedSubview(metadataLabel)

        metadataTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        metadataTextView.isEditable = false
        metadataTextView.isRichText = false
        metadataTextView.textColor = .secondaryLabelColor
        metadataScroll.documentView = metadataTextView
        metadataScroll.hasVerticalScroller = true
        metadataScroll.borderType = .bezelBorder
        sidePane.addArrangedSubview(metadataScroll)
        metadataScroll.heightAnchor.constraint(equalToConstant: 150).isActive = true

        let buttonGrid = NSGridView(views: [
            [makeDecisionButton(title: "X  Disregard", status: "reject"), makeDecisionButton(title: "Y  Use this", status: "use")],
            [makeDecisionButton(title: "M  Maybe", status: "maybe"), makeButton(title: "N  Notes", action: #selector(focusNotes))]
        ])
        buttonGrid.rowSpacing = 8
        buttonGrid.columnSpacing = 8
        sidePane.addArrangedSubview(buttonGrid)

        extraItemActionStack.orientation = .horizontal
        extraItemActionStack.spacing = 6
        extraItemActionStack.distribution = .fillEqually
        sidePane.addArrangedSubview(extraItemActionStack)

        let groupActionLabel = NSTextField(labelWithString: "Group review")
        groupActionLabel.font = NSFont.boldSystemFont(ofSize: 13)
        sidePane.addArrangedSubview(groupActionLabel)

        groupActionStack.orientation = .vertical
        groupActionStack.spacing = 6
        sidePane.addArrangedSubview(groupActionStack)

        groupNoteTextView.font = NSFont.systemFont(ofSize: 13)
        groupNoteTextView.isRichText = false
        groupNoteTextView.isAutomaticQuoteSubstitutionEnabled = false
        groupNoteTextView.isAutomaticDashSubstitutionEnabled = false
        groupNoteScroll.documentView = groupNoteTextView
        groupNoteScroll.hasVerticalScroller = true
        groupNoteScroll.borderType = .bezelBorder
        sidePane.addArrangedSubview(groupNoteScroll)
        groupNoteScroll.heightAnchor.constraint(equalToConstant: 80).isActive = true

        let noteLabel = NSTextField(labelWithString: "Feedback for this image")
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
        sidePane.addArrangedSubview(finishButton)
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
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

    @objc private func focusNotes() {
        noteTextView.window?.makeFirstResponder(noteTextView)
    }

    @objc private func thumbnailPressed(_ sender: NSButton) {
        session.currentIndex = sender.tag
        render()
        persist()
    }

    @objc private func finishAndExport() {
        saveCurrentNote()
        saveCurrentGroupNote()
        session.finishedAt = nowISO()
        persist()
        let export = buildExport(session: session)
        latestExportText = export
        print(export)
        showExportWindow(export)
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
        if let decision = session.groupDecisions?[group.id] {
            return decision
        }
        return GroupDecision(status: "unreviewed", note: "", reviewedAt: nil, itemOrder: group.itemIds)
    }

    private func sessionIndex(for itemId: String) -> Int? {
        session.items.firstIndex { $0.id == itemId }
    }

    private func item(for itemId: String) -> ImageItem? {
        guard let index = sessionIndex(for: itemId) else { return nil }
        return session.items[index]
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
    }

    func canMoveStoryboardItem(_ sourceId: String, relativeTo targetId: String?) -> Bool {
        guard let group = currentGroup(), group.itemIds.contains(sourceId) else { return false }
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
        render()
        persist()
    }

    private func setDecision(_ status: String, advance: Bool) {
        guard let item = currentItem() else { return }
        session.decisions[item.id] = Decision(status: status, note: noteTextView.string, reviewedAt: status == "unreviewed" ? nil : nowISO())
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

        let decision = currentDecision()
        let counts = progress(for: session)
        titleLabel.stringValue = session.title
        metaLabel.stringValue = "\(item.label) / \(item.filename)"
        progressLabel.stringValue = "\(counts.reviewed) / \(counts.total) reviewed"
        positionLabel.stringValue = "\(item.index) of \(session.items.count)"
        statusLabelView.stringValue = statusLabel(decision.status)
        filenameLabel.stringValue = item.filename
        pathLabel.stringValue = item.path
        noteTextView.string = decision.note
        metadataTextView.string = metadataSummary(item: item, group: currentGroup())
        groupNoteTextView.string = currentGroupDecision()?.note ?? ""
        useCountLabel.stringValue = "\(counts.use)\nUse"
        maybeCountLabel.stringValue = "\(counts.maybe)\nMaybe"
        rejectCountLabel.stringValue = "\(counts.reject)\nReject"

        imageView.image = NSImage(contentsOfFile: item.path)
        if imageView.image == nil {
            imageView.image = placeholderImage(text: "Preview unavailable\n\(item.filename)")
        }

        for (status, button) in decisionButtons {
            button.state = decision.status == status ? .on : .off
        }

        renderStoryboard()
        renderGroupActions()
        renderExtraItemActions()
        renderThumbnails()
    }

    private func titleForAction(_ action: String) -> String {
        statusLabel(action)
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
            if let maxValue = constraints["maxSelected"] ?? constraints["maxImages"] ?? constraints["accountMaxImages"] {
                let maxText = jsonDisplay(maxValue)
                if let maxCount = Int(maxText), group.itemIds.count > maxCount {
                    warnings.append("Slide count \(group.itemIds.count) exceeds max \(maxCount)")
                }
            }
            if let requiredValue = constraints["requiredAspect"] {
                let required = jsonDisplay(requiredValue)
                let actual = metadataString(item.metadata, keys: ["aspectRatio", "aspect", "requiredAspect"])
                if let actual = actual, !actual.isEmpty, actual != required {
                    warnings.append("Aspect \(actual) does not match \(required)")
                }
            }
        }

        if metadataString(item.metadata, keys: ["personaApproval", "personaApproved"]) == "false" {
            warnings.append("Persona reference is not approved")
        }

        return warnings
    }

    private func metadataSummary(item: ImageItem, group: ReviewGroup?) -> String {
        var lines: [String] = []
        if let group = group {
            let groupDecision = currentGroupDecision()
            lines.append("Group")
            lines.append("id: \(group.id)")
            lines.append("label: \(group.label)")
            lines.append("status: \(groupDecision?.status ?? "unreviewed")")
            if let reviewType = group.reviewType ?? session.reviewType {
                lines.append("reviewType: \(reviewType)")
            }
            if !group.itemIds.isEmpty {
                lines.append("slides/items: \(group.itemIds.count)")
            }
            if let constraints = group.constraints, !constraints.isEmpty {
                lines.append("")
                appendMetadata(&lines, title: "Constraints", metadata: constraints, preferredKeys: ["minSelected", "maxSelected", "requiresOrder", "requiredAspect"])
            }
            let warnings = reviewWarnings(item: item, group: group)
            if !warnings.isEmpty {
                lines.append("")
                lines.append("Warnings")
                for warning in warnings {
                    lines.append("- \(warning)")
                }
            }
            lines.append("")
            appendMetadata(
                &lines,
                title: "Group metadata",
                metadata: group.metadata,
                preferredKeys: [
                    "personaId",
                    "contentSetId",
                    "briefId",
                    "hook",
                    "caption",
                    "cta",
                    "platform",
                    "accountGroup",
                    "oneLink",
                    "externalId",
                    "checklist"
                ]
            )
        }

        if !lines.isEmpty {
            lines.append("")
        }
        appendMetadata(
            &lines,
            title: "Item metadata",
            metadata: item.metadata,
            preferredKeys: ["slideIndex", "role", "aspectRatio", "personaId", "externalId", "score", "checklist"]
        )
        return lines.joined(separator: "\n")
    }

    private func makeStoryboardDropSlot(targetItemId: String?, insertion: StoryboardInsertionPosition) -> StoryboardDropSlotView {
        let slot = StoryboardDropSlotView()
        slot.controller = self
        slot.targetItemId = targetItemId
        slot.insertion = insertion
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.widthAnchor.constraint(equalToConstant: 14).isActive = true
        slot.heightAnchor.constraint(equalToConstant: 112).isActive = true
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
        storyboardTitleLabel.stringValue = group.label
        storyboardStatusLabel.stringValue = "\(items.count) items"

        if let first = items.first {
            storyboardStack.addArrangedSubview(makeStoryboardDropSlot(targetItemId: first.id, insertion: .before))
        }

        for (sequenceIndex, item) in items.enumerated() {
            let button = StoryboardItemButton()
            button.itemId = item.id
            button.tag = sessionIndex(for: item.id) ?? item.index - 1
            button.target = self
            button.action = #selector(thumbnailPressed(_:))
            button.title = "\(sequenceIndex + 1). \(metadataString(item.metadata, keys: ["role"]) ?? item.label)"
            button.toolTip = "#\(item.index) \(item.filename) · \(statusLabel(session.decisions[item.id]?.status ?? "unreviewed"))"
            button.bezelStyle = item.id == currentItem()?.id ? .regularSquare : .shadowlessSquare
            button.imagePosition = .imageAbove
            button.imageScaling = .scaleProportionallyUpOrDown
            button.image = NSImage(contentsOfFile: item.path) ?? placeholderImage(text: "\(sequenceIndex + 1)")
            button.cell?.lineBreakMode = .byTruncatingTail
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 108).isActive = true
            button.heightAnchor.constraint(equalToConstant: 118).isActive = true
            storyboardStack.addArrangedSubview(button)
            storyboardStack.addArrangedSubview(makeStoryboardDropSlot(targetItemId: item.id, insertion: .after))
        }
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

        for action in actions {
            let button = NSButton(title: titleForAction(action), target: self, action: #selector(groupActionPressed(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(action)
            button.bezelStyle = action == currentStatus ? .regularSquare : .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            groupActionButtons[action] = button
            groupActionStack.addArrangedSubview(button)
        }
    }

    private func renderExtraItemActions() {
        for view in extraItemActionStack.arrangedSubviews {
            extraItemActionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
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
            let button = NSButton(title: titleForAction(action), target: self, action: #selector(extraItemActionPressed(_:)))
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
            button.toolTip = "#\(item.index) \(item.filename)"
            button.image = NSImage(contentsOfFile: item.path) ?? placeholderImage(text: "\(item.index)")
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

func reviewWindowContentRect() -> NSRect {
    let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let width = min(1080, max(720, visibleFrame.width * 0.86))
    let height = min(720, max(560, visibleFrame.height * 0.84))
    return NSRect(x: 0, y: 0, width: width, height: height)
}

func reviewWindowMinimumSize() -> NSSize {
    let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    return NSSize(
        width: min(900, max(680, visibleFrame.width * 0.72)),
        height: min(620, max(520, visibleFrame.height * 0.72))
    )
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
            window.center()
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
