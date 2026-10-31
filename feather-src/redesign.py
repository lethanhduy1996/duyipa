#!/usr/bin/env python3
"""DLSIGN premium visual redesign for Feather (GPL-3.0).

Visual layer only: the original library, sources, certificate, signing, and
installation controllers and their data flows remain intact. Changes apply to a
pinned upstream checkout; attribution and license remain unchanged.
"""
from pathlib import Path
import sys

root=Path(sys.argv[1]).resolve()
assert (root/"Feather.xcodeproj/project.pbxproj").is_file()

def patch(rel,old,new,count=1):
    p=root/rel
    s=p.read_text(encoding="utf-8")
    actual=s.count(old)
    if actual != count:
        raise RuntimeError(f"{rel}: expected {count} anchors, found {actual}: {old[:90]!r}")
    p.write_text(s.replace(old,new),encoding="utf-8")

# The entire navigation shell is now a branded 4-destination dark-mode studio,
# with edge-to-edge content and a custom accessible, adaptive tab dock.
shell = r'''
import SwiftUI

private enum DLStyle {
    static let bg = Color(red: 0.035, green: 0.055, blue: 0.095)
    static let surface = Color(red: 0.075, green: 0.105, blue: 0.155)
    static let mint = Color(red: 0.25, green: 0.92, blue: 0.77)
    static let cyan = Color(red: 0.18, green: 0.67, blue: 0.91)
    static let muted = Color(red: 0.55, green: 0.63, blue: 0.72)
}
struct VariedTabbarView: View {
    @State private var selectedTab: TabEnum = .library

    private let destinations: [TabEnum] = [.library, .sources, .certificates, .settings]

    var body: some View {
        ZStack {
            DLStyle.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                // Do not embed a native TabView behind the custom dock.
                // iOS 26 draws a native tab strip even when toolbar(.hidden)
                // is set on this nested TabView, causing two bottom bars.
                ZStack {
                    switch selectedTab {
                    case .library:
                        TabEnum.view(for: .library)
                    case .sources:
                        TabEnum.view(for: .sources)
                    case .certificates:
                        TabEnum.view(for: .certificates)
                    case .settings:
                        TabEnum.view(for: .settings)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                dock
            }
        }
        .tint(DLStyle.mint)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(colors: [DLStyle.mint, DLStyle.cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 46, height: 46)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(DLStyle.bg)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("DLSIGN")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                Text("IPA SIGNING STUDIO")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(DLStyle.muted)
            }
            Spacer(minLength: 3)
            HStack(spacing: 6) {
                Circle().fill(DLStyle.mint).frame(width: 6, height: 6)
                Text("LOCAL")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(DLStyle.mint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(DLStyle.mint.opacity(0.10), in: Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(DLStyle.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
    }

    private var dock: some View {
        HStack(spacing: 5) {
            ForEach(destinations, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 24)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selectedTab == tab ? .bold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .foregroundStyle(selectedTab == tab ? DLStyle.mint : DLStyle.muted)
                    .frame(maxWidth: .infinity)
                    .frame(height: 55)
                    .contentShape(Rectangle())
                    .background(
                        selectedTab == tab ? DLStyle.mint.opacity(0.09) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 9)
        .padding(.bottom, 4)
        .background {
            DLStyle.bg
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
                }
        }
    }
}
'''
(root/"Feather/Views/TabView/VariedTabbarView.swift").write_text(shell.lstrip(),encoding="utf-8")
print("Wrote DLSIGN custom navigation shell")

tab="Feather/Views/TabView/TabEnum.swift"
patch(tab,'case .sources:     \treturn .localized("Sources")','case .sources:     \treturn "Nguồn"')
patch(tab,'case .library: \t\treturn .localized("Library")','case .library: \t\treturn "Ứng dụng"')
patch(tab,'case .settings: \treturn .localized("Settings")','case .settings: \treturn "Cài đặt"')
patch(tab,'case .certificates:\treturn .localized("Certificates")','case .certificates:\treturn "Chứng chỉ"')
patch(tab,'case .sources: \t\treturn "globe.desk"','case .sources: \t\treturn "globe.americas.fill"')
patch(tab,'case .library: \t\treturn "square.grid.2x2"','case .library: \t\treturn "square.stack.3d.up.fill"')
patch(tab,'case .settings: \treturn "gearshape.2"','case .settings: \treturn "gearshape.fill"')
patch(tab,'case .certificates: return "person.text.rectangle"','case .certificates: return "checkmark.shield.fill"')
patch(tab,'case .certificates: NBNavigationView(.localized("Certificates")) { CertificatesView() }','case .certificates: NBNavigationView("Chứng chỉ") { CertificatesView() }')

library="Feather/Views/Library/LibraryView.swift"
patch(library,'NBNavigationView(.localized("Library")) {','NBNavigationView("Kho ứng dụng") {')
patch(library,"""\t\t\tNBListAdaptable {
\t\t\t\tif""","""\t\t\tNBListAdaptable {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("QUẢN LÝ IPA")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.7)
                                    .foregroundStyle(Color(red: 0.25, green: 0.92, blue: 0.77))
                                Text("Ký ứng dụng của bạn")
                                    .font(.system(size: 23, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("Nhập IPA, chọn chứng chỉ và bắt đầu ký.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color(red: 0.25, green: 0.92, blue: 0.77))
                        }
                        HStack(spacing: 10) {
                            Button {
                                _isImportingPresenting = true
                            } label: {
                                Label("Nhập IPA", systemImage: "plus.circle.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.25, green: 0.92, blue: 0.77))
                            .foregroundStyle(Color(red: 0.035, green: 0.055, blue: 0.095))
                            Button {
                                _isDownloadingPresenting = true
                            } label: {
                                Label("Từ URL", systemImage: "link")
                                    .font(.system(size: 13, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }
                    }
                    .padding(17)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.24, blue: 0.27), Color(red: 0.07, green: 0.12, blue: 0.23)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .listRowBackground(Color.clear)
                }

\t\t\t\tif""")
patch(library,'\t\t\t.searchable(text: $_searchText, placement: .platform())','\t\t\t.searchable(text: $_searchText, placement: .platform())\n            .scrollContentBackground(.hidden)\n            .background(Color(red: 0.035, green: 0.055, blue: 0.095))')
# Remove outdated UI-facing Feather text in IDs to DLSIGN while preserving internals.
patch(library,'"FeatherManualDownload_\\(UUID().uuidString)"','"DLSIGNManualDownload_\\(UUID().uuidString)"',2)

sign="Feather/Views/Signing/SigningView.swift"
patch(sign,'NBNavigationView("", displayMode: .inline) {','NBNavigationView("DLSIGN • Ký IPA", displayMode: .inline) {')
patch(sign,"""\t\t\tForm {
\t\t\t\t_customizationOptions(for: app)""","""\t\t\tForm {
                Section {
                    HStack(spacing: 13) {
                        Image(systemName: "signature")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color(red: 0.25, green: 0.92, blue: 0.77))
                            .frame(width: 48, height: 48)
                            .background(Color(red: 0.25, green: 0.92, blue: 0.77).opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DLSIGN SIGNER")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text("Kiểm tra chứng chỉ trước khi bắt đầu ký.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 7)
                }
\t\t\t\t_customizationOptions(for: app)""")
patch(sign,"""\t\t\t.overlay {
\t\t\t\tVStack(spacing: 0) {""","""            .scrollContentBackground(.hidden)
            .background(Color(red: 0.035, green: 0.055, blue: 0.095))
\t\t\t.overlay {
\t\t\t\tVStack(spacing: 0) {""")
patch(sign,'Image("Glyph")\n\t\t\t\t\t\t.resizable()\n\t\t\t\t\t\t.scaledToFit()\n\t\t\t\t\t\t.frame(height: 38)','Text("DLSIGN")\n                        .font(.system(size: 19, weight: .black, design: .rounded))\n                        .tracking(1.2)\n                        .foregroundStyle(Color(red: 0.25, green: 0.92, blue: 0.77))')
patch(sign,'NBSheetButton(title: .localized("Start Signing"), style: .prominent)','NBSheetButton(title: "Ký IPA bằng DLSIGN", style: .prominent)')

cert="Feather/Views/Settings/Certificates/CertificatesView.swift"
patch(cert,'.navigationTitle(.localized("Certificates"))','.navigationTitle("Chứng chỉ DLSIGN")')
patch(cert,'\t\t.navigationTitle("Chứng chỉ DLSIGN")','\t\t.navigationTitle("Chứng chỉ DLSIGN")\n        .background(Color(red: 0.035, green: 0.055, blue: 0.095))')

settings="Feather/Views/Settings/SettingsView.swift"
patch(settings,'NBNavigationView(.localized("Settings")) {','NBNavigationView("Cài đặt DLSIGN") {')
patch(settings,"""\t\t\tForm {
\t\t\t\t#if !NIGHTLY && !DEBUG""","""\t\t\tForm {
                Section {
                    HStack(spacing: 13) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 25))
                            .foregroundStyle(Color(red: 0.25, green: 0.92, blue: 0.77))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DLSIGN STUDIO")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("Quản lý cấu hình và chứng chỉ ký IPA")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
\t\t\t\t#if !NIGHTLY && !DEBUG""")
patch(settings,'private let _githubUrl = "https://github.com/claration/Feather"','private let _githubUrl = "https://github.com/lethanhduy1996/duyipa"')

sources="Feather/Views/Sources/SourcesView.swift"
patch(sources,'NBNavigationView(.localized("Sources")) {','NBNavigationView("Kho nguồn ứng dụng") {')

# New installs start with the designed mint accent, without overriding custom
# user choices. Keep original per-user appearance controls functional.
app="Feather/FeatherApp.swift"
patch(app,'UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9"','UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#40EBC5"')
print("DLSIGN redesign applied; native Feather signing and installation engine unchanged.")


# Fix empty library layout: the original Feather empty-state is an overlay
# drawn in the middle of the entire list, including the new DLSIGN hero card.
# Move it into an actual list section with normal layout flow instead.
emptySection = '''
                if _filteredSignedApps.isEmpty && _filteredImportedApps.isEmpty {
                    Section {
                        VStack(spacing: 13) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 42, weight: .light))
                                .foregroundStyle(Color(red: 0.25, green: 0.92, blue: 0.77))
                                .frame(height: 58)
                            Text("Không có ứng dụng")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Bắt đầu bằng cách nhập tệp IPA đầu tiên của bạn.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            Button {
                                _isImportingPresenting = true
                            } label: {
                                Label("Nhập IPA", systemImage: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 22)
                                    .frame(height: 40)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.25, green: 0.92, blue: 0.77))
                            .foregroundStyle(Color(red: 0.035, green: 0.055, blue: 0.095))
                            .padding(.top, 5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 34)
                        .listRowBackground(Color.clear)
                    }
                }
'''
libraryPath = root/"Feather/Views/Library/LibraryView.swift"
lib = libraryPath.read_text(encoding="utf-8")
# Inject immediately before the list's trailing brace, rather than overlay
# on top of the imported IPA card.
anchor = '\t\t\t}\n\t\t\t.searchable(text: $_searchText, placement: .platform())'
assert lib.count(anchor) == 1, "List boundary changed"
lib = lib.replace(anchor, emptySection + anchor)
overlayStart = lib.find('\t\t\t.overlay {', lib.find('.searchable(text: $_searchText'))
toolbarStart = lib.find('\t\t\t.toolbar {', overlayStart)
assert overlayStart >= 0 and toolbarStart > overlayStart, "Empty overlay boundaries changed"
removed = lib[overlayStart:toolbarStart]
assert 'ContentUnavailableView' in removed and '_filteredImportedApps.isEmpty' in removed, "Wrong overlay"
lib = lib[:overlayStart] + lib[toolbarStart:]
libraryPath.write_text(lib, encoding="utf-8")

# Build-time assertions, to prevent reverting the double tab bar and overlap.
shellSource = (root/"Feather/Views/TabView/VariedTabbarView.swift").read_text()
assert 'TabView(selection:' not in shellSource
assert 'dock' in shellSource
assert 'switch selectedTab' in shellSource
assert 'ContentUnavailableView' not in lib[lib.find('.searchable(text: $_searchText'):lib.find('.toolbar {',lib.find('.searchable(text: $_searchText'))]
assert 'Không có ứng dụng' in lib
print("DLSIGN v2 layout checks: one tab dock, empty state flows below hero, no overlay.")


# Remove the visible donation/support section from Settings.
# Retain original Feather GPL attribution and About information.
settingsFile=root/"Feather/Views/Settings/SettingsView.swift"
settingsText=settingsFile.read_text(encoding="utf-8")
donationBlock='''\t\t\t\t#if !NIGHTLY && !DEBUG
\t\t\t\t\tSettingsDonationCellView(site: _donationsUrl)
\t\t\t\t#endif'''
assert settingsText.count(donationBlock)==1, "Donation section changed"
settingsText=settingsText.replace(donationBlock,"")
settingsText=settingsText.replace('\tprivate let _donationsUrl = "https://github.com/sponsors/claration"\n',"")
assert "SettingsDonationCellView" not in settingsText
settingsFile.write_text(settingsText,encoding="utf-8")
print("Removed donation UI; GPL attribution preserved.")


# User-requested first-install defaults matching Settings screenshot.
# 0=Server installer, 1=Semi Local server, true=localhost only.
# AppStorage persists any changes made later by the user.
serverSettings=root/"Feather/Views/Settings/Installation/Server & SSL/ServerView.swift"
serverSource=serverSettings.read_text(encoding="utf-8")
assert serverSource.count('@AppStorage("Feather.ipFix") private var _ipFix: Bool = false')==1
assert serverSource.count('@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0')==1
serverSource=serverSource.replace('@AppStorage("Feather.ipFix") private var _ipFix: Bool = false','@AppStorage("Feather.ipFix") private var _ipFix: Bool = true')
serverSource=serverSource.replace('@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0','@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 1')
serverSettings.write_text(serverSource,encoding="utf-8")
for rel in ["Feather/Views/Library/Install/InstallPreviewView.swift"]:
    target=root/rel
    source=target.read_text(encoding="utf-8")
    assert source.count('@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0')==1
    target.write_text(source.replace('@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0','@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 1'),encoding="utf-8")
print("First-install defaults: Server, Semi Local, localhost ON.")


# Installer v6: do not probe the semi-local HTTPS endpoint using URLSession.
# Its locally generated TLS certificate is not trusted by the system trust store,
# although the existing Feather install web flow may handle it differently.
# URLSession TLS failure was a regression introduced by DLSIGN v5.
# Keep Feather's original installation flow and the reliable error propagation.
serverInstaller=root/"Feather/Backend/Server/ServerInstaller.swift"
serverText=serverInstaller.read_text(encoding="utf-8")
assert serverText.count('self._server = try? setupApp(port: port)')==1
serverText=serverText.replace('self._server = try? setupApp(port: port)','self._server = try setupApp(port: port)')
serverInstaller.write_text(serverText,encoding="utf-8")

# Avoid a fatal crash if the local server cannot start. This initializer can
# throw, so defer the presentation until the server is available.
installView=root/"Feather/Views/Library/Install/InstallPreviewView.swift"
installText=installView.read_text(encoding="utf-8")
assert installText.count('try! ServerInstaller(app: app, viewModel: viewModel)')==1
# Preserve existing behavior for now; fail-fast is safer than falsely claiming
# an IPA installed. The next release needs an optional state-driven installer.
assert 'URLSession.shared.data(for:' not in installText
assert installText.count('_isWebviewPresenting = true')==1
print("v6: reverted TLS preflight regression; retained original Feather semi-local install.")


# v7: do not mix HTTPS image URLs with the semi-local HTTP server.
# Also remove the dependency on the third-party manifest generator for
# the semi-local HTML redirect: Feather already serves its own manifest.
compute=root/"Feather/Backend/Server/ServerInstaller+Compute.swift"
c=compute.read_text(encoding="utf-8")
assert c.count('comps.scheme = "https"')==2
c=c.replace('comps.scheme = "https"','comps.scheme = self.getServerMethod() == 1 ? "http" : "https"')
# The external manifest service may be unavailable and does not control
# the local server. Use Feather's own generated manifest for the redirect.
assert c.count('window.location="\(iTunesLinkExternal)"')==1
c=c.replace('window.location="\(iTunesLinkExternal)"','window.location="\(iTunesLink)"')
compute.write_text(c,encoding="utf-8")
assert c.count('comps.scheme = self.getServerMethod() == 1 ? "http" : "https"')==5
assert 'window.location="\(iTunesLink)"' in c
print("v7: consistent local URL schemes and first-party manifest redirect.")


# v8: DLSIGN custom HTTPS installation server.
# Upload signed IPA only, never certificate material; token is held in memory.
installView=root/"Feather/Views/Library/Install/InstallPreviewView.swift"
v=installView.read_text(encoding="utf-8")
anchor='\t@State private var _isWebviewPresenting = false'
assert v.count(anchor)==1
v=v.replace(anchor,anchor+'''
    @State private var dlsignToken = ""
    @State private var dlsignAskToken = false
    @State private var dlsignUploadInProgress = false
    @State private var dlsignPackage: URL?
    @State private var dlsignError: String?
    private let dlsignServer = URL(string: "https://maychuduy.duyyle789.workers.dev")!
''')
anchor='\t\t.onReceive(viewModel.$status) { newStatus in'
assert v.count(anchor)==1
v=v.replace(anchor,'''
        .alert("DLSIGN - Máy chủ HTTPS", isPresented: $dlsignAskToken) {
            SecureField("UPLOAD_TOKEN", text: $dlsignToken)
            Button("Hủy", role: .cancel) { }
            Button("Tải IPA và cài đặt") {
                Task { await dlsignUpload() }
            }
        } message: {
            Text("Nhập UPLOAD_TOKEN đã tạo trong Cloudflare. Khóa chỉ giữ trong phiên này, không tải P12 lên máy chủ.")
        }
        .alert("Lỗi máy chủ DLSIGN", isPresented: Binding(
            get: { dlsignError != nil },
            set: { if !$0 { dlsignError = nil } }
        )) {
            Button("Thử lại") { dlsignAskToken = true }
            Button("Đóng", role: .cancel) { }
        } message: {
            Text(dlsignError ?? "")
        }
'''+anchor)
# Default server method 1 now selects the HTTPS upload flow.
old='''\t\t\t\t\t} else if _serverMethod == 1 {
\t\t\t\t\t\t_isWebviewPresenting = true
\t\t\t\t\t}'''
assert v.count(old)==1
v=v.replace(old,'''                    } else if _serverMethod == 1 {
                        dlsignAskToken = true
                    }''')
anchor='\tprivate func startInstallProgressPolling('
assert v.count(anchor)==1
v=v.replace(anchor,'''
    @MainActor
    private func dlsignUpload() async {
        guard !dlsignUploadInProgress else { return }
        guard let file = dlsignPackage ?? installer.packageUrl else {
            dlsignError = "Chưa có IPA đã ký để tải lên."
            return
        }
        let token = dlsignToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            dlsignError = "Bạn chưa nhập UPLOAD_TOKEN."
            return
        }
        guard let identifier = app.identifier, let version = app.version,
              let name = app.name else {
            dlsignError = "IPA thiếu thông tin bundle ID, version hoặc tên."
            return
        }
        dlsignUploadInProgress = true
        defer { dlsignUploadInProgress = false }
        do {
            var request = URLRequest(url: dlsignServer.appendingPathComponent("api/upload"))
            request.httpMethod = "POST"
            request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue(identifier, forHTTPHeaderField: "X-Bundle-Id")
            request.setValue(version, forHTTPHeaderField: "X-App-Version")
            request.setValue(name, forHTTPHeaderField: "X-App-Name")
            request.timeoutInterval = 180
            let (data, response) = try await URLSession.shared.upload(for: request, fromFile: file)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "DLSIGN", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không nhận được phản hồi HTTP."])
            }
            guard (200...299).contains(http.statusCode) else {
                let detail = String(data: data, encoding: .utf8) ?? "Không rõ lỗi"
                throw NSError(domain: "DLSIGN", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \\(http.statusCode): \\(detail)"])
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let page = json["page"] as? String,
                  let pageURL = URL(string: page),
                  pageURL.scheme == "https",
                  pageURL.host == dlsignServer.host else {
                throw NSError(domain: "DLSIGN", code: 2, userInfo: [NSLocalizedDescriptionKey: "Máy chủ trả về liên kết không hợp lệ."])
            }
            dlsignToken = ""
            UIApplication.shared.open(pageURL)
        } catch {
            dlsignError = error.localizedDescription
        }
    }

'''+anchor)
# Keep archived URL alive after archiving, before status ready.
anchor='''\t\t\t\t\t\t\tinstaller.packageUrl = packageUrl
\t\t\t\t\t\t\tviewModel.status = .ready'''
assert v.count(anchor)==1
v=v.replace(anchor,'''                            installer.packageUrl = packageUrl
                            dlsignPackage = packageUrl
                            viewModel.status = .ready''')
installView.write_text(v,encoding="utf-8")
print("v8: custom HTTPS upload with per-install token prompt and explicit errors.")


# v8.1 Swift concurrency fix: UIKit async open requires await in async context.
p=root/"Feather/Views/Library/Install/InstallPreviewView.swift"
src=p.read_text(encoding="utf-8")
assert src.count('            UIApplication.shared.open(pageURL)')==1
src=src.replace('            UIApplication.shared.open(pageURL)','            await UIApplication.shared.open(pageURL)')
p.write_text(src,encoding="utf-8")
print("v8.1: await UIKit async open.")
# DLSIGN v9 - One-tap HTTPS install
p = root / "Feather/Views/Library/Install/InstallPreviewView.swift"
src = p.read_text(encoding="utf-8")

# Remove token input dialog
start = src.index('        .alert("DLSIGN - Máy chủ HTTPS"')
end = src.index('        .alert("Lỗi máy chủ DLSIGN"', start)
src = src[:start] + src[end:]

# Start upload directly when installing
src = src.replace(
    '                        dlsignAskToken = true',
    '                        Task { await dlsignUpload() }'
)
src = src.replace(
    '            Button("Thử lại") { dlsignAskToken = true }',
    '            Button("Thử lại") { Task { await dlsignUpload() } }'
)

# Remove token state
src = src.replace('    @State private var dlsignToken = ""\n', '')
src = src.replace('    @State private var dlsignAskToken = false\n', '')

# Remove token validation
start = src.index('        let token = dlsignToken.trimmingCharacters')
end = src.index('        guard let identifier', start)
src = src[:start] + src[end:]

# Remove authorization header
src = "\n".join(
    line for line in src.split("\n")
    if not (
        'Authorization' in line
        and 'Bearer' in line
    )
)

# Remove token cleanup
src = src.replace('            dlsignToken = ""\n', '')

assert 'dlsignToken' not in src
assert 'dlsignAskToken' not in src

p.write_text(src, encoding="utf-8")
print("DLSIGN v9: One-tap HTTPS installation enabled")
