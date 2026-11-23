# WQFiles Patch overlay (experimental)

Base: [kolbicz/WQFiles](https://github.com/kolbicz/WQFiles) at commit `a8a4d06cbf2651de1cd7bd9f5f8e38f67b025890`.

## Features

- New **Patch** tab in Prism UI and Patch row in Classic UI.
- Import selected `.3105` packages from Files, including password protected archives.
- Verify authenticated AES-GCM envelope, key fingerprint and SHA-256 payload hashes.
- Explicit apply confirmation; keep local originals and SHA-256 journal under Documents/WQPatchBackups.
- Restore original bytes / delete added files only if the target still hashes to the applied bytes. Refuse changed targets.

## Limitations

This is an **experimental implementation, not a drop-in replacement for 3105**. The decoder currently accepts package schemas 1-3 as implemented in the inspected 3105 repository's `PatchPackageCodec.swift`. Other package versions, including newer schemas, are rejected without modifying data. A basic single-file `.3105` v3 exporter is available, but there is no multi-file editor, plist merge, JSON merge, AppGroup mapping or custom fields. Only Application data (Documents/Library/tmp) and existing parent directories are supported; max 8 MiB per file, 64 MiB per package. No attempt is made to bypass access permissions; access depends on the installed iOS version and signing.

## CI build

The GitHub Actions workflow checks out this overlay, clones the pinned upstream source, runs `patch/prepare_upstream.py`, then runs the original `build.sh` with a mixed Objective-C / Swift link. It runs fast package validation; the full upstream regression suite is not part of the release build (its inode checkpoint test can time out on hosted macOS runners). The result is an ad-hoc-signed IPA, **not** a production-signed or device-tested build. A compatible provisioning profile / App Group must be retained when side-loading. Review CI logs for failures and do not consider the IPA tested until device validation.

## License

GPL-3.0-or-later, consistent with the upstream WQFiles and 3105 sources. Verify the relevant upstream repository licenses before redistribution. This overlay is intended for data and apps you own or are authorized to modify. Do not use it to circumvent paid features or third-party restrictions.
