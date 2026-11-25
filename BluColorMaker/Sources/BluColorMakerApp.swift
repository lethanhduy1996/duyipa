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
    var scanNoise: Double? = 0.15
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
                    let scan = 0.5 + 0.5 * cos((warped - phase) * 2 * .pi)
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
    @State private var importing = false
    @State private var sourceName: String? = nil
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
                    Text("Hỗ trợ shader mẫu Blu và cấu hình JSON cho dự án Unity riêng. Không đọc AssetBundle nhị phân hoặc .3105.")
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
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 1024 * 1024 else { throw ShaderIOError.tooLarge }
                let bytes = try Data(contentsOf: url)
                guard bytes.count <= 1024 * 1024 else { throw ShaderIOError.tooLarge }
                let loaded = try BluShaderIO.read(bytes, ext: url.pathExtension.lowercased())
                current = loaded
                sourceName = url.lastPathComponent
            } catch { message = error.localizedDescription }
        }
        .sheet(item: $shaderExport) { item in
            ShaderExportPicker(url: item.url) { success in
                shaderExport = nil
                if success { message = "Đã xuất mã nguồn .shader" }
            }
        }
        .alert("Blu Color Maker", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
    private var fileControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tệp nguồn", systemImage: "folder").font(.headline)
            Text(sourceName ?? "Chưa nhập tệp")
                .font(.subheadline).foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Button { importing = true } label: {
                    Label("Nhập tệp", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent)
                Button {
                    sourceName = "BluNeon.shader (mẫu)"
                } label: {
                    Text("Dùng mẫu").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered)
            }
            Text("Nhận .shader mẫu Blu hoặc JSON; nhận diện UnityFS nhưng không chỉnh gói nhị phân.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
         .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private var shaderActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                do {
                    let data = try BluShaderIO.render(current)
                    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let url = dir.appendingPathComponent("BluNeon.shader")
                    try data.write(to: url, options: .atomic)
                    shaderExport = ShaderExportItem(url: url)
                } catch { message = error.localizedDescription }
            } label: {
                Label("Áp dụng & xuất shader", systemImage: "square.and.arrow.up")
                    .font(.headline).frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent)
            Text("Xuất mã nguồn mới cho Unity; giữ nguyên tệp đã nhập.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
         .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
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
        case .tooLarge: return "Tệp vượt quá 1 MB."
        case .binaryBundle: return "Đây là UnityFS AssetBundle đã biên dịch. Ứng dụng chỉ chỉnh thông số shader mẫu độc lập và JSON, không sửa gói nhị phân."
        case .unsupported: return "Chỉ hỗ trợ preset JSON và shader mẫu Blu do ứng dụng xuất. Không hỗ trợ gói shader nhị phân."
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
                    float4 _ColorA, _ColorB;
                    float _Cycle, _Glow, _Effect, _ScanNoise;
                    struct appdata { float4 vertex : POSITION; float2 uv : TEXCOORD0; };
                    struct v2f { float4 vertex : SV_POSITION; float2 uv : TEXCOORD0; };
                    v2f vert(appdata v)
                    {
                        v2f o;
                        o.vertex = UnityObjectToClipPos(v.vertex);
                        o.uv = v.uv;
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
                            float scan = 0.5 + 0.5 * cos((warped - phase) * 6.2831853);
                            col = lerp(_ColorA.rgb, _ColorB.rgb, scan);
                            col = lerp(col, float3(1,1,1), pow(scan, 18) * 0.85);
                        } else if (_Effect > 0.5) {
                            col = lerp(_ColorA.rgb, _ColorB.rgb, wave);
                        }
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
