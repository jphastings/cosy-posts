#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import UniformTypeIdentifiers

// MARK: - Shared Models (duplicated to avoid cross-target dependencies)

/// Nanoid generator for the share extension (standalone, no cross-target dependency).
enum NanoidHelper {
    private static let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz")

    static func generate(length: Int = 21) -> String {
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            let index = Int.random(in: 0..<alphabet.count)
            result.append(alphabet[index])
        }
        return result
    }
}

/// Post manifest for the share extension (mirrors SharedPost in main app).
struct SharedPostManifest: Codable {
    let postID: String
    let date: String
    let bodyText: String
    let mediaFilenames: [String]
    let contentExt: String
}

// MARK: - Shared Logic

/// Loads media attachments from extension items and saves to the App Group container.
enum ShareHelper {
    static func loadAttachments(from extensionItems: [NSExtensionItem]) async -> [(data: Data, filename: String)] {
        var items: [(data: Data, filename: String)] = []
        var counter = 0

        for extensionItem in extensionItems {
            guard let attachments = extensionItem.attachments else { continue }

            for attachment in attachments {
                let types: [UTType] = [.image, .movie, .audio]
                for type in types {
                    if attachment.hasItemConformingToTypeIdentifier(type.identifier) {
                        if let (data, ext) = await loadItem(from: attachment, type: type) {
                            let filename = "shared_\(counter).\(ext)"
                            items.append((data: data, filename: filename))
                            counter += 1
                        }
                        break
                    }
                }
            }
        }

        return items
    }

    private static func loadItem(from attachment: NSItemProvider, type: UTType) async -> (Data, String)? {
        await withCheckedContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: type.identifier) { item, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                var data: Data?
                var ext = defaultExtension(for: type)

                if let url = item as? URL {
                    data = try? Data(contentsOf: url)
                    if !url.pathExtension.isEmpty { ext = url.pathExtension }
                } else if let itemData = item as? Data {
                    data = itemData
                }
                #if canImport(UIKit)
                if data == nil, let image = item as? UIImage {
                    data = image.jpegData(compressionQuality: 0.9)
                    ext = "jpg"
                }
                #endif

                if let data {
                    continuation.resume(returning: (data, ext))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func saveToContainer(bodyText: String, items: [(data: Data, filename: String)]) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.me.byjp.cosyposts"
        ) else { return }

        let postID = NanoidHelper.generate()
        let postDir = containerURL.appendingPathComponent("inbox").appendingPathComponent(postID)
        try FileManager.default.createDirectory(at: postDir, withIntermediateDirectories: true)

        var filenames: [String] = []
        for item in items {
            let fileURL = postDir.appendingPathComponent(item.filename)
            try item.data.write(to: fileURL)
            filenames.append(item.filename)
        }

        let post = SharedPostManifest(
            postID: postID,
            date: ISO8601DateFormatter().string(from: Date()),
            bodyText: bodyText,
            mediaFilenames: filenames,
            contentExt: "md"
        )

        let manifestData = try JSONEncoder().encode(post)
        try manifestData.write(to: postDir.appendingPathComponent("post.json"))
    }

    static func defaultExtension(for type: UTType) -> String {
        if type.conforms(to: .image) { return "jpg" }
        if type.conforms(to: .movie) { return "mov" }
        if type.conforms(to: .audio) { return "m4a" }
        return "bin"
    }
}

// MARK: - iOS Share View Controller

#if canImport(UIKit)
class ShareViewController: UIViewController {
    private var textView: UITextView!
    private var countLabel: UILabel!
    private var postButton: UIButton!
    private var cancelButton: UIButton!
    private var activityIndicator: UIActivityIndicatorView!
    private var sharedItems: [(data: Data, filename: String)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSharedItems()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        let headerStack = UIStackView()
        headerStack.axis = .horizontal
        headerStack.alignment = .center
        headerStack.distribution = .equalSpacing
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let titleLabel = UILabel()
        titleLabel.text = "Share to Chaos"
        titleLabel.font = .preferredFont(forTextStyle: .headline)

        postButton = UIButton(type: .system)
        postButton.setTitle("Post", for: .normal)
        postButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        postButton.addTarget(self, action: #selector(postTapped), for: .touchUpInside)

        headerStack.addArrangedSubview(cancelButton)
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(postButton)

        countLabel = UILabel()
        countLabel.font = .preferredFont(forTextStyle: .subheadline)
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .center
        countLabel.text = "Loading items..."
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.borderWidth = 0.5
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.translatesAutoresizingMaskIntoConstraints = false

        activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerStack)
        view.addSubview(countLabel)
        view.addSubview(textView)
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            countLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            countLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            countLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            textView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func loadSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            countLabel.text = "No items to share"
            return
        }

        Task {
            let items = await ShareHelper.loadAttachments(from: extensionItems)
            self.sharedItems = items
            let count = items.count
            self.countLabel.text = count == 1 ? "1 item to share" : "\(count) items to share"
        }
    }

    @objc private func cancelTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func postTapped() {
        postButton.isEnabled = false
        cancelButton.isEnabled = false
        textView.isEditable = false
        activityIndicator.startAnimating()

        Task {
            try? ShareHelper.saveToContainer(bodyText: textView.text ?? "", items: sharedItems)
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

// MARK: - macOS Share View Controller

#elseif canImport(AppKit)
class ShareViewController: NSViewController {
    private var textField: NSTextField!
    private var countLabel: NSTextField!
    private var sharedItems: [(data: Data, filename: String)] = []

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        let titleLabel = NSTextField(labelWithString: "Share to Chaos")
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel = NSTextField(labelWithString: "Loading items...")
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        textField = NSTextField()
        textField.placeholderString = "What's on your mind?"
        textField.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        let postButton = NSButton(title: "Post", target: self, action: #selector(postTapped))
        postButton.bezelStyle = .push
        postButton.keyEquivalent = "\r"
        postButton.translatesAutoresizingMaskIntoConstraints = false

        let buttonStack = NSStackView(views: [cancelButton, postButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(countLabel)
        container.addSubview(textField)
        container.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            countLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            countLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            textField.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 12),
            textField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            buttonStack.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadSharedItems()
    }

    private func loadSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            countLabel.stringValue = "No items to share"
            return
        }

        Task {
            let items = await ShareHelper.loadAttachments(from: extensionItems)
            self.sharedItems = items
            let count = items.count
            self.countLabel.stringValue = count == 1 ? "1 item to share" : "\(count) items to share"
        }
    }

    @objc private func cancelTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func postTapped() {
        Task {
            try? ShareHelper.saveToContainer(bodyText: textField.stringValue, items: sharedItems)
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
#endif
