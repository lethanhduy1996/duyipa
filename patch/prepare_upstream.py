#!/usr/bin/env python3
"""Integrate a pinned WQFiles checkout with patch module."""
from pathlib import Path
import sys
import shutil
overlay, root = map(Path, sys.argv[1:])
for fn in ("WQPatch.h", "WQPatch.m", "WQ3105Bridge.swift"):
    shutil.copy2(overlay / "patch" / fn, root / fn)

def sub_once(s, before, after):
    assert s.count(before) == 1, "unexpected upstream change: " + before[:80]
    return s.replace(before, after)

p = root / "main.m"
s = p.read_text()
changes = [
    ('#import "WQApps.h"', '#import "WQApps.h"\n#import "WQPatch.h"'),
    ('WQPrismVaultViewController *vault = [WQPrismVaultViewController new];',
     'WQPrismVaultViewController *vault = [WQPrismVaultViewController new];\n    WQPatchViewController *patch = [WQPatchViewController new];'),
    ('WQNavigationController *vaultNav = [[WQNavigationController alloc] initWithRootViewController:vault];',
     'WQNavigationController *vaultNav = [[WQNavigationController alloc] initWithRootViewController:vault];\n    WQNavigationController *patchNav = [[WQNavigationController alloc] initWithRootViewController:patch];'),
    ('image:[UIImage systemImageNamed:@"clock.arrow.circlepath"] tag:3];',
     'image:[UIImage systemImageNamed:@"clock.arrow.circlepath"] tag:3];\n    patchNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Patch" image:[UIImage systemImageNamed:@"square.stack.3d.up.fill"] tag:4];'),
    ('self.viewControllers = @[homeNav, appsNav, cleanNav, vaultNav];',
     'self.viewControllers = @[homeNav, appsNav, patchNav, cleanNav, vaultNav];'),
    ('return section == 0 ? (NSInteger)_locations.count + (wq_system_areas_reachable() ? 1 : 0) : 10;',
     'return section == 0 ? (NSInteger)_locations.count + (wq_system_areas_reachable() ? 1 : 0) : 11;'),
    ('@[@"Recent", @"clock"], @[@"Inspectors", @"curlybraces"]];',
     '@[@"Recent", @"clock"], @[@"Inspectors", @"curlybraces"], @[@"Patch", @"square.stack.3d.up"]];'),
    ('} else if (indexPath.row == 9) {\n        wq_open_inspectors_folder(self.navigationController);',
     '} else if (indexPath.row == 10) {\n        next = [WQPatchViewController new];\n    } else if (indexPath.row == 9) {\n        wq_open_inspectors_folder(self.navigationController);'),
]
for old, new in changes: s=sub_once(s, old, new)
# WQFiles uses one tab-bar index for each Prism quick action; update the two
# quick navigation targets when the Patch tab moves into the center position.
s=sub_once(s, 'case 1: [self openTab:2]; break;', 'case 1: [self openTab:3]; break;')
s=sub_once(s, 'case 3: [self openTab:3]; break;', 'case 3: [self openTab:4]; break;')
s=sub_once(s,
    'else if (index == 2) [self.navigationController pushViewController:[WQCacheCleanerViewController new] animated:YES];',
    'else if (index == 3) [self.navigationController pushViewController:[WQCacheCleanerViewController new] animated:YES];')
s=sub_once(s,
    'else if (index == 3) [self.navigationController pushViewController:[WQPrismVaultViewController new] animated:YES];',
    'else if (index == 4) [self.navigationController pushViewController:[WQPrismVaultViewController new] animated:YES];')
# Keep the selected center tab's bottom label as "Patch" (the page header stays "Đã cài").
# Upstream's tabDidAppear resets the third tab to "Clean"; the new Patch tab is
# now index 2, so retarget its hardcoded cleanup label to index 3.
s=sub_once(s, 'WQNavigationController *cleanNav = self.viewControllers[2];',
                'WQNavigationController *cleanNav = self.viewControllers[3];')
# Long-press a regular app-data file to create a .3105 patch at its exact path.
s = sub_once(s,
    """        // Inside an app's data container: let the Cache Cleaner empty this""",
    """        if (!current.isDir && current.isRegular && !current.isLink &&
            [WQPatchViewController canCreatePatchFromFilePath:current.path]) {
            [actions addObject:[UIAction actionWithTitle:@"Tạo patch từ tệp này"
                image:[UIImage systemImageNamed:@"doc.badge.plus"] identifier:nil
                handler:^(UIAction *__unused action) {
                    WQItem *selected=currentItem();
                    if (!selected || !weakSelf) return;
                    WQPatchViewController *patch=[[WQPatchViewController alloc]
                        initWithCreateFromFilePath:selected.path];
                    [weakSelf.navigationController pushViewController:patch animated:YES];
                }]];
        }
        // Inside an app's data container: let the Cache Cleaner empty this""")
# Disable automatic update checks and release banners in this custom Patch build.
# Upstream checks on both Prism/Classic startup; remove both invocations rather
# than relying on a persisted preference that might be enabled on reinstall.
# Other network features, such as user-initiated sharing, remain untouched.
assert s.count('    [self checkForUpdate];') == 2, 'upstream update-check call sites changed'
s = s.replace('    [self checkForUpdate];',
              '    // WQFiles Patch: automatic release checks and update banners disabled.')
# Keep the setting visible but explicitly off/disabled in both designs.
s = sub_once(s,
    ': indexPath.row == 4 ? ![defaults boolForKey:kWQUpdateCheckOffPref]',
    ': indexPath.row == 4 ? NO /* Patch build: updates disabled */')
s = sub_once(s,
    ': row == 5 ? ![defaults boolForKey:kWQUpdateCheckOffPref]',
    ': row == 5 ? NO /* Patch build: updates disabled */')
s = sub_once(s,
    '        cell.accessoryView = toggle;\n        cell.selectionStyle = UITableViewCellSelectionStyleNone;\n        return cell;\n    }\n    if (indexPath.section == 2) {',
    '        cell.accessoryView = toggle;\n        cell.selectionStyle = UITableViewCellSelectionStyleNone;\n        return cell;\n    }\n    if (indexPath.section == 2) {') if False else s
# Both settings UIs contain exactly one update-enabled toggle; lock them off.
# Lock the Check for Updates switch off without changing other Settings rows.
# Match the unique toggle expressions so this survives structural UI changes.
s = sub_once(s,
    '        toggle.on = indexPath.row == 1 ? wq_show_item_counts()',
    '        toggle.enabled = indexPath.row != 4;\n'
    '        toggle.on = indexPath.row == 1 ? wq_show_item_counts()')
s = sub_once(s,
    '        toggle.on = row == 1 ? wq_show_item_counts() : row == 2 ? wq_keep_before_restore()',
    '        toggle.enabled = row != 5;\n'
    '        toggle.on = row == 1 ? wq_show_item_counts() : row == 2 ? wq_keep_before_restore()')
old = 'Check for Updates: twice a day WQ Files reads the public release list on GitHub and shows a note when a new version is out; nothing about your device is sent.'
assert s.count(old) == 2, 'update help text changed'
s=s.replace(old,'Check for Updates: automatically checking for updates is disabled in this Patch build; no update notifications appear.')

# Opening a .3105 file inside WQFiles routes to the importer.
s = sub_once(s,
    'if ([self canEditHere] && [item.name.pathExtension caseInsensitiveCompare:@"zip"] == NSOrderedSame) {',
    'if ([item.name.pathExtension caseInsensitiveCompare:@"3105"] == NSOrderedSame) {\n'
    '            WQPatchViewController *patch = [[WQPatchViewController alloc] initWithImportFilePath:item.path];\n'
    '            [self.navigationController pushViewController:patch animated:YES];\n'
    '            return;\n'
    '        }\n'
    '        if ([self canEditHere] && [item.name.pathExtension caseInsensitiveCompare:@"zip"] == NSOrderedSame) {')
# Opening through iOS Files app / Open In.
s = sub_once(s,
    'else if ([ext isEqualToString:@"zip"])   // a custom inspector (#45)',
    'else if ([ext isEqualToString:@"3105"]) {\n'
    '            dispatch_async(dispatch_get_main_queue(), ^{\n'
    '                UIViewController *host = wq_top_view_controller();\n'
    '                WQPatchViewController *patch = [[WQPatchViewController alloc] initWithImportURL:url];\n'
    '                UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:patch];\n'
    '                [host presentViewController:nav animated:YES completion:nil];\n'
    '            });\n'
    '        }\n'
    '        else if ([ext isEqualToString:@"zip"])   // a custom inspector (#45)')
p.write_text(s)
import plistlib
info_path=root / 'Info.plist'
with info_path.open('rb') as f: info=plistlib.load(f)
identifier='cz.kolbi.wqfiles.patch3105'
info.setdefault('UTImportedTypeDeclarations', []).append({
    'UTTypeIdentifier': identifier, 'UTTypeDescription': '3105 Patch Package',
    'UTTypeConformsTo': ['public.data'],
    'UTTypeTagSpecification': {'public.filename-extension': ['3105']}})
info.setdefault('CFBundleDocumentTypes', []).append({
    'CFBundleTypeName': '3105 Patch Package', 'CFBundleTypeRole': 'Viewer',
    'LSHandlerRank': 'Alternate', 'LSItemContentTypes': [identifier]})
with info_path.open('wb') as f: plistlib.dump(info, f)


p = root / "build.sh"
s = p.read_text()
start = s.index("xcrun --sdk iphoneos clang -fobjc-arc")
end = s.index('cp Info.plist "$APP/Info.plist"', start)
build_part = """mkdir -p "$OUT/obj"
SOURCES=(WQCore.m WQAccess.m WQScanTask.m WQLocalization.m WQLaunchServices.m WQUI.m WQSharing.m WQApps.m WQCache.m WQPlistEditor.m WQHexViewer.m WQSQLiteViewer.m WQSQLiteSave.m WQHealth.m WQTrash.m WQArchive.m WQSyntax.m WQMediaStream.m WQWebServer.m WQTheme.m WQInspector.m WQPatch.m main.m)
OBJECTS=()
for source in "AT{SOURCES[@]}"; do
    object="$OUT/obj/AT{source%.m}.o"
    xcrun --sdk iphoneos clang -fobjc-arc -fmodules -fmodules-cache-path="$OUT/ModuleCache" -arch arm64 -miphoneos-version-min="$MINIMUM_IOS_VERSION" -isysroot "$SDK" -Wall -Wextra -Werror -O2 AT{WQ_EXTRA_CFLAGS:-} -c "$source" -o "$object"
    OBJECTS+=("$object")
done
xcrun --sdk iphoneos swiftc -target arm64-apple-ios26.0 -sdk "$SDK" -O -parse-as-library WQ3105Bridge.swift "AT{OBJECTS[@]}" -framework UIKit -framework Foundation -framework Security -framework UniformTypeIdentifiers -framework JavaScriptCore -lsqlite3 -lz -o "$APP/WQFiles"
"""
build_part=build_part.replace("AT{", chr(36)+"{")
p.write_text(s[:start]+build_part+s[end:])
print("Patch overlay installed")
