#!/usr/bin/env python3
"""Remove the redeem-code and UDID controls from SettingsView only.

This changes the visible settings UI; it does not bypass or modify
LicenseManager authentication, entitlement, or server-side checks.
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

source.write_text(data, encoding="utf-8")
print(f"Settings UI patched successfully: {source} ({len(data)} characters)")
