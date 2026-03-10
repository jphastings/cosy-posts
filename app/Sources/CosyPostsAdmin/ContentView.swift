import SwiftUI
import SwiftData
import PhotosUI
import os

private let infoLog = Logger(subsystem: "com.cosyposts", category: "SiteInfo")

struct ContentView: View {
    @State private var viewModel = ComposeViewModel()
    @State private var showingSiteSheet = false
    @State private var siteInfoLoader = SiteInfoLoader()
    @State private var accessRequestsLoader = AccessRequestsLoader()
    @Environment(AuthManager.self) private var authManager
    @Environment(UploadManager.self) private var uploadManager
    @Environment(NetworkMonitor.self) private var networkMonitor

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Offline banner
                if !networkMonitor.isConnected {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("Offline -- posts will upload when connected")
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.orange)
                }

                // Media area — takes up most of the space
                PhotosPicker(
                    selection: $viewModel.selectedPhotos,
                    maxSelectionCount: 20,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    Group {
                        if viewModel.mediaItems.isEmpty {
                            // Empty state — tap to add media
                            VStack(spacing: 12) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 40))
                                Text("Tap to select photos or videos")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.secondary.opacity(0.08))
                        } else {
                            // Media carousel
                            MediaCarouselView(
                                items: viewModel.mediaItems,
                                onRemove: { id in viewModel.removeMedia(id: id) }
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxHeight: .infinity)

                Divider()

                // Text input area — one per locale
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($viewModel.localeEntries) { $entry in
                            LocaleTextArea(
                                entry: $entry,
                                isPrimary: entry.id == viewModel.localeEntries.first?.id,
                                onRemove: { viewModel.removeLocale(id: entry.id) }
                            )
                            if entry.id != viewModel.localeEntries.last?.id {
                                Divider().padding(.horizontal)
                            }
                        }
                    }
                }
                .frame(minHeight: 60, maxHeight: viewModel.localeEntries.count > 1 ? 180 : 100)

                // Error message
                if let error = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                            .font(.caption)
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }

                Divider()

                // Bottom toolbar
                BottomToolbar(
                    viewModel: $viewModel,
                    showingSiteSheet: $showingSiteSheet,
                    siteName: siteInfoLoader.info?.name ?? authManager.serverURL?.host ?? "Not connected",
                    uploadManager: uploadManager,
                    accessRequestCount: accessRequestsLoader.emails.count
                )
            }
            .navigationTitle("New Post")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $showingSiteSheet) {
                SiteInfoSheet(authManager: authManager, loader: siteInfoLoader, accessRequestsLoader: accessRequestsLoader)
                    #if !os(macOS)
                    .presentationDetents([.medium])
                    #else
                    .frame(minWidth: 340, minHeight: 400)
                    #endif
            }
            .sheet(isPresented: $viewModel.showingLocalePicker) {
                LocalePickerSheet(
                    existingLocales: viewModel.localeEntries.compactMap { $0.locale.languageCode?.identifier },
                    siteLocales: siteInfoLoader.info?.locales ?? [],
                    onSelect: { language in
                        viewModel.addLocale(language)
                    }
                )
                #if !os(macOS)
                .presentationDetents([.medium])
                #else
                .frame(minWidth: 300, minHeight: 300)
                #endif
            }
            .task(id: authManager.serverURL) {
                guard let serverURL = authManager.serverURL else { return }
                async let siteInfo: () = siteInfoLoader.load(serverURL: serverURL, token: authManager.sessionToken)
                async let accessRequests: () = accessRequestsLoader.load(serverURL: serverURL, token: authManager.sessionToken)
                _ = await (siteInfo, accessRequests)
            }
        }
    }
}

// MARK: - Bottom Toolbar

/// Spacing unit for the bottom toolbar, equal to the vertical padding.
private let toolbarUnit: CGFloat = 10

private struct BottomToolbar: View {
    @Binding var viewModel: ComposeViewModel
    @Binding var showingSiteSheet: Bool
    let siteName: String
    let uploadManager: UploadManager
    var accessRequestCount: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            // Add Media — collapses to icon-only first
            PhotosPicker(
                selection: $viewModel.selectedPhotos,
                maxSelectionCount: 20,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            ) {
                ViewThatFits(in: .horizontal) {
                    Label("Add Media", systemImage: "photo.on.rectangle.angled")
                    Image(systemName: "photo.on.rectangle.angled")
                }
                .font(.body)
            }

            Spacer()
                .frame(width: toolbarUnit)

            // Locale picker
            Button {
                viewModel.showingLocalePicker = true
            } label: {
                Image(systemName: "globe")
                    .font(.body)
            }
            .fixedSize()

            Spacer(minLength: toolbarUnit * 2)

            // Site name — truncates last, falls back to icon-only
            Button {
                showingSiteSheet = true
            } label: {
                SiteNameLabel(name: siteName, badgeCount: accessRequestCount)
            }
            .buttonStyle(.plain)
            .layoutPriority(1)

            Spacer(minLength: toolbarUnit * 2)

            if uploadManager.isProcessing {
                Label("Uploading...", systemImage: "arrow.up.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()

                Spacer()
                    .frame(width: toolbarUnit)
            }

            // Post
            Button(action: { viewModel.upload(using: uploadManager) }) {
                if viewModel.isUploading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 12)
                } else {
                    Text("Post")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canUpload || viewModel.isUploading)
            .fixedSize()
        }
        .padding(.horizontal, toolbarUnit)
        .padding(.vertical, toolbarUnit)
    }
}

/// Shows house icon + site name in a capsule, truncating at the letter boundary.
/// Falls back to icon-only (in a circle) when fewer than 3 characters would be visible.
/// A hidden copy of the full-length label anchors the ideal width so the HStack
/// always proposes the same space regardless of which mode is active, preventing
/// layout oscillation.
private struct SiteNameLabel: View {
    let name: String
    var badgeCount: Int = 0
    @State private var availableWidth: CGFloat = 200
    @State private var minLabelWidth: CGFloat = 0

    private var showText: Bool { availableWidth >= minLabelWidth }

    var body: some View {
        ZStack {
            // Hidden label that anchors the ideal width to the full site name.
            // Without this, switching to icon-only would shrink the ideal size,
            // causing the HStack to reclaim space and never offer enough to switch back.
            Label(name, systemImage: "house")
                .font(.body)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .hidden()

            Group {
                if showText {
                    Label(name, systemImage: "house")
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.fill.tertiary, in: .capsule)
                } else {
                    Image(systemName: "house")
                        .padding(8)
                        .background(.fill.tertiary, in: .circle)
                }
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .overlay(alignment: .topTrailing) {
                if badgeCount > 0 {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                        .offset(x: 2, y: -2)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        .background {
            // Measure the minimum width needed to show at least 3 characters
            Label(minimumText, systemImage: "house")
                .font(.body)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { minLabelWidth = $0 }
        }
    }

    private var minimumText: String {
        if name.count <= 3 { return name }
        return String(name.prefix(3)) + "…"
    }
}

// MARK: - Models

struct SiteInfo: Decodable {
    let name: String
    let version: String
    let gitSHA: String
    let stats: SiteStats
    let locales: [String]

    enum CodingKeys: String, CodingKey {
        case name, version
        case gitSHA = "git_sha"
        case stats, locales
    }
}

struct SiteStats: Decodable {
    let posts: Int
    let photos: Int
    let videos: Int
    let audio: Int
    let members: Int
}

@Observable
@MainActor
final class SiteInfoLoader {
    var info: SiteInfo?
    var isLoading = false

    func load(serverURL: URL, token: String?) async {
        isLoading = true
        defer { isLoading = false }

        let url = serverURL.appendingPathComponent("api/info")
        infoLog.info("Loading site info from \(url)")
        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            guard http.statusCode == 200 else {
                infoLog.error("HTTP \(http.statusCode) from \(url)")
                if http.statusCode == 401 {
                    NotificationCenter.default.post(name: .authSessionExpired, object: nil)
                }
                return
            }
            info = try JSONDecoder().decode(SiteInfo.self, from: data)
            infoLog.info("Loaded: \(self.info?.name ?? "nil")")
        } catch {
            infoLog.error("Failed: \(error)")
        }
    }
}

struct SiteInfoSheet: View {
    let authManager: AuthManager
    var loader: SiteInfoLoader
    var accessRequestsLoader: AccessRequestsLoader
    @Environment(\.dismiss) private var dismiss

    private var repoURL: URL? {
        guard let sha = loader.info?.gitSHA, sha != "unknown" else { return nil }
        return URL(string: "https://github.com/jphastings/cosy-posts/commit/\(sha)")
    }

    var body: some View {
        NavigationStack {
            List {
                if let info = loader.info {
                    // Stats
                    Section {
                        Label {
                            Text("\(info.stats.posts) posts")
                        } icon: {
                            Image(systemName: "doc.richtext")
                        }
                        .foregroundStyle(.primary)

                        if info.stats.photos > 0 {
                            Label {
                                Text("\(info.stats.photos) photos")
                            } icon: {
                                Image(systemName: "photo")
                            }
                            .foregroundStyle(.primary)
                        }

                        if info.stats.videos > 0 {
                            Label {
                                Text("\(info.stats.videos) videos")
                            } icon: {
                                Image(systemName: "film")
                            }
                            .foregroundStyle(.primary)
                        }

                        if info.stats.audio > 0 {
                            Label {
                                Text("\(info.stats.audio) sound clips")
                            } icon: {
                                Image(systemName: "waveform")
                            }
                            .foregroundStyle(.primary)
                        }

                        if info.stats.members > 0 {
                            Label {
                                Text("\(info.stats.members) members")
                            } icon: {
                                Image(systemName: "person.2")
                            }
                            .foregroundStyle(.primary)
                        }
                    } header: {
                        Text("Content")
                    }
                } else if loader.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                AccessRequestsView(authManager: authManager, loader: accessRequestsLoader)

                // Visit site
                if let serverURL = authManager.serverURL {
                    Section {
                        Link(destination: serverURL) {
                            Label("Visit Site", systemImage: "safari")
                        }
                    }
                }

                // Logout
                Section {
                    Button(role: .destructive) {
                        authManager.logout()
                        dismiss()
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                // Version footer
                if let info = loader.info {
                    Section {
                        if let repoURL {
                            Link(destination: repoURL) {
                                Text("v\(info.version) (\(info.gitSHA))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        } else {
                            Text("v\(info.version)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(loader.info?.name ?? authManager.serverURL?.host ?? "Site Info")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard loader.info == nil, let serverURL = authManager.serverURL else { return }
                await loader.load(serverURL: serverURL, token: authManager.sessionToken)
            }
        }
    }
}

/// A text area for a single locale, with a flag label and optional remove button.
struct LocaleTextArea: View {
    @Binding var entry: LocaleEntry
    let isPrimary: Bool
    let onRemove: () -> Void

    private var languageName: String {
        let code = entry.locale.languageCode?.identifier ?? "en"
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(languageName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if !isPrimary {
                    Spacer()
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            TextEditor(text: $entry.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
                .frame(minHeight: 44)
        }
    }
}

/// Sheet for picking a locale to add for translation.
struct LocalePickerSheet: View {
    let existingLocales: [String]
    let siteLocales: [String]
    let onSelect: (Locale.Language) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    /// Common language codes to show as suggestions.
    private static let commonLanguages = [
        "en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "ar",
        "ru", "hi", "nl", "sv", "da", "no", "fi", "pl", "tr", "th",
    ]

    private var allLanguages: [(code: String, name: String)] {
        // Site locales first, then common, then all available.
        var seen = Set(existingLocales)
        var result: [(String, String)] = []

        // Site locales that aren't already added.
        for code in siteLocales where !seen.contains(code) {
            if let name = Locale.current.localizedString(forLanguageCode: code) {
                result.append((code, name))
                seen.insert(code)
            }
        }

        // Common languages.
        for code in Self.commonLanguages where !seen.contains(code) {
            if let name = Locale.current.localizedString(forLanguageCode: code) {
                result.append((code, name))
                seen.insert(code)
            }
        }

        return result
    }

    private var filteredLanguages: [(code: String, name: String)] {
        if searchText.isEmpty { return allLanguages }
        let query = searchText.lowercased()
        return allLanguages.filter {
            $0.code.lowercased().contains(query) || $0.name.lowercased().contains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !siteLocales.isEmpty {
                    let siteFiltered = filteredLanguages.filter { siteLocales.contains($0.code) }
                    if !siteFiltered.isEmpty {
                        Section("Used on this site") {
                            ForEach(siteFiltered, id: \.code) { lang in
                                languageButton(code: lang.code, name: lang.name)
                            }
                        }
                    }
                }

                let otherFiltered = filteredLanguages.filter { !siteLocales.contains($0.code) }
                if !otherFiltered.isEmpty {
                    Section("Other languages") {
                        ForEach(otherFiltered, id: \.code) { lang in
                            languageButton(code: lang.code, name: lang.name)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search languages")
            .navigationTitle("Add Translation")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func languageButton(code: String, name: String) -> some View {
        Button {
            let language = Locale.Language(identifier: code)
            onSelect(language)
            dismiss()
        } label: {
            HStack {
                Text(name)
                Spacer()
                Text(code.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}


#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(NetworkMonitor())
        .environment(
            UploadManager(
                serverURL: URL(string: "http://localhost:8080")!,
                networkMonitor: NetworkMonitor(),
                modelContainer: try! ModelContainer(for: PendingPost.self)
            )
        )
}
