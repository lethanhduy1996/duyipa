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
     'self.viewControllers = @[homeNav, appsNav, cleanNav, vaultNav, patchNav];'),
    ('return section == 0 ? (NSInteger)_locations.count + (wq_system_areas_reachable() ? 1 : 0) : 10;',
     'return section == 0 ? (NSInteger)_locations.count + (wq_system_areas_reachable() ? 1 : 0) : 11;'),
    ('@[@"Recent", @"clock"], @[@"Inspectors", @"curlybraces"]];',
     '@[@"Recent", @"clock"], @[@"Inspectors", @"curlybraces"], @[@"Patch", @"square.stack.3d.up"]];'),
    ('} else if (indexPath.row == 9) {\n        wq_open_inspectors_folder(self.navigationController);',
     '} else if (indexPath.row == 10) {\n        next = [WQPatchViewController new];\n    } else if (indexPath.row == 9) {\n        wq_open_inspectors_folder(self.navigationController);'),
]
for old, new in changes: s=sub_once(s, old, new)
p.write_text(s)

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
