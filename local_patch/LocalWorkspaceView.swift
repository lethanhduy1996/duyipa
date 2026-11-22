import SwiftUI
import UniformTypeIdentifiers

/// File management is confined to this app's Documents directory.
/// Importing through the document picker requires the user's explicit selection.
private enum LocalWorkspaceIO {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TotoroxLocal", isDirectory: true)
    }

    static func list() throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        .filter { ((try? $0.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]))
            .map { $0.isRegularFile == true && $0.isSymbolicLink != true }) ?? false }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func importFiles(_ sources: [URL]) -> (count: Int, errors: [String]) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return (0, ["Không thể tạo thư mục: \(error.localizedDescription)"])
        }

        var copied = 0
        var errors: [String] = []
        for source in sources {
            let scoped = source.startAccessingSecurityScopedResource()
            defer {
                if scoped { source.stopAccessingSecurityScopedResource() }
            }
            do {
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    errors.append("\(source.lastPathComponent): chỉ chấp nhận tệp thường")
                    continue
                }
                let sanitizedName = source.lastPathComponent
                guard !sanitizedName.isEmpty, sanitizedName != ".", sanitizedName != ".." else {
                    errors.append("Tên tệp không hợp lệ")
                    continue
                }
                let proposed = directory.appendingPathComponent(sanitizedName, isDirectory: false)
                let base = proposed.deletingPathExtension().lastPathComponent
                let ext = proposed.pathExtension
                var target = proposed
                var n = 1
                while fm.fileExists(atPath: target.path) {
                    let stem = "\(base) (\(n))"
                    target = directory.appendingPathComponent(
                        ext.isEmpty ? stem : "\(stem).\(ext)", isDirectory: false
                    )
                    n += 1
                    if n > 10000 { throw CocoaError(.fileWriteFileExists) }
                }
                try fm.copyItem(at: source, to: target)
                copied += 1
            } catch {
                errors.append("\(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return (copied, errors)
    }
}

struct LocalWorkspaceView: View {
    @State private var items: [URL] = []
    @State private var showImporter = false
    @State private var isImporting = false
    @State private var showMessage = false
    @State private var message = ""
    @State private var pendingDeletion: URL?

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Quản lý tệp trong vùng Documents của ứng dụng. Không truy cập trái phép dữ liệu của app khác; tính năng ghi đè qua server không có trong bản Local.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                Section("Tệp đã nhập (\(items.count))") {
                    if items.isEmpty {
                        Text("Chưa có tệp. Chọn Nhập tệp để bắt đầu.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(items, id: \.path) { file in
                        HStack(spacing: 12) {
                            Image(systemName: "doc.zipper")
                                .foregroundColor(.mint)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.lastPathComponent)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            ShareLink(item: file) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel("Chia sẻ \(file.lastPathComponent)")
                        }
                        .swipeActions {
                            Button(role: .destructive) { pendingDeletion = file } label: {
                                Label("Xóa", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tệp Local")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Làm mới")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImporter = true } label: {
                        Label("Nhập tệp", systemImage: "plus")
                    }
                    .disabled(isImporting)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear { reload() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                isImporting = true
                Task.detached(priority: .userInitiated) {
                    let outcome = LocalWorkspaceIO.importFiles(urls)
                    await MainActor.run {
                        isImporting = false
                        reload()
                        message = "Đã nhập \(outcome.count) tệp."
                        if !outcome.errors.isEmpty {
                            message += "\n" + outcome.errors.prefix(3).joined(separator: "\n")
                        }
                        showMessage = true
                    }
                }
            case .failure(let error):
                message = error.localizedDescription
                showMessage = true
            }
        }
        .alert("Kết quả", isPresented: $showMessage) {
            Button("Đóng", role: .cancel) {}
        } message: {
            Text(message)
        }
        .alert("Xóa tệp?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Xóa", role: .destructive) {
                if let url = pendingDeletion {
                    do { try FileManager.default.removeItem(at: url) }
                    catch {
                        message = error.localizedDescription
                        showMessage = true
                    }
                }
                pendingDeletion = nil
                reload()
            }
            Button("Hủy", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Tệp sẽ bị xóa khỏi Documents của Totorox Local.")
        }
    }

    private func reload() {
        do { items = try LocalWorkspaceIO.list() }
        catch {
            items = []
            message = error.localizedDescription
            showMessage = true
        }
    }
}
