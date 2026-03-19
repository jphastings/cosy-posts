import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
@preconcurrency import Translation
import os

private let infoLog = Logger(subsystem: "com.cosyposts", category: "SiteInfo")
private let translationLog = Logger(subsystem: "com.cosyposts", category: "Translation")

struct ContentView: View {
    @State private var viewModel = ComposeViewModel()
    @State private var showingSiteSheet = false
    @State private var siteInfoLoader = SiteInfoLoader()
    @State private var accessRequestsLoader = AccessRequestsLoader()
    @State private var translationManager = TranslationManager()
    @State private var translationConfig: TranslationSession.Configuration?
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

                // Main content: media (if any) + text panel
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        if !viewModel.mediaItems.isEmpty {
                            let mediaHeight = min(
                                geo.size.width / viewModel.averageMediaAspectRatio,
                                geo.size.height * 0.75
                            )

                            PhotosPicker(
                                selection: $viewModel.selectedPhotos,
                                maxSelectionCount: 20,
                                matching: .any(of: [.images, .videos]),
                                photoLibrary: .shared()
                            ) {
                                MediaCarouselView(
                                    items: viewModel.mediaItems,
                                    onRemove: { id in viewModel.removeMedia(id: id) }
                                )
                            }
                            .buttonStyle(.plain)
                            .frame(height: mediaHeight)

                            Divider()

                            // Text fills remaining space (at least 25% of total)
                            LocaleTextArea(
                                entry: $viewModel.localeEntries[viewModel.activeLocaleIndex],
                                localeCount: viewModel.localeEntries.count,
                                onCycleLocale: { viewModel.cycleLocale() }
                            )
                            .frame(maxHeight: .infinity)
                        } else {
                            // No media — tappable placeholder + text area
                            PhotosPicker(
                                selection: $viewModel.selectedPhotos,
                                maxSelectionCount: 20,
                                matching: .any(of: [.images, .videos]),
                                photoLibrary: .shared()
                            ) {
                                MediaPlaceholderView()
                            }
                            .buttonStyle(.plain)
                            .frame(height: geo.size.height * 0.25)

                            Divider()

                            LocaleTextArea(
                                entry: $viewModel.localeEntries[viewModel.activeLocaleIndex],
                                localeCount: viewModel.localeEntries.count,
                                onCycleLocale: { viewModel.cycleLocale() }
                            )
                            .frame(maxHeight: .infinity)
                        }
                    }
                }
                .onDrop(of: [.image, .movie, .audio, .fileURL], isTargeted: $viewModel.isDropTargeted) { providers in
                    viewModel.handleDrop(providers: providers)
                    return true
                }

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
                    viewModel: $viewModel,
                    siteLocales: siteInfoLoader.info?.locales ?? [],
                    onAdd: { language, autoTranslate in
                        viewModel.addLocale(language)
                        if autoTranslate {
                            let primaryText = viewModel.bodyText
                            let targetCode = language.languageCode?.identifier ?? ""
                            // Mark as translating for skeleton UI
                            if let idx = viewModel.localeEntries.firstIndex(where: { $0.locale == language }) {
                                viewModel.localeEntries[idx].isTranslating = true
                            }
                            let config = translationManager.prepareTranslation(text: primaryText, to: targetCode) { translated in
                                if let idx = viewModel.localeEntries.firstIndex(where: { $0.locale == language }) {
                                    viewModel.localeEntries[idx].text = translated
                                    viewModel.localeEntries[idx].isTranslating = false
                                }
                            }
                            if let config {
                                translationConfig = nil
                                Task { @MainActor in
                                    translationConfig = config
                                }
                                // Timeout: if translation hasn't completed after 10s, clear skeleton so user can type
                                Task { @MainActor in
                                    try? await Task.sleep(for: .seconds(10))
                                    if let idx = viewModel.localeEntries.firstIndex(where: { $0.locale == language }),
                                       viewModel.localeEntries[idx].isTranslating {
                                        translationLog.warning("Translation to \(targetCode) timed out after 10s")
                                        viewModel.localeEntries[idx].isTranslating = false
                                    }
                                }
                            } else {
                                // Translation not available, clear skeleton
                                if let idx = viewModel.localeEntries.firstIndex(where: { $0.locale == language }) {
                                    viewModel.localeEntries[idx].isTranslating = false
                                }
                            }
                        }
                    },
                    translationManager: translationManager
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
            .translationTask(translationConfig) { session in
                guard let pending = translationManager.pendingTranslation else { return }
                translationManager.pendingTranslation = nil
                // NOTE: do NOT set translationConfig = nil here — that cancels this task!

                do {
                    let response = try await session.translate(pending.text)
                    translationLog.info("Translated to \(pending.targetCode): \(response.targetText.prefix(40))…")
                    pending.completion(response.targetText)
                } catch {
                    translationLog.error("Translation failed: \(error.localizedDescription)")
                    // Clear the translating state so the user can type manually
                    if let idx = viewModel.localeEntries.firstIndex(where: {
                        $0.locale.languageCode?.identifier == pending.targetCode
                    }) {
                        viewModel.localeEntries[idx].isTranslating = false
                    }
                }
                // Reset config after translation completes so next request can trigger nil→non-nil
                translationConfig = nil
            }
            .onChange(of: viewModel.localeEntries.first?.locale) {
                translationManager.sourceLanguage = viewModel.localeEntries.first?.locale
            }
            .onAppear {
                translationManager.sourceLanguage = viewModel.localeEntries.first?.locale
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

/// A text area for a single locale, with a tappable language label that cycles between locales.
struct LocaleTextArea: View {
    @Binding var entry: LocaleEntry
    let localeCount: Int
    let onCycleLocale: () -> Void

    private var languageName: String {
        let code = entry.locale.languageCode?.identifier ?? "en"
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                if entry.isTranslating {
                    ProgressView()
                        .controlSize(.mini)
                }
                Button(action: onCycleLocale) {
                    HStack(spacing: 4) {
                        Text(languageName)
                            .font(.caption2)
                            .textCase(.uppercase)
                        if localeCount > 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(localeCount <= 1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            if entry.isTranslating {
                SkeletonTextView()
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
            } else {
                TextEditor(text: $entry.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Animated skeleton placeholder for text being translated.
/// Uses a standard iOS-style sliding shimmer highlight.
struct SkeletonTextView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SkeletonLine(widthFraction: 0.9, phase: phase)
            SkeletonLine(widthFraction: 0.75, phase: phase)
            SkeletonLine(widthFraction: 0.6, phase: phase)
        }
        .padding(.vertical, 8)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
    }
}

private struct SkeletonLine: View {
    let widthFraction: CGFloat
    var phase: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.secondary.opacity(0.12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 12)
            .scaleEffect(x: widthFraction, anchor: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let w = geo.size.width * widthFraction
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .secondary.opacity(0.15), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: w * 0.4)
                        .offset(x: phase * w)
                }
                .clipped()
            }
    }
}

/// Tappable placeholder shown when no media is selected.
private struct MediaPlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Add Photos or Videos")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.secondary.opacity(0.08))
    }
}

/// Sheet for toggling locale entries on/off with checkmarks.
struct LocalePickerSheet: View {
    @Binding var viewModel: ComposeViewModel
    let siteLocales: [String]
    let onAdd: (Locale.Language, Bool) -> Void // (language, canAutoTranslate)
    var translationManager: TranslationManager
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var entryToRemove: LocaleEntry?

    private var enabledCodes: Set<String> {
        Set(viewModel.localeEntries.compactMap { $0.locale.languageCode?.identifier })
    }

    private var primaryCode: String? {
        viewModel.localeEntries.first?.locale.languageCode?.identifier
    }

    /// Common language codes to show as suggestions.
    private static let commonLanguages = [
        "en", "es", "fr", "de", "it", "pt", "zh", "ja", "ko", "ar",
        "ru", "hi", "nl", "sv", "da", "no", "fi", "pl", "tr", "th",
    ]

    private var allLanguages: [(code: String, name: String)] {
        var seen = Set<String>()
        var result: [(String, String)] = []

        // Enabled locales first.
        for entry in viewModel.localeEntries {
            let code = entry.locale.languageCode?.identifier ?? "en"
            if !seen.contains(code), let name = Locale.current.localizedString(forLanguageCode: code) {
                result.append((code, name))
                seen.insert(code)
            }
        }

        // Site locales.
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

    /// If the search text looks like a language code not in the list, offer to add it.
    private var customCodeEntry: (code: String, name: String)? {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let pattern = /^[a-zA-Z]{2,3}(-[a-zA-Z]{2,4})?$/
        guard trimmed.wholeMatch(of: pattern) != nil else { return nil }
        let code = trimmed.lowercased()
        guard !enabledCodes.contains(code) else { return nil }
        guard !filteredLanguages.contains(where: { $0.code.lowercased() == code }) else { return nil }
        let name = Locale.current.localizedString(forLanguageCode: code)
        return (code: code, name: name ?? code)
    }

    var body: some View {
        NavigationStack {
            List {
                // Custom code entry row
                if let custom = customCodeEntry {
                    Section {
                        Button {
                            let language = Locale.Language(identifier: custom.code)
                            let status = translationManager.statuses[custom.code]
                            onAdd(language, status == .available)
                        } label: {
                            HStack {
                                Label {
                                    Text("Add \"\(custom.name)\"")
                                } icon: {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                                Spacer()
                                Text(custom.code.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !siteLocales.isEmpty {
                    let siteFiltered = filteredLanguages.filter { siteLocales.contains($0.code) }
                    if !siteFiltered.isEmpty {
                        Section("Used on this site") {
                            ForEach(siteFiltered, id: \.code) { lang in
                                languageRow(code: lang.code, name: lang.name)
                            }
                        }
                    }
                }

                let otherFiltered = filteredLanguages.filter { !siteLocales.contains($0.code) }
                if !otherFiltered.isEmpty {
                    Section("Other languages") {
                        ForEach(otherFiltered, id: \.code) { lang in
                            languageRow(code: lang.code, name: lang.name)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search languages or enter code (e.g. cy, en-GB)")
            .navigationTitle("Languages")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Remove translation?",
                isPresented: Binding(
                    get: { entryToRemove != nil },
                    set: { if !$0 { entryToRemove = nil } }
                ),
                presenting: entryToRemove
            ) { entry in
                Button("Keep \(localeName(for: entry))") { }
                Button("Discard translation", role: .destructive) {
                    viewModel.removeLocale(id: entry.id)
                }
            } message: { entry in
                Text(entry.text)
            }
            .task {
                let codes = allLanguages.map(\.code)
                if let source = translationManager.sourceLanguage {
                    await translationManager.checkAvailability(for: codes, from: source)
                }
            }
        }
    }

    private func languageRow(code: String, name: String) -> some View {
        let isEnabled = enabledCodes.contains(code)
        let isPrimary = code == primaryCode
        let status = translationManager.statuses[code] ?? .unsupported

        return Button {
            if isEnabled {
                guard !isPrimary else { return }
                if let entry = viewModel.localeEntries.first(where: {
                    $0.locale.languageCode?.identifier == code
                }) {
                    if entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.removeLocale(id: entry.id)
                    } else {
                        entryToRemove = entry
                    }
                }
            } else {
                let language = Locale.Language(identifier: code)
                onAdd(language, status == .available)
            }
        } label: {
            HStack {
                Text(name)
                Spacer()
                if isEnabled && isPrimary {
                    Text("Primary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(code.uppercased())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isEnabled {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                } else if status == .available {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .disabled(isPrimary && isEnabled)
    }

    private func localeName(for entry: LocaleEntry) -> String {
        let code = entry.locale.languageCode?.identifier ?? "en"
        return Locale.current.localizedString(forLanguageCode: code) ?? code
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
