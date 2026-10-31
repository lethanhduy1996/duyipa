# DLSIGN — Feather-based iOS build

This is a customized build of **Feather** by its upstream authors. This is NOT the original Feather release, and the Feather maintainers do not endorse this build.

- Upstream source: https://github.com/claration/feather
- Upstream source commit: `7078b053c0af262809a48e4d3898d42b0d35fedf`
- Upstream license: **GNU GPL version 3** (`LICENSE` in Feather repository)
- DLSIGN modifications: `feather-port/brand.py`, `feather-port/make_icon.swift`, and `.github/workflows/build-dlsign-feather.yml`
- Display name: DLSIGN
- Bundle identifier: `vn.dlsign.feather`
- IPA is **unsigned**. You must use a valid certificate and provisioning profile to install it.
- Preserves Feather's signing engine and UI, as well as attribution. No remote IPA-signing server is deployed.
- This build uses the actual Feather project, unlike the previous small experimental DLSIGN app.

## Source and license requirements

Feather is licensed under GPL-3.0. Distribution of a modified binary to other people requires supplying the corresponding source and license, including the upstream source at the pinned commit, its relevant submodules, and the above modifications/scripts. If the build branch is private, publishing only a private link is insufficient for distributing GPL-covered binaries publicly; publish or otherwise provide the complete corresponding source to recipients under the GPL.

## Rebuild

Use the GitHub Actions workflow "Build DLSIGN (Feather engine)" in the `dlsign-feather` branch. It clones Feather from the pinned commit with submodules, applies transparent modifications, uses Xcode on a macOS 26 runner, builds unsigned for iOS, and bundles the resulting IPA with license and attribution.

No P12 or Apple Developer credentials are used by the CI build.
