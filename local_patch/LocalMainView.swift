import SwiftUI

/// Standalone, offline entry point. No activation screen or Totorox backend calls.
struct LocalMainView: View {
    @State private var tab: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.fill")
                    .foregroundColor(.mint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Totorox Local")
                        .font(.headline)
                    Text("Không tài khoản · Không key · Không thu thập UDID")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            TabView(selection: $tab) {
                LocalWorkspaceView()
                    .tabItem { Label("Tệp", systemImage: "folder.fill") }
                    .tag(0)

                PatchConverterView()
                    .tabItem { Label("Chuyển đổi", systemImage: "arrow.triangle.2.circlepath") }
                    .tag(1)

                MergeFileView()
                    .tabItem { Label("Gộp file", systemImage: "square.stack.3d.up.fill") }
                    .tag(2)
            }
        }
        .background(TotoroxTheme.pageBackground)
        .tint(TotoroxTheme.mintAccent)
    }
}
