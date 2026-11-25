# Blu Color Maker

Standalone SwiftUI color-effect designer for iOS 16 and newer. It previews a stylized character, saves local presets, and exports JSON color configurations. It does not modify or connect to games.

## Build on GitHub

The Build Blu Color Maker IPA workflow runs on pushes to the blu-color-maker branch when project files change. It builds a Release app for physical iOS devices on macOS and uploads an unsigned IPA and SHA-256 checksum as the BluColorMaker-IPA artifact.

## Local build

Install Xcode and XcodeGen on macOS, then run:

    cd BluColorMaker
    xcodegen generate
    open BluColorMaker.xcodeproj

For installation on an iPhone, sign the app with an appropriate Apple development or distribution identity and provisioning profile. The unsigned CI artifact cannot install directly until signed.

The exported presets are JSON files for this independent app, not .3105 patches.
