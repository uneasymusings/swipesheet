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
    var metadata: [String: JSONValue]?
}

struct Decision: Codable {
    var status: String
    var note: String
    var reviewedAt: String?
}

struct ReviewSession: Codable {
    var version: Int
    var id: String
    var title: String
    var prompt: String
    var rootDir: String
    var createdAt: String
    var updatedAt: String
    var finishedAt: String?
    var currentIndex: Int
    var batchSize: Int
    var items: [ImageItem]
    var decisions: [String: Decision]
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
        return "Unreviewed"
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
        default:
            counts.unreviewed += 1
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

final class ReviewViewController: NSViewController, NSTextViewDelegate {
    private var session: ReviewSession
    private let sessionPath: String

    private let titleLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let imageView = NSImageView()
    private let imageFrame = NSView()
    private let thumbnailStack = NSStackView()
    private let positionLabel = NSTextField(labelWithString: "")
    private let statusLabelView = NSTextField(labelWithString: "")
    private let filenameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let noteScroll = NSScrollView()
    private let noteTextView = NSTextView()
    private let useCountLabel = NSTextField(labelWithString: "0\nUse")
    private let maybeCountLabel = NSTextField(labelWithString: "0\nMaybe")
    private let rejectCountLabel = NSTextField(labelWithString: "0\nReject")
    private var decisionButtons: [String: NSButton] = [:]
    private var latestExportText = ""

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
        render()
    }

    func handleKey(_ event: NSEvent) -> Bool {
        if noteTextView.window?.firstResponder === noteTextView || noteTextView.window?.firstResponder === noteTextView.textStorage {
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

        root.addArrangedSubview(reviewPane)
        root.addArrangedSubview(sidePane)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            root.topAnchor.constraint(equalTo: view.topAnchor),
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidePane.widthAnchor.constraint(equalToConstant: 360)
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
        imageFrame.addSubview(imageView)
        reviewPane.addArrangedSubview(imageFrame)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: imageFrame.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageFrame.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: imageFrame.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageFrame.bottomAnchor),
            imageFrame.heightAnchor.constraint(greaterThanOrEqualToConstant: 420)
        ])

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
        thumbScroll.heightAnchor.constraint(equalToConstant: 92).isActive = true

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

        let buttonGrid = NSGridView(views: [
            [makeDecisionButton(title: "X  Disregard", status: "reject"), makeDecisionButton(title: "Y  Use this", status: "use")],
            [makeDecisionButton(title: "M  Maybe", status: "maybe"), makeButton(title: "N  Notes", action: #selector(focusNotes))]
        ])
        buttonGrid.rowSpacing = 8
        buttonGrid.columnSpacing = 8
        sidePane.addArrangedSubview(buttonGrid)

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

    private func currentDecision() -> Decision {
        guard let item = currentItem() else {
            return Decision(status: "unreviewed", note: "", reviewedAt: nil)
        }
        return session.decisions[item.id] ?? Decision(status: "unreviewed", note: item.note ?? "", reviewedAt: nil)
    }

    private func saveCurrentNote() {
        guard let item = currentItem() else { return }
        var decision = session.decisions[item.id] ?? Decision(status: "unreviewed", note: "", reviewedAt: nil)
        decision.note = noteTextView.string
        session.decisions[item.id] = decision
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
        session.currentIndex = max(0, min(session.currentIndex + delta, session.items.count - 1))
        render()
        persist()
    }

    private func render() {
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

        renderThumbnails()
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
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SwipeSheet"
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
