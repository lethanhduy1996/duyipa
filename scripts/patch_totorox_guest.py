#!/usr/bin/env python3
"""Patch Totorox for optional local guest access and a simplified Settings UI.

Does not alter LicenseManager, API authentication, server license, or UDID checks.
Remote operations continue to require valid server-side authorization.
"""
from pathlib import Path

source = Path("Totorox/views/SettingsView.swift")
data = source.read_text(encoding="utf-8")


def remove_span(start: str, end: str, label: str) -> None:
    global data
    if data.count(start) != 1:
        raise RuntimeError(f"{label}: expected one start marker, found {data.count(start)}")
    i = data.index(start)
    j = data.find(end, i + len(start))
    if j < 0:
        raise RuntimeError(f"{label}: end marker missing")
    data = data[:i] + data[j:]
    print(f"Removed {label}")


remove_span(
    "                    if !license.isDeviceVerified {\n",
    "                    // Language Selection\n",
    "standalone device verification card",
)
remove_span(
    "            .sheet(isPresented: $showRedeemSheet) {\n",
    '            .alert(language.text("settings.clear_cache_confirm_title")',
    "redeem-code sheet",
)
remove_span(
    "            .alert(item: settingsUDIDAlertBinding) { alertItem in\n",
    "        }\n    }\n\n    private var settingsUDIDAlertBinding",
    "UDID alert",
)
remove_span(
    "    private var settingsUDIDAlertBinding:",
    "    private var licenseAndDeviceCard:",
    "UDID alert binding",
)
remove_span(
    "            Divider()\n\n            // Redeem Code Button\n",
    "            if license.hasActivePackage {\n",
    "redeem-code button",
)
remove_span(
    "                if license.isDeviceVerified {\n",
    "                Button {\n                    Task { await license.refresh() }\n",
    "device UDID panel",
)
remove_span(
    "    private func copyBadgeButton(",
    "    private func settingsRow(",
    "UDID-only helpers",
)

for marker in (
    "    @State private var showRedeemSheet = false\n",
    "    @State private var didCopyUDID = false\n",
    "                .animation(.easeInOut(duration: 0.25), value: license.isDeviceVerified)\n",
):
    if data.count(marker) != 1:
        raise RuntimeError(f"Missing or duplicated state/animation: {marker!r}")
    data = data.replace(marker, "")

data = data.replace(
    "                    // License & Device UDID Card",
    "                    // Account & Package Card",
)

absent = (
    "DeviceVerificationCard(compact: false)",
    "showRedeemSheet",
    "settingsUDIDAlertBinding",
    "account.redeem_button",
    "account.redeem_more_button",
    "udid.verify.not_verified_short",
    "didCopyUDID",
    "copyBadgeButton",
    "settings.udid_verified_profile",
)
present = ("account.username_label", "account.logout_button", "settings.section_language")
for token in absent:
    if token in data:
        raise RuntimeError(f"Unexpected removed UI token remains: {token}")
for token in present:
    if token not in data:
        raise RuntimeError(f"Expected original UI token missing: {token}")

if data.count("                    licenseAndDeviceCard\n") != 1:
    raise RuntimeError("Expected account card anchor missing")
data = data.replace(
    "                    licenseAndDeviceCard\n",
    "                    if license.isAuthenticated {\n"
    "                        licenseAndDeviceCard\n"
    "                    }\n",
)

source.write_text(data, encoding="utf-8")
print(f"Settings UI patched successfully: {source} ({len(data)} characters)")


# ContentView: open the original navigation UI without forcing a sign-in screen.
# This does not synthesize a token or grant a server entitlement.
content_path = Path("Totorox/ContentView.swift")
content = content_path.read_text(encoding="utf-8")


def replace_unique(old: str, new: str, label: str) -> None:
    global content
    count = content.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one marker, got {count}")
    content = content.replace(old, new)


def remove_content_span(start: str, end: str, label: str) -> None:
    global content
    if content.count(start) != 1:
        raise RuntimeError(f"{label}: expected one start marker")
    i = content.index(start)
    j = content.find(end, i + len(start))
    if j < 0:
        raise RuntimeError(f"{label}: missing end marker")
    content = content[:i] + content[j:]
    print(f"Removed {label}")


remove_content_span(
    "    var body: some View {\n",
    "    private var mainAppBody: some View {\n",
    "mandatory login/registration screen",
)
replace_unique(
    "    private var mainAppBody: some View {\n",
    "    var body: some View {\n"
    "        mainAppBody\n"
    "            .background(TotoroxTheme.pageBackground)\n"
    "    }\n\n"
    "    private var mainAppBody: some View {\n",
    "root ContentView",
)
remove_content_span(
    "            if !license.hasActivePackage {\n",
    "            ZStack {\n",
    "root redeem and UDID banners",
)
replace_unique(
    "            ZStack {\n",
    "            if !license.isAuthenticated {\n"
    "                HStack(spacing: 8) {\n"
    '                    Image(systemName: "info.circle.fill")\n'
    "                        .foregroundStyle(Color.orange)\n"
    '                    Text("Chế độ khách: chức năng cần máy chủ vẫn yêu cầu tài khoản được cấp quyền.")\n'
    "                        .font(.system(size: 12))\n"
    "                        .foregroundStyle(TotoroxTheme.textSecondary)\n"
    "                    Spacer(minLength: 0)\n"
    "                }\n"
    "                .padding(.horizontal, 16)\n"
    "                .padding(.vertical, 8)\n"
    "            }\n\n"
    "            ZStack {\n",
    "guest status notice",
)
remove_content_span(
    "        .sheet(isPresented: $showRedeemSheet) {\n",
    "        .onAppear {\n",
    "unused redeem/logout/UDID modals",
)
remove_content_span(
    "    private var rootUDIDAlertBinding:",
    "\n}",
    "unused root UDID alert binding",
)
for line in (
    "    @State private var showRedeemSheet: Bool = false\n",
    "    @State private var showLogoutConfirm: Bool = false\n",
    "        .animation(.easeInOut(duration: 0.25), value: license.hasActivePackage)\n",
    "        .animation(.easeInOut(duration: 0.25), value: license.isDeviceVerified)\n",
):
    replace_unique(line, "", "unused root UI state")
for token in ("ActivationView()", "DeviceVerificationCard(compact: true)",
              "RedeemCodeSheet()", "rootUDIDAlertBinding", "AccountStatusBar(",
              "showRedeemSheet", "showLogoutConfirm"):
    if token in content:
        raise RuntimeError(f"Unexpected UI token remains in ContentView: {token}")
for token in ("OverwriteFileView()", "FolderExplorerView()", "PatchConverterView()",
              "MergeFileView()", "SettingsView()", "TotoroxTabBar"):
    if token not in content:
        raise RuntimeError(f"Main original feature missing: {token}")

content_path.write_text(content, encoding="utf-8")
print(f"Guest root UI patched: {content_path} ({len(content)} characters)")
