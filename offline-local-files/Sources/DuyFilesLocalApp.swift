import SwiftUI
import UniformTypeIdentifiers
import QuickLook

@main
struct DuyFilesLocalApp: App {
    var body: some Scene {
        WindowGroup {
            LocalFileBrowser()
        }
    }
}

private struct FileEntry: Identifiable {
    let url: URL
    let isDirectory: Bool
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

struct LocalFileBrowser: View {
    private let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    @State private var folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    @State private var entries: [FileEntry] = []
    @State private var showImporter = false
    @State private var showCreateFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: FileEntry?
    @State private var renameText = ""
    @State private var showRename = false
    @State private var deleteTarget: FileEntry?
    @State private var showDelete = false
    @State private var previewURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""

    private var isAtRoot: Bool {
        folder.standardizedFileURL == root.standardizedFileURL
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if entries.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("Chưa có tệp")
                                .font(.headline)
                            Text("Nhập tệp hoặc tạo thư mục để bắt đầu.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    } else {
                        ForEach(entries) { entry in
                            Button {
                                if entry.isDirectory {
                                    folder = entry.url
                                    refresh()
                                } else {
                                    previewURL = entry.url
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                                        .foregroundStyle(entry.isDirectory ? .mint : .blue)
                                        .frame(width: 24)
                                    Text(entry.name)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Spacer()
                                    if entry.isDirectory {
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 5)
                            }
                            .contextMenu {
                                ShareLink(item: entry.url) {
                                    Label("Chia sẻ / Xuất", systemImage: "square.and.arrow.up")
                                }
                                Button {
                                    renameTarget = entry
                                    renameText = entry.name
                                    showRename = true
                                } label: {
                                    Label("Đổi tên", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    deleteTarget = entry
                                    showDelete = true
                                } label: {
                                    Label("Xóa", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text(isAtRoot ? "Tệp trong ứng dụng" : folder.lastPathComponent)
                } footer: {
                    Text("Hoạt động ngoại tuyến. Chỉ truy cập vùng tài liệu của ứng dụng và những tệp bạn chọn nhập.")
                }
            }
            .navigationTitle("DuyFiles Local")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !isAtRoot {
                        Button {
                            folder.deleteLastPathComponent()
                            refresh()
                        } label: {
                            Label("Quay lại", systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        newFolderName = ""
                        showCreateFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("Tạo thư mục")
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Nhập tệp")
                }
            }
            .onAppear(perform: refresh)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer {
                            if accessed { url.stopAccessingSecurityScopedResource() }
                        }
                        do {
                            try FileManager.default.copyItem(
                                at: url,
                                to: availableDestination(for: url.lastPathComponent)
                            )
                        } catch {
                            displayError(error)
                        }
                    }
                    refresh()
                case .failure(let error):
                    displayError(error)
                }
            }
            .quickLookPreview($previewURL)
            .alert("Tạo thư mục", isPresented: $showCreateFolder) {
                TextField("Tên thư mục", text: $newFolderName)
                Button("Tạo") { createFolder() }
                Button("Hủy", role: .cancel) {}
            } message: {
                Text("Thư mục mới sẽ nằm trong thư mục hiện tại.")
            }
            .alert("Đổi tên", isPresented: $showRename) {
                TextField("Tên mới", text: $renameText)
                Button("Lưu") { renameEntry() }
                Button("Hủy", role: .cancel) { renameTarget = nil }
            }
            .confirmationDialog("Xóa mục này?", isPresented: $showDelete) {
                Button("Xóa vĩnh viễn", role: .destructive) { deleteEntry() }
                Button("Hủy", role: .cancel) { deleteTarget = nil }
            } message: {
                Text(deleteTarget?.name ?? "")
            }
            .alert("Không thể thực hiện", isPresented: $showError) {
                Button("Đóng", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .tint(.mint)
    }

    private func refresh() {
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            entries = contents.map { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FileEntry(url: url, isDirectory: isDirectory)
            }.sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } catch {
            entries = []
            displayError(error)
        }
    }

    private func safeName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != "..",
              !trimmed.contains("/"), !trimmed.contains("\\") else {
            return nil
        }
        return trimmed
    }

    private func availableDestination(for name: String) -> URL {
        let desired = folder.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: desired.path) { return desired }
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 1
        while true {
            let candidateName = ext.isEmpty ? "\(stem) (\(index))" : "\(stem) (\(index)).\(ext)"
            let candidate = folder.appendingPathComponent(candidateName)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
    }

    private func createFolder() {
        guard let name = safeName(newFolderName) else {
            errorMessage = "Tên thư mục không hợp lệ."
            showError = true
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: availableDestination(for: name),
                withIntermediateDirectories: false
            )
            refresh()
        } catch {
            displayError(error)
        }
    }

    private func renameEntry() {
        guard let target = renameTarget else { return }
        defer { renameTarget = nil }
        guard let name = safeName(renameText) else {
            errorMessage = "Tên mới không hợp lệ."
            showError = true
            return
        }
        let destination = folder.appendingPathComponent(name)
        if destination.standardizedFileURL == target.url.standardizedFileURL { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            errorMessage = "Tên này đã tồn tại."
            showError = true
            return
        }
        do {
            try FileManager.default.moveItem(at: target.url, to: destination)
            refresh()
        } catch {
            displayError(error)
        }
    }

    private func deleteEntry() {
        guard let target = deleteTarget else { return }
        defer { deleteTarget = nil }
        do {
            try FileManager.default.removeItem(at: target.url)
            refresh()
        } catch {
            displayError(error)
        }
    }

    private func displayError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
    }
}
