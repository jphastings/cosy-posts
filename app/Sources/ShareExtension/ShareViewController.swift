import UIKit
import UniformTypeIdentifiers

/// Share extension view controller that receives media from other apps.
/// Saves shared items to the App Group container for the main app to pick up.
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

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        // Navigation-like header
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

        // Media count label
        countLabel = UILabel()
        countLabel.font = .preferredFont(forTextStyle: .subheadline)
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .center
        countLabel.text = "Loading items..."
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        // Text input
        textView = UITextView()
        textView.font = .preferredFont(forTextStyle: .body)
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.layer.borderWidth = 0.5
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.translatesAutoresizingMaskIntoConstraints = false

        // Activity indicator
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

    // MARK: - Load Shared Items

    private func loadSharedItems() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            countLabel.text = "No items to share"
            return
        }

        let group = DispatchGroup()
        var loadedItems: [(data: Data, filename: String)] = []

        for extensionItem in extensionItems {
            guard let attachments = extensionItem.attachments else { continue }

            for attachment in attachments {
                let types: [UTType] = [.image, .movie, .audio]
                for type in types {
                    if attachment.hasItemConformingToTypeIdentifier(type.identifier) {
                        group.enter()
                        attachment.loadItem(forTypeIdentifier: type.identifier) { item, error in
                            defer { group.leave() }
                            guard error == nil else { return }

                            var data: Data?
                            var ext = "bin"

                            if let url = item as? URL {
                                data = try? Data(contentsOf: url)
                                ext = url.pathExtension.isEmpty ? Self.defaultExtension(for: type) : url.pathExtension
                            } else if let imageData = item as? Data {
                                data = imageData
                                ext = Self.defaultExtension(for: type)
                            } else if let image = item as? UIImage {
                                data = image.jpegData(compressionQuality: 0.9)
                                ext = "jpg"
                            }

                            if let data {
                                let filename = "shared_\(loadedItems.count).\(ext)"
                                DispatchQueue.main.async {
                                    loadedItems.append((data: data, filename: filename))
                                }
                            }
                        }
                        break // Only load once per attachment
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.sharedItems = loadedItems
            let count = loadedItems.count
            self.countLabel.text = count == 1
                ? "1 item to share"
                : "\(count) items to share"
        }
    }

    private static func defaultExtension(for type: UTType) -> String {
        if type.conforms(to: .image) { return "jpg" }
        if type.conforms(to: .movie) { return "mov" }
        if type.conforms(to: .audio) { return "m4a" }
        return "bin"
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func postTapped() {
        postButton.isEnabled = false
        cancelButton.isEnabled = false
        textView.isEditable = false
        activityIndicator.startAnimating()

        Task {
            await saveToSharedContainer()
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func saveToSharedContainer() async {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.us.awaits.chaos"
        ) else { return }

        let postID = NanoidHelper.generate()
        let inboxURL = containerURL.appendingPathComponent("inbox")
        let postDir = inboxURL.appendingPathComponent(postID)

        do {
            try FileManager.default.createDirectory(at: postDir, withIntermediateDirectories: true)

            // Save media files
            var filenames: [String] = []
            for item in sharedItems {
                let fileURL = postDir.appendingPathComponent(item.filename)
                try item.data.write(to: fileURL)
                filenames.append(item.filename)
            }

            // Create and save the post manifest
            let post = SharedPostManifest(
                postID: postID,
                date: ISO8601DateFormatter().string(from: Date()),
                bodyText: textView.text ?? "",
                mediaFilenames: filenames,
                contentExt: "md"
            )

            let manifestData = try JSONEncoder().encode(post)
            let manifestURL = postDir.appendingPathComponent("post.json")
            try manifestData.write(to: manifestURL)
        } catch {
            // Silently fail -- the main app will not pick this up
        }
    }
}

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
