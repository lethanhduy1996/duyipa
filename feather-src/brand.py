#!/usr/bin/env python3
"""Apply minimal, auditable DLSIGN branding to pinned GPL-3.0 Feather sources.

Avoid changing signing or installation internals; keep Feather attribution.
"""
import json
import plistlib
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
assert (root / 'Feather.xcodeproj/project.pbxproj').exists(), 'Feather source missing'

def replace_exact(path, needle, replacement, count):
    text = path.read_text(encoding='utf-8')
    observed = text.count(needle)
    if observed != count:
        raise RuntimeError(f'{path}: expected {count} occurrences of {needle!r}, found {observed}')
    path.write_text(text.replace(needle, replacement), encoding='utf-8')

config = root / 'Feather.xcconfig'
replace_exact(config, 'FEATHER_PRODUCT_BUNDLE_IDENTIFIER=thewonderofyou.Feather',
              'FEATHER_PRODUCT_BUNDLE_IDENTIFIER=vn.dlsign.feather', 1)

project = root / 'Feather.xcodeproj/project.pbxproj'
replace_exact(project, 'INFOPLIST_KEY_CFBundleDisplayName = Feather;',
              'INFOPLIST_KEY_CFBundleDisplayName = DLSIGN;', 2)

# The pinned upstream pbxproj registers NimbleViews and NimbleExtensions
# twice as the same Swift Package products. This can abort Xcode's package
# graph with an NSInvalidArgumentException before compilation begins.
# Remove only the second references; keep the first of each product.
duplicates = [
    '330F69012DC03DF500D8C35D',  # duplicate NimbleExtensions PBXBuildFile
    '330F69032DC03DF500D8C35D',  # duplicate NimbleViews PBXBuildFile
    '330F69002DC03DF500D8C35D',  # duplicate NimbleExtensions product
    '330F69022DC03DF500D8C35D',  # duplicate NimbleViews product
]
lines = project.read_text(encoding='utf-8').splitlines(keepends=True)
filtered = []
skipping = False
seen = {key: 0 for key in duplicates}
for line in lines:
    if skipping:
        if line.strip() == '};':
            skipping = False
        continue
    key = next((key for key in duplicates if line.lstrip().startswith(key + ' ')), None)
    if key:
        seen[key] += 1
        if '= {' in line and not line.strip().endswith('};'):
            skipping = True
        continue
    filtered.append(line)
text = ''.join(filtered)
if skipping or any(value != 2 for value in seen.values()) or any(key in text for key in duplicates):
    raise RuntimeError('Unexpected NimbleKit duplicate project structure; refusing unsafe patch')
project.write_text(text, encoding='utf-8')
print('Removed duplicate NimbleViews/NimbleExtensions Xcode product references.')

plist = root / 'Feather/Resources/Info.plist'
with plist.open('rb') as f:
    info = plistlib.load(f)
# Rename the public URL scheme without losing internal import support.
for item in info.get('CFBundleURLTypes', []):
    item['CFBundleURLSchemes'] = [
        ('dlsign' if scheme == 'feather' else scheme)
        for scheme in item.get('CFBundleURLSchemes', [])
    ]
for entry in info.get('UTExportedTypeDeclarations', []):
    old = entry.get('UTTypeIdentifier', '')
    if old.startswith('thewonderofyou.Feather.'):
        entry['UTTypeIdentifier'] = old.replace('thewonderofyou.Feather.', 'vn.dlsign.feather.', 1)
for entry in info.get('CFBundleDocumentTypes', []):
    entry['LSItemContentTypes'] = [
        kind.replace('thewonderofyou.Feather.', 'vn.dlsign.feather.', 1)
        for kind in entry.get('LSItemContentTypes', [])
    ]
with plist.open('wb') as f:
    plistlib.dump(info, f, sort_keys=False)

app = root / 'Feather/FeatherApp.swift'
replace_exact(app, 'if url.scheme == "feather" {',
              'if url.scheme == "dlsign" {', 1)

icon_json = root / 'Feather/Resources/AppIcon.icon/icon.json'
data = json.loads(icon_json.read_text(encoding='utf-8'))
data['fill']['linear-gradient'] = [
    'srgb:0.035,0.12,0.18,1.00000',
    'srgb:0.15,0.76,0.67,1.00000',
]
# Keep icon Composer format, but replace Feather glyph with DLSIGN DL layer.
for group in data.get('groups', []):
    if group.get('layers'):
        group['layers'] = [{'image-name':'feather.png', 'name':'DLSIGN'}]
icon_json.write_text(json.dumps(data, indent=2), encoding='utf-8')

print('Branding complete: DLSIGN / vn.dlsign.feather; Feather functionality preserved.')
