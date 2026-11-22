#!/usr/bin/env python3
"""Apply a reproducible offline-UI patch to a local copy of VannHoc/Totorox.

This patch does NOT defeat the original backend's access controls.
It uses only local file-management / conversion / merging functionality.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import sys

HERE = Path(__file__).resolve().parent
APP_DECLARATION = '@main\nstruct TotoroxApp: App {'
APPSTATE_DECLARATION = 'class AppState: ObservableObject {'

LOCAL_ROOT = '''@main
struct TotoroxApp: App {
    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.systemDefault.rawValue

    init() {
        setupLogCapture()
        log("app: Totorox Local standalone startup")
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageCode) ?? .systemDefault
    }

    var body: some Scene {
        WindowGroup {
            LocalMainView()
                .environment(\.appLanguage, language)
                .environment(\.locale, language.locale)
                .preferredColorScheme(themeManager.mode.colorScheme)
        }
    }
}

'''


def replace_exact(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    found = text.count(old)
    if found != count:
        raise RuntimeError(f'{label}: expected {count} matches, found {found}; source may have changed')
    return text.replace(old, new)


def apply(root: Path) -> None:
    root = root.resolve()
    project_file = root / 'project.yml'
    app_file = root / 'Totorox' / 'App.swift'
    info_file = root / 'Totorox' / 'Info.plist'
    for file in (project_file, app_file, info_file):
        if not file.is_file():
            raise RuntimeError(f'Missing expected source file: {file}')

    original_app = app_file.read_text(encoding='utf-8')
    if APP_DECLARATION not in original_app or APPSTATE_DECLARATION not in original_app:
        raise RuntimeError('App.swift entry point no longer matches expected upstream structure')
    a = original_app.index(APP_DECLARATION)
    b = original_app.index(APPSTATE_DECLARATION)
    if a >= b:
        raise RuntimeError('App.swift entry point position is invalid')
    patched_app = original_app[:a] + LOCAL_ROOT + original_app[b:]

    project = project_file.read_text(encoding='utf-8')
    project = replace_exact(project,
        'PRODUCT_BUNDLE_IDENTIFIER: com.apple.mobile.MobileHouseArrest',
        'PRODUCT_BUNDLE_IDENTIFIER: com.totorox.local', 'main bundle id')
    project = replace_exact(project,
        'PRODUCT_BUNDLE_IDENTIFIER: com.apple.mobile.TotoroxTests',
        'PRODUCT_BUNDLE_IDENTIFIER: com.totorox.local.Tests', 'test bundle id')
    project = replace_exact(project,
        'CODE_SIGN_ENTITLEMENTS: Totorox/Totorox.entitlements',
        'CODE_SIGN_ENTITLEMENTS: Totorox/Totorox-Local.entitlements', 'entitlements path')
    project = replace_exact(project,
        'bundleIdPrefix: com.apple.mobile',
        'bundleIdPrefix: com.totorox', 'bundle id prefix')
    project = replace_exact(project,
        'INFOPLIST_KEY_CFBundleDisplayName: Totorox',
        'INFOPLIST_KEY_CFBundleDisplayName: Totorox Local', 'Xcode generated display name')

    info = info_file.read_text(encoding='utf-8')
    info = replace_exact(info,
        '<key>CFBundleIdentifier</key>\n    <string>com.apple.mobile.MobileHouseArrest</string>',
        '<key>CFBundleIdentifier</key>\n    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>',
        'Info.plist CFBundleIdentifier')
    info = replace_exact(info,
        '<key>CFBundleDisplayName</key>\n    <string>Totorox</string>',
        '<key>CFBundleDisplayName</key>\n    <string>Totorox Local</string>',
        'Info.plist display name')

    # Validate changes before altering the checkout.
    if 'LicenseManager.shared.refresh()' in patched_app[:patched_app.index(APPSTATE_DECLARATION)]:
        raise RuntimeError('Unexpected license refresh in the new entry point')
    if 'BootstrapManager.shared' in patched_app[:patched_app.index(APPSTATE_DECLARATION)]:
        raise RuntimeError('Unexpected remote bootstrap in the new entry point')
    if 'LocalMainView()' not in patched_app:
        raise RuntimeError('Offline entry point missing')

    (root / 'Totorox' / 'views').mkdir(parents=True, exist_ok=True)
    app_file.write_text(patched_app, encoding='utf-8')
    project_file.write_text(project, encoding='utf-8')
    info_file.write_text(info, encoding='utf-8')
    for name in ('LocalMainView.swift', 'LocalWorkspaceView.swift'):
        shutil.copyfile(HERE / name, root / 'Totorox' / 'views' / name)
    shutil.copyfile(HERE / 'Totorox-Local.entitlements', root / 'Totorox' / 'Totorox-Local.entitlements')
    print('PATCH OK: Totorox Local UI, offline file features, separate bundle id and minimal entitlements')
    print('NOTE: upstream authentication/backend code remains present but is not invoked by the local UI.')
    print('NOTE: Xcode build and runtime testing remain necessary.')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repository', type=Path, help='Path to a fresh checkout of VannHoc/Totorox')
    args = parser.parse_args()
    try:
        apply(args.repository)
    except (OSError, RuntimeError) as e:
        print(f'PATCH FAILED: {e}', file=sys.stderr)
        return 1
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
