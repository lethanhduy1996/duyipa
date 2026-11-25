import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct BluColorMakerApp: App {
    var body: some Scene {
        WindowGroup { ContentView().preferredColorScheme(.dark) }
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
        String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
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
    private func frame(phase: Double) -> some View {
        let wave = (1 - cos(phase * 2 * .pi)) / 2
        let mixed = mix(preset.first, preset.second, wave)
        let main = preset.effect == .rainbow ? Color(hue: phase, saturation: 1, brightness: 1) :
            (preset.effect == .blend ? mixed : preset.first.color)
        let secondary = preset.effect == .rainbow ? Color(hue: (phase+0.36).truncatingRemainder(dividingBy: 1), saturation: 1, brightness: 1) : preset.second.color
        let position = preset.effect == .scan ? -0.8 + phase * 2.6 : 0.5
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
                    PreviewCharacter().fill(
                        LinearGradient(colors: [main, secondary, .white, main, secondary],
                                       startPoint: UnitPoint(x: 0.2, y: position-0.65),
                                       endPoint: UnitPoint(x: 0.8, y: position+0.65))
                    )
                }
                PreviewCharacter().stroke(Color.white.opacity(0.25 + preset.intensity * 0.5), lineWidth: 1.3)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(rgb.hex).font(.caption.monospaced()).foregroundStyle(.secondary)
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
        }
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

struct ContentView: View {
    @State private var current = Preset()
    @State private var saved: [Preset] = Self.loadPresets()
    @State private var export = false
    @State private var document = PresetDocument()
    @State private var message: String?
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
                    NeonPreview(preset: current)
                    controls
                    presets
                    Text("Ứng dụng thiết kế hiệu ứng màu độc lập. Tệp xuất là cấu hình JSON, không phải patch game hoặc .3105.")
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
        .alert("Blu Color Maker", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Thiết kế màu").font(.title3.bold())
            PalettePicker(title: "Màu chính", rgb: $current.first)
            PalettePicker(title: "Màu phụ", rgb: $current.second)
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
