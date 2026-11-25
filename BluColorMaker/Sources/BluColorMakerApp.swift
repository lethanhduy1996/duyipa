import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct BluColorMakerApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem { Label("Make màu", systemImage: "paintpalette") }
                OfflineWebTab()
                    .tabItem { Label("Web offline", systemImage: "globe") }
            }.preferredColorScheme(.dark)
        }
    }
}

struct RGB: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var color: Color { Color(red: r, green: g, blue: b) }
    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }
    init(_ color: Color) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(Double(red), Double(green), Double(blue))
        } else { self.init(1, 1, 1) }
    }
    static let pink = RGB(1, 0, 0.8)
    static let cyan = RGB(0, 1, 1)
    static let palette: [RGB] = [
        RGB(1,0.08,0.08), RGB(1,0.42,0), RGB(1,0.95,0),
        RGB(0.1,1,0.2), .cyan, RGB(0.15,0.35,1),
        RGB(0.6,0.1,1), .pink, RGB(1,1,1)
    ]
    var hex: String {
        func byte(_ v: Double) -> Int { v.isFinite ? Int((min(1, max(0, v)) * 255).rounded()) : 0 }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
    static func fromHex(_ raw: String) -> RGB? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard code.count == 6, code.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }),
              let value = UInt32(code, radix: 16) else { return nil }
        return RGB(Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }
}

enum Effect: String, CaseIterable, Codable, Identifiable {
    case solid = "Màu cố định"
    case blend = "Chuyển hai màu"
    case scan = "Quét sáng"
    case pulse = "Nhấp nháy mềm"
    case rainbow = "RGB cầu vồng"
    var id: String { rawValue }
}

struct Preset: Codable, Identifiable {
    var id = UUID()
    var name = "Neon mới"
    var first = RGB.pink
    var second = RGB.cyan
    var effect: Effect = .scan
    var duration: Double = 3
    var intensity: Double = 0.7
    var scanNoise: Double? = 0.15
    var rim: RGB? = .cyan
    var rimStrength: Double? = 0.6
    var scanStrength: Double? = 1
    static var initial: [Preset] {
        [
            Preset(name: "Tím hồng", first: RGB(0.6,0.1,1), second: .pink, effect: .blend),
            Preset(name: "Đỏ vàng", first: RGB(1,0.05,0.05), second: RGB(1,0.95,0), effect: .scan),
            Preset(name: "RGB Neon", effect: .rainbow)
        ]
    }
}

struct PreviewCharacter: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 120, rect.height / 200)
        let ox = rect.midX - 60 * scale
        let oy = rect.midY - 100 * scale
        var p = Path()
        p.addEllipse(in: CGRect(x: ox + 46*scale, y: oy + 3*scale, width: 28*scale, height: 36*scale))
        let points: [(CGFloat, CGFloat)] = [
            (43,43),(60,38),(77,43),(91,54),(108,109),(94,115),
            (78,78),(77,112),(88,186),(69,190),(60,129),(51,190),
            (32,186),(43,112),(42,78),(26,115),(12,109),(29,54)
        ]
        for (i, point) in points.enumerated() {
            let next = CGPoint(x: ox + point.0*scale, y: oy + point.1*scale)
            if i == 0 { p.move(to: next) } else { p.addLine(to: next) }
        }
        p.closeSubpath()
        return p
    }
}

struct NeonPreview: View {
    let preset: Preset
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    private func mix(_ a: RGB, _ b: RGB, _ t: Double) -> Color {
        Color(red: a.r+(b.r-a.r)*t, green: a.g+(b.g-a.g)*t, blue: a.b+(b.b-a.b)*t)
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0.0 : context.date.timeIntervalSinceReferenceDate
            let t = time.truncatingRemainder(dividingBy: max(0.5,preset.duration)) / max(0.5,preset.duration)
            frame(phase: t)
        }
    }
    private func scanCanvas(phase: Double) -> some View {
        Canvas { context, size in
            let cols = 24, rows = 36
            let w = size.width / CGFloat(cols)
            let h = size.height / CGFloat(rows)
            let noise = max(0, min(1, preset.scanNoise ?? 0))
            for y in 0..<rows {
                for x in 0..<cols {
                    let u = (Double(x) + 0.5) / Double(cols)
                    let v = 1 - (Double(y) + 0.5) / Double(rows)
                    let n = 0.62 * sin((u * 7 + v * 3 + phase) * 2 * .pi)
                        + 0.38 * sin((u * 13 - v * 9 - phase * 2) * 2 * .pi)
                    let warped = v + noise * 0.25 * n
                    let scan = (0.5 + 0.5 * cos((warped - phase) * 2 * .pi)) * (preset.scanStrength ?? 1)
                    let c: Color
                    if preset.effect == .rainbow {
                        let rawHue = phase + warped * 0.3
                        c = Color(hue: rawHue - floor(rawHue), saturation: 1, brightness: 1)
                    } else {
                        let white = pow(scan, 18) * 0.85
                        func channel(_ a: Double, _ b: Double) -> Double {
                            let mixed = a + (b - a) * scan
                            return mixed + (1 - mixed) * white
                        }
                        c = Color(red: channel(preset.first.r, preset.second.r),
                                  green: channel(preset.first.g, preset.second.g),
                                  blue: channel(preset.first.b, preset.second.b))
                    }
                    context.fill(Path(CGRect(x: CGFloat(x)*w, y: CGFloat(y)*h, width: w+0.5, height: h+0.5)), with: .color(c))
                }
            }
        }
    }
    private func frame(phase: Double) -> some View {
        let wave = (1 - cos(phase * 2 * .pi)) / 2
        let mixed = mix(preset.first, preset.second, wave)
        let main = preset.effect == .rainbow ? Color(hue: phase, saturation: 1, brightness: 1) :
            (preset.effect == .blend ? mixed : preset.first.color)
        let alpha = preset.effect == .pulse ? 0.45 + 0.55*wave : 1.0
        let glow = preset.intensity * 18
        let showScan = preset.effect == .scan || preset.effect == .rainbow
        return ZStack {
            RoundedRectangle(cornerRadius: 24).fill(
                RadialGradient(colors: [Color(red:0.13,green:0.14,blue:0.21), Color(red:0.04,green:0.04,blue:0.07)], center: .center, startRadius: 15, endRadius: 240)
            )
            VStack {
                HStack {
                    Label("Xem trước", systemImage: "sparkles").font(.caption.weight(.semibold))
                    Spacer()
                    Text(preset.effect.rawValue).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Mô hình minh họa · Không kết nối game").font(.caption2).foregroundStyle(.secondary)
            }.padding(16)
            ZStack {
                PreviewCharacter().fill(main).blur(radius: glow * 0.65).opacity(0.75)
                PreviewCharacter().fill(main)
                if showScan {
                    scanCanvas(phase: phase).mask(PreviewCharacter().fill(.white))
                }
                PreviewCharacter().stroke((preset.rim ?? .cyan).color.opacity(preset.rimStrength ?? 0.6), lineWidth: 1.3)
            }
            .opacity(alpha)
            .shadow(color: main.opacity(preset.intensity), radius: glow, x: 0, y: 0)
            .frame(width: 160, height: 228)
        }.frame(height: 300)
    }
}

struct PalettePicker: View {
    let title: String
    @Binding var rgb: RGB
    @State private var hexInput = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                TextField("#RRGGBB", text: $hexInput)
                    .font(.caption.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 104)
                    .onSubmit { if let parsed = RGB.fromHex(hexInput) { rgb = parsed } }
                Button("Đặt") {
                    if let parsed = RGB.fromHex(hexInput) { rgb = parsed; hexInput = parsed.hex }
                }.font(.caption).disabled(RGB.fromHex(hexInput) == nil)
                ColorPicker("", selection: Binding(get: { rgb.color }, set: { rgb = RGB($0) }), supportsOpacity: false)
                    .labelsHidden()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 9), spacing: 6) {
                ForEach(Array(RGB.palette.enumerated()), id: \.offset) { _, item in
                    Button { rgb = item } label: {
                        Circle().fill(item.color)
                            .overlay(Circle().strokeBorder(.white, lineWidth: rgb == item ? 3 : 0))
                            .frame(width: 26, height: 26)
                            .frame(minWidth: 30, minHeight: 40)
                    }.buttonStyle(.plain).accessibilityLabel(item.hex)
                }
            }
        }.onAppear { hexInput = rgb.hex }
         .onChange(of: rgb) { value in hexInput = value.hex }
    }
}

struct PresetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// File roles are UI labels based on the filename convention, not a verified shader role.
private enum SourceCategory: String, CaseIterable, Identifiable {
    case opti, shader, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .opti: return "Opti · Nhân vật"
        case .shader: return "Shader · Súng"
        case .other: return "Khác"
        }
    }
    static func classify(_ filename: String) -> Self {
        let name = filename.lowercased()
        if name.hasPrefix("optionalavatarres_commonab_shader") { return .opti }
        if name.hasPrefix("shaders.") || name.hasPrefix("shaders(") || name == "shaders" { return .shader }
        return .other
    }
}

struct ContentView: View {
    @State private var current = Preset()
    @State private var sourceCategory: SourceCategory = .opti
    @State private var categoryPresets: [SourceCategory: Preset] = [:]
    @State private var saved: [Preset] = Self.loadPresets()
    @State private var export = false
    @State private var document = PresetDocument()
    @State private var message: String?
    @State private var sourcePicker: SourcePickerMode?
    @State private var sourceFolder: URL?
    @State private var folderFiles: [URL] = []
    @State private var importError: String? = nil
    @State private var sourceName: String? = nil
    @State private var sourceInfo: String? = nil
    @State private var binaryReference = false
    @State private var decorativeBundle: DecorativeBundle?
    @State private var selectedFieldID: Int?
    @State private var shaderExport: ShaderExportItem?
    private static let storageKey = "blu.presets.v1"
    private static func loadPresets() -> [Preset] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let result = try? JSONDecoder().decode([Preset].self, from: data) else { return Preset.initial }
        return result
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
    private func save() {
        var copy = current
        copy.id = UUID()
        let name = copy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.name = name.isEmpty ? "Neon mới" : name
        saved.insert(copy, at: 0)
        persist()
        message = "Đã lưu mẫu \(copy.name)"
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fileControls
                    NeonPreview(preset: current)
                    controls
                    shaderActions
                    presets
                    Text("Chỉnh mẫu Blu hoặc thuộc tính RGB trang trí của UnityFS được hỗ trợ. Không chỉnh chương trình shader hoặc tạo patch game.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(16)
            }
            .navigationTitle("Blu Color Maker")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { current = Preset() } label: { Image(systemName: "arrow.counterclockwise") }
                        .accessibilityLabel("Đặt lại")
                }
            }
        }
        .fileExporter(isPresented: $export, document: document, contentType: .json,
                      defaultFilename: "BluPreset") { result in
            switch result {
            case .success: message = "Đã xuất cấu hình JSON"
            case .failure(let error): message = error.localizedDescription
            }
        }
        .sheet(item: $sourcePicker) { mode in
            NativeSourcePicker(mode: mode) { url in
                sourcePicker = nil
                guard let url = url else { return }
                if mode == .folder { openReferenceFolder(url) }
                else { readSource(url) }
            }
        }
        .sheet(item: $shaderExport) { item in
            ShaderExportPicker(url: item.url) { success in
                shaderExport = nil
                if success { message = "Đã xuất tệp mới" }
            }
        }
        .alert("Blu Color Maker", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
    private func openReferenceFolder(_ url: URL) {
        importError = nil
        folderFiles = []
        sourceFolder = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            folderFiles = children.filter {
                (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            sourceFolder = url
            if folderFiles.isEmpty { importError = "Không tìm thấy tệp trong thư mục đã chọn." }
        } catch { importError = error.localizedDescription }
    }
    private func switchCategory(_ category: SourceCategory) {
        guard category != sourceCategory else { return }
        categoryPresets[sourceCategory] = current
        current = categoryPresets[category] ?? Preset()
        sourceCategory = category
        sourceName = nil
        sourceInfo = nil
        importError = nil
        binaryReference = false
        decorativeBundle = nil
        selectedFieldID = nil
    }
    private func readSource(_ url: URL, parent: URL? = nil) {
        switchCategory(SourceCategory.classify(url.lastPathComponent))
        importError = nil
        sourceName = nil
        sourceInfo = nil
        binaryReference = false
        decorativeBundle = nil
        selectedFieldID = nil
        let accessURL = parent ?? url
        let scoped = accessURL.startAccessingSecurityScopedResource()
        defer { if scoped { accessURL.stopAccessingSecurityScopedResource() } }
        do {
            let limit = 32 * 1024 * 1024
            let info = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            guard info.isDirectory != true else { throw ShaderIOError.invalid }
            if let size = info.fileSize, size > limit { throw ShaderIOError.tooLarge }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var bytes = Data()
            while bytes.count <= limit {
                guard let chunk = try file.read(upToCount: min(256 * 1024, limit + 1 - bytes.count)), !chunk.isEmpty else { break }
                bytes.append(chunk)
            }
            guard bytes.count <= limit else { throw ShaderIOError.tooLarge }
            sourceName = url.lastPathComponent
            if let header = try BluReferenceHeader.inspect(bytes) {
                sourceInfo = header
                binaryReference = true
                do {
                    let bundle = try DecorativeBundle(bytes)
                    decorativeBundle = bundle
                    selectedFieldID = bundle.fields.first?.id
                    if bundle.fields.isEmpty { importError = BundleColorError.noColors.localizedDescription }
                } catch { importError = error.localizedDescription }
            } else {
                let loaded = try BluShaderIO.readReference(bytes, ext: url.pathExtension.lowercased(), fallback: current)
                current = loaded.preset
                sourceInfo = loaded.detail
            }
        } catch {
            importError = error.localizedDescription
        }
    }
    private var fileControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tệp nguồn", systemImage: "folder").font(.headline)
            Picker("Loại tài nguyên", selection: Binding(
                get: { sourceCategory },
                set: { switchCategory($0) }
            )) {
                ForEach(SourceCategory.allCases) { category in
                    Text(category.title).tag(category)
                }
            }.pickerStyle(.segmented)
            Text(sourceCategory == .opti ? "Opti — optionalavatarres_commonab_shader…" :
                 sourceCategory == .shader ? "Shader — shaders…" : "Tài nguyên Unity khác")
                .font(.caption).foregroundStyle(.secondary)
            Text(sourceName ?? "Chưa nhập tệp")
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Button { importError = nil; sourcePicker = .file } label: {
                    Label("Nhập tệp", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                Button {
                    switchCategory(.other)
                    sourceName = "BluNeon.shader (mẫu)"
                    sourceInfo = nil
                    importError = nil
                    binaryReference = false
                    decorativeBundle = nil
                    selectedFieldID = nil
                } label: {
                    Text("Dùng mẫu").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
            Button {
                importError = nil
                sourcePicker = .folder
            } label: {
                Label("Chọn thư mục nếu tệp không chọn được", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
            if let folder = sourceFolder {
                let filtered = folderFiles.filter { SourceCategory.classify($0.lastPathComponent) == sourceCategory }
                DisclosureGroup("Tệp \(sourceCategory.title) (\(filtered.count))") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            if filtered.isEmpty {
                                Text("Không có tệp thuộc mục này. Chọn mục khác để xem.").font(.caption)
                            }
                            ForEach(filtered, id: \.self) { url in
                                Button {
                                    readSource(url, parent: folder)
                                } label: {
                                    HStack {
                                        Image(systemName: "doc")
                                        Text(url.lastPathComponent).font(.caption).multilineTextAlignment(.leading)
                                        Spacer()
                                        if sourceName == url.lastPathComponent { Image(systemName: "checkmark") }
                                    }.padding(.vertical, 6)
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxHeight: 220)
                }.font(.subheadline)
            }
            if let error = importError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let info = sourceInfo {
                Label(info, systemImage: binaryReference ? "doc.text.magnifyingglass" : "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if binaryReference {
                Text("Phân loại theo tên tệp. Chức năng đồ họa thực tế chưa được xác minh.")
                    .font(.caption).foregroundStyle(.secondary)
                if let bundle = decorativeBundle, !bundle.fields.isEmpty {
                    Text("Thuộc tính màu trang trí").font(.subheadline.weight(.medium))
                    Picker("Vật liệu / màu", selection: $selectedFieldID) {
                        ForEach(bundle.fields) { field in
                            Text(field.title).tag(Optional(field.id))
                        }
                    }.pickerStyle(.menu)
                    Text("Chỉ đổi RGB của thuộc tính đã chọn. Giữ nguyên alpha và mã shader; không áp dụng tốc độ, quét hoặc HDR vào UnityFS.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Tệp này chưa có thuộc tính màu trang trí được hỗ trợ. Không thể xuất UnityFS đã sửa.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Chọn tệp tối đa 32 MB, kể cả đuôi lạ. Hỗ trợ shader văn bản, JSON và UnityFS có material tương thích.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16)
         .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private var shaderActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                do {
                    let data: Data
                    let filename: String
                    if binaryReference {
                        guard let bundle = decorativeBundle, let id = selectedFieldID,
                              let name = sourceName, !name.isEmpty else { throw BundleColorError.noColors }
                        data = try bundle.export(fieldID: id, red: current.first.r, green: current.first.g, blue: current.first.b)
                        filename = name
                    } else {
                        data = try BluShaderIO.render(current)
                        filename = "BluNeon.shader"
                    }
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent(filename)
                    try data.write(to: url, options: .atomic)
                    shaderExport = ShaderExportItem(url: url)
                } catch { message = error.localizedDescription }
            } label: {
                Label(binaryReference ? "Áp dụng & xuất UnityFS" : "Áp dụng & xuất shader", systemImage: "square.and.arrow.up")
                    .font(.headline).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent)
             .disabled(binaryReference && (decorativeBundle == nil || selectedFieldID == nil))
            Text(binaryReference ? "Xuất bản sao UnityFS giữ nguyên tên tệp gốc. Chỉ thay RGB của material được chọn." : "Xuất mã nguồn mới cho Unity; giữ nguyên tệp đã nhập.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
         .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Thiết kế màu").font(.title3.bold())
            PalettePicker(title: "Màu chính", rgb: $current.first)
            PalettePicker(title: "Màu quét / màu phụ", rgb: $current.second)
            DisclosureGroup("Hologram trang trí · Xem trước") {
                VStack(alignment: .leading, spacing: 12) {
                    PalettePicker(title: "Màu sáng mép", rgb: Binding(
                        get: { current.rim ?? .cyan }, set: { current.rim = $0 }))
                    HStack {
                        Text("Độ sáng mép")
                        Spacer()
                        Text("\(Int((current.rimStrength ?? 0.6) * 100))%").monospacedDigit()
                    }
                    Slider(value: Binding(get: { current.rimStrength ?? 0.6 }, set: { current.rimStrength = $0 }), in: 0...1)
                    HStack {
                        Text("Độ mạnh quét")
                        Spacer()
                        Text("\(Int((current.scanStrength ?? 1) * 100))%").monospacedDigit()
                    }
                    Slider(value: Binding(get: { current.scanStrength ?? 1 }, set: { current.scanStrength = $0 }), in: 0...1)
                    Text("Dành cho mô hình xem trước và shader trang trí độc lập. Không thay shader định vị hoặc trạng thái hiển thị của game.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
            Picker("Hiệu ứng", selection: $current.effect) {
                ForEach(Effect.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu)
            HStack {
                Text("Chu kỳ chuyển động")
                Spacer()
                Text(String(format: "%.1f giây", current.duration)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $current.duration, in: 0.5...10, step: 0.5)
            HStack {
                Text("Độ phát sáng")
                Spacer()
                Text("\(Int(current.intensity * 100))%").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $current.intensity, in: 0...1)
            if current.effect == .scan || current.effect == .rainbow {
                HStack {
                    Text("Độ nhiễu màu quét")
                    Spacer()
                    Text("\(Int((current.scanNoise ?? 0) * 100))%").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { current.scanNoise ?? 0 }, set: { current.scanNoise = $0 }), in: 0...1, step: 0.05)
                Text("0%: quét mượt · 100%: vệt màu gợn mạnh")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Tên mẫu", text: $current.name).textFieldStyle(.roundedBorder)
            HStack {
                Button(action: save) { Label("Lưu mẫu", systemImage: "heart").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                Button {
                    do {
                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        document = PresetDocument(data: try encoder.encode(current))
                        export = true
                    } catch { message = error.localizedDescription }
                } label: { Label("Xuất JSON", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mẫu đã lưu").font(.title3.bold())
            if saved.isEmpty { Text("Chưa có mẫu").foregroundStyle(.secondary) }
            ForEach(saved) { item in
                HStack {
                    Button { current = item } label: {
                        HStack {
                            RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [item.first.color, item.second.color], startPoint: .leading, endPoint: .trailing)).frame(width: 46, height: 46)
                            VStack(alignment: .leading) {
                                Text(item.name).foregroundStyle(.primary)
                                Text(item.effect.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }.buttonStyle(.plain)
                    Button(role: .destructive) {
                        saved.removeAll { $0.id == item.id }; persist()
                    } label: { Image(systemName: "trash").padding(10) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Xóa mẫu")
                }
                Divider()
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}


// Independent Unity shader template and round-trip preset format.
enum ShaderIOError: LocalizedError {
    case tooLarge, unsupported, invalid, binaryBundle
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "Tệp vượt quá 32 MB."
        case .binaryBundle: return "Đây là UnityFS AssetBundle đã biên dịch. Ứng dụng chỉ chỉnh thông số shader mẫu độc lập và JSON, không sửa gói nhị phân."
        case .unsupported: return "Tệp không chứa mẫu Blu hoặc thuộc tính Color trong mã nguồn ShaderLab được hỗ trợ."
        case .invalid: return "Tệp không hợp lệ hoặc cấu hình màu không đúng định dạng."
        }
    }
}

enum BluShaderIO {
    static let marker = "// BluColorMakerPresetV2:"
    static func sanitize(_ p: Preset) throws -> Preset {
        let values = [p.first.r, p.first.g, p.first.b, p.second.r, p.second.g, p.second.b, p.duration, p.intensity, p.scanNoise ?? 0]
        guard values.allSatisfy({ $0.isFinite }),
              values.prefix(6).allSatisfy({ (0.0...1.0).contains($0) }),
              (0.5...10.0).contains(p.duration),
              (0.0...1.0).contains(p.intensity), (0.0...1.0).contains(p.scanNoise ?? 0) else { throw ShaderIOError.invalid }
        let rim = p.rim ?? .cyan
        guard [rim.r, rim.g, rim.b, p.rimStrength ?? 0.6, p.scanStrength ?? 1].allSatisfy({
            $0.isFinite && (0.0...1.0).contains($0)
        }) else { throw ShaderIOError.invalid }
        var clean = p
        clean.name = String(p.name.prefix(80))
        return clean
    }
    static func read(_ data: Data, ext: String) throws -> Preset {
        if data.starts(with: Data("UnityFS".utf8)) || data.starts(with: Data("UnityRaw".utf8)) || data.starts(with: Data("UnityWeb".utf8)) { throw ShaderIOError.binaryBundle }
        if ext == "json" {
            return try sanitize(JSONDecoder().decode(Preset.self, from: data))
        }
        guard ext == "shader", let source = String(data: data, encoding: .utf8),
              let line = source.split(whereSeparator: \.isNewline).first,
              line.hasPrefix(marker),
              let presetData = Data(base64Encoded: String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)) else {
            throw ShaderIOError.unsupported
        }
        // Never carry imported shader code into the exported program.
        return try sanitize(JSONDecoder().decode(Preset.self, from: presetData))
    }
    static func readReference(_ data: Data, ext: String, fallback: Preset) throws -> (preset: Preset, detail: String) {
        if ext == "json" { return (try read(data, ext: ext), "Preset JSON có thể chỉnh sửa") }
        guard ext == "shader", let source = String(data: data, encoding: .utf8) else { throw ShaderIOError.unsupported }
        if source.hasPrefix(marker) {
            return (try read(data, ext: ext), "Mẫu Blu có thể chỉnh sửa")
        }
        // Extract only ordinary ShaderLab default Color values, never imported code.
        let pattern = #"(?m)^\s*(?:\[[^\]\r\n]{1,80}\]\s*)*([A-Za-z_][A-Za-z_0-9]*)\s*\(\s*"[^"\r\n]*"\s*,\s*Color\s*\)\s*=\s*\(\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*,\s*([-+0-9.eE]+)\s*\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        var colors: [(String, RGB)] = []
        for m in matches.prefix(128) {
            let values = (2...4).compactMap { Double(ns.substring(with: m.range(at: $0))) }
            guard values.count == 3, values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { continue }
            colors.append((ns.substring(with: m.range(at: 1)), RGB(values[0], values[1], values[2])))
        }
        guard !colors.isEmpty else { throw ShaderIOError.unsupported }
        var p = fallback
        let main = colors.first(where: { ["_ColorA", "_BaseColor", "_Color", "_TintColor"].contains($0.0) }) ?? colors[0]
        let other = colors.first(where: { ["_ColorB", "_ScanColor", "_RimColor"].contains($0.0) && $0.0 != main.0 }) ?? colors.first(where: { $0.0 != main.0 })
        p.first = main.1
        p.second = other?.1 ?? main.1
        return (try sanitize(p), "Đã đọc \(colors.count) giá trị Color. Xuất shader Blu mới, không sao chép mã nguồn gốc.")
    }
    static func render(_ input: Preset) throws -> Data {
        let p = try sanitize(input)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let meta = try encoder.encode(p).base64EncodedString()
        let mode = Effect.allCases.firstIndex(of: p.effect) ?? 0
        func number(_ n: Double) -> String {
            String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), n)
        }
        func color(_ c: RGB) -> String { "(\(number(c.r)),\(number(c.g)),\(number(c.b)),1)" }
        let source = """
        \(marker)\(meta)
        Shader "BluColorMaker/Neon"
        {
            Properties
            {
                _ColorA ("Main Color", Color) = \(color(p.first))
                _ColorB ("Secondary Color", Color) = \(color(p.second))
                _DecorRim ("Decorative Rim Color", Color) = \(color(p.rim ?? .cyan))
                _DecorRimStrength ("Rim Strength", Range(0,1)) = \(number(p.rimStrength ?? 0.6))
                _DecorScanStrength ("Scan Strength", Range(0,1)) = \(number(p.scanStrength ?? 1))
                _Cycle ("Cycle Seconds", Float) = \(number(p.duration))
                _Glow ("Glow", Range(0,6)) = \(number(p.intensity * 6))
                _Effect ("Effect Mode", Float) = \(mode)
                _ScanNoise ("Scan Noise", Range(0,1)) = \(number(p.scanNoise ?? 0))
            }
            SubShader
            {
                Tags { "Queue"="Geometry" "RenderType"="Opaque" }
                Pass
                {
                    ZTest LEqual
                    ZWrite On
                    Cull Back
                    CGPROGRAM
                    #pragma vertex vert
                    #pragma fragment frag
                    #include "UnityCG.cginc"
                    float4 _ColorA, _ColorB, _DecorRim;
                    float _Cycle, _Glow, _Effect, _ScanNoise, _DecorRimStrength, _DecorScanStrength;
                    struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; float3 normal : NORMAL; };
                    struct v2f { float4 vertex : SV_POSITION; float2 uv : TEXCOORD0; float3 worldNormal : TEXCOORD1; float3 worldPos : TEXCOORD2; };
                    v2f vert(appdata v)
                    {
                        v2f o;
                        o.vertex = UnityObjectToClipPos(v.vertex);
                        o.uv = v.uv;
                        o.worldNormal = UnityObjectToWorldNormal(v.normal);
                        o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                        return o;
                    }
                    float3 hsv(float h)
                    {
                        return saturate(abs(frac(h + float3(0, 0.666667, 0.333333)) * 6 - 3) - 1);
                    }
                    float4 frag(v2f i) : SV_Target
                    {
                        float phase = frac(_Time.y / max(0.5, _Cycle));
                        float wave = 0.5 - 0.5 * cos(phase * 6.2831853);
                        float n = 0.62 * sin((i.uv.x * 7 + i.uv.y * 3 + phase) * 6.2831853)
                            + 0.38 * sin((i.uv.x * 13 - i.uv.y * 9 - phase * 2) * 6.2831853);
                        float warped = i.uv.y + saturate(_ScanNoise) * 0.25 * n;
                        float3 col = _ColorA.rgb;
                        float strength = 1.0;
                        if (_Effect > 3.5) {
                            col = hsv(phase + warped * 0.3);
                        } else if (_Effect > 2.5) {
                            strength = 0.35 + 0.65 * wave;
                        } else if (_Effect > 1.5) {
                            float scan = (0.5 + 0.5 * cos((warped - phase) * 6.2831853)) * saturate(_DecorScanStrength);
                            col = lerp(_ColorA.rgb, _ColorB.rgb, scan);
                            col = lerp(col, float3(1,1,1), pow(scan, 18) * 0.85);
                        } else if (_Effect > 0.5) {
                            col = lerp(_ColorA.rgb, _ColorB.rgb, wave);
                        }
                        float3 viewDir = normalize(_WorldSpaceCameraPos.xyz - i.worldPos);
                        float rim = pow(1 - saturate(dot(normalize(i.worldNormal), viewDir)), 3);
                        col = lerp(col, _DecorRim.rgb, rim * saturate(_DecorRimStrength));
                        return float4(col * strength * (1 + _Glow), 1);
                    }
                    ENDCG
                }
            }
            FallBack Off
        }
        """
        return Data(source.utf8)
    }
}

struct ShaderExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShaderExportPicker: UIViewControllerRepresentable {
    let url: URL
    let finished: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finished: (Bool) -> Void
        init(_ finished: @escaping (Bool) -> Void) { self.finished = finished }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finished(!urls.isEmpty)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finished(false) }
    }
}


// Read-only UnityFS reference header. No decompression or binary writes.
enum BluReferenceHeader {
    static func inspect(_ data: Data) throws -> String? {
        let b = Array(data.prefix(4096))
        guard b.starts(with: Array("UnityFS".utf8)) else { return nil }
        var pos = 0
        func text() throws -> String {
            guard pos < b.count, let end = b[pos...].firstIndex(of: 0),
                  end - pos <= 128,
                  let value = String(bytes: b[pos..<end], encoding: .utf8) else { throw ShaderIOError.invalid }
            pos = end + 1
            return value
        }
        func integer(_ count: Int) throws -> UInt64 {
            guard pos + count <= b.count else { throw ShaderIOError.invalid }
            var n: UInt64 = 0
            for x in b[pos..<(pos + count)] { n = (n << 8) | UInt64(x) }
            pos += count
            return n
        }
        guard try text() == "UnityFS" else { throw ShaderIOError.invalid }
        let version = try integer(4)
        _ = try text()
        let engine = try text()
        let declared = try integer(8)
        guard version >= 6 && version <= 9, declared == UInt64(data.count) else {
            throw ShaderIOError.invalid
        }
        return "UnityFS v\(version) · Unity \(engine) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
    }
}


enum SourcePickerMode: String, Identifiable {
    case file, folder
    var id: String { rawValue }
}

struct NativeSourcePicker: UIViewControllerRepresentable {
    let mode: SourcePickerMode
    let finished: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller: UIDocumentPickerViewController
        if mode == .folder {
            controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        } else {
            controller = UIDocumentPickerViewController(forOpeningContentTypes: [.item, .data, .content], asCopy: true)
        }
        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let finished: (URL?) -> Void
        init(_ finished: @escaping (URL?) -> Void) { self.finished = finished }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finished(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finished(nil) }
    }
}
