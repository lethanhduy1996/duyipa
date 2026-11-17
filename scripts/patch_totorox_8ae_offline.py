#!/usr/bin/env python3
"""Focused reliability fixes for Totorox commit 8ae5daa8.

No license, account, UDID or API modifications. Fail-closed patch anchors.
"""
from pathlib import Path

engine = Path("Totorox/engine/AovModMergerEngine.swift")
data = engine.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global data
    occurrences = data.count(old)
    if occurrences != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, got {occurrences}")
    data = data.replace(old, new)
    print(f"Patched: {label}")


replace_once(
    '''                if contributors.count == 1 {
                    try fm.copyItem(at: first.url, to: destURL)
                    totalWritten += 1
                    continue
                }''',
    '''                if contributors.count == 1 {
                    try fm.copyItem(at: first.url, to: destURL)
                    // Thanos MD5 references must include a unique KernelLua / StableSystems package.
                    if relPath.hasSuffix("/KernelLua.pkg.bytes")
                        || relPath.hasSuffix("/StableSystems_3.pkg.bytes") {
                        let payload = try Data(contentsOf: first.url)
                        mergedPkgMD5s[(relPath as NSString).lastPathComponent] = self.md5Hex(payload)
                    }
                    totalWritten += 1
                    continue
                }''',
    "compute MD5 for single-contributor package",
)
replace_once(
    '''            let outZipName = "GopMod_AOV_\(suffix).zip"
            let outZipURL = outDir.appendingPathComponent(outZipName)
            if fm.fileExists(atPath: outZipURL.path) {
                try? fm.removeItem(at: outZipURL)
            }''',
    '''            // Never destroy an earlier successful merge with the same selected hero IDs.
            let outZipName = "GopMod_AOV_\(suffix)_\(UUID().uuidString).zip"
            let outZipURL = outDir.appendingPathComponent(outZipName)''',
    "retain previous merge outputs",
)
replace_once(
    '''        let components = unified
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." && $0 != ".." }

        guard !components.isEmpty else { return nil }
        if components.contains("__MACOSX") { return nil }''',
    '''        let rawComponents = unified
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        // Reject rather than silently dropping parent traversal segments.
        guard !rawComponents.contains("..") else { return nil }
        let components = rawComponents.filter { $0 != "." }

        guard !components.isEmpty else { return nil }
        if components.contains(where: { $0.uppercased() == "__MACOSX" }) { return nil }''',
    "reject path traversal instead of normalizing it away",
)
replace_once(
    '''        var dst = [UInt8]()
        dst.reserveCapacity(uncompressedSize)''',
    '''        // A corrupt LZ4 length must never force unbounded memory growth.
        guard uncompressedSize >= 0, uncompressedSize <= 256 * 1024 * 1024 else {
            throw AovModMergerError.assetBundleMergeFailed("Kích thước LZ4 vượt giới hạn an toàn.")
        }
        var dst = [UInt8]()
        dst.reserveCapacity(uncompressedSize)''',
    "bound LZ4 advertised output size",
)
replace_once(
    '''            guard pos + litLen <= srcLen else {
                throw AovModMergerError.assetBundleMergeFailed("LZ4 literal vượt quá giới hạn khối.")
            }''',
    '''            guard litLen <= srcLen - pos,
                  litLen <= uncompressedSize - dst.count else {
                throw AovModMergerError.assetBundleMergeFailed("LZ4 literal vượt quá giới hạn khối.")
            }''',
    "bound LZ4 literal copy",
)
replace_once(
    '''            let matchPos = dst.count - offset
            for i in 0..<matchLen {
                dst.append(dst[matchPos + i])
            }
        }

        return Data(dst)''',
    '''            guard matchLen <= uncompressedSize - dst.count else {
                throw AovModMergerError.assetBundleMergeFailed("LZ4 match vượt quá kích thước khai báo.")
            }
            let matchPos = dst.count - offset
            for i in 0..<matchLen {
                dst.append(dst[matchPos + i])
            }
        }

        guard dst.count == uncompressedSize else {
            throw AovModMergerError.assetBundleMergeFailed("Kích thước LZ4 giải nén không khớp header.")
        }
        return Data(dst)''',
    "verify LZ4 final length and match bounds",
)
replace_once(
    '''        let entryCount = Int(readUInt16LE(tail, eocd + 10))
        let centralSize = UInt64(readUInt32LE(tail, eocd + 12))
        let centralOffset = UInt64(readUInt32LE(tail, eocd + 16))
        guard centralOffset + centralSize <= archiveSize else {''',
    '''        let entryCount = Int(readUInt16LE(tail, eocd + 10))
        let centralSize = UInt64(readUInt32LE(tail, eocd + 12))
        let centralOffset = UInt64(readUInt32LE(tail, eocd + 16))
        // Reject absurd central directory sizes before allocating memory.
        guard centralSize <= 128 * 1024 * 1024 else {
            throw AovModMergerError.invalidArchive("ZIP Central Directory quá lớn.")
        }
        guard centralOffset + centralSize <= archiveSize else {''',
    "protect ZIP directory allocation",
)
replace_once(
    '''            pos += 46 + nameLen + extraLen + commentLen
        }
        return results''',
    '''            guard nameLen + extraLen + commentLen <= cdData.count - pos - 46 else {
                throw AovModMergerError.invalidArchive("ZIP Central Directory entry bị cắt cụt.")
            }
            pos += 46 + nameLen + extraLen + commentLen
        }
        guard results.count == entryCount else {
            throw AovModMergerError.invalidArchive("ZIP Central Directory không đủ số mục.")
        }
        return results''',
    "reject truncated ZIP directory",
)

engine.write_text(data, encoding="utf-8")
assert "APIService" not in data and "LicenseManager" not in data
print(f"Patched offline engine: {engine}; {len(data)} chars")

# Extend preexisting XCTest tests with two deterministic regression checks.
tests = Path("TotoroxTests/PatchZipConverterTests.swift")
contents = tests.read_text(encoding="utf-8")
end = "\n}\n"
if not contents.endswith(end):
    raise RuntimeError("Test class closing marker changed")
extra = '''
    func testAovModMergerRejectsParentTraversal() {
        let engine = AovModMergerEngine.shared
        XCTAssertNil(engine.normalizeAovRelativePath("Resources/1.64.1/../../outside.txt"))
        XCTAssertNil(engine.normalizeAovRelativePath("Resources/../outside.txt"))
        XCTAssertNil(engine.normalizeAovRelativePath("__MACOSX/Resources/1.64.1/malicious.txt"))
        XCTAssertEqual(
            engine.normalizeAovRelativePath("Resources/1.64.1/Ages/config.bytes"),
            "Resources/1.64.1/Ages/config.bytes"
        )
    }

    func testAovModMergerDoesNotOverwriteEarlierOutput() async throws {
        let archiveMaker = PatchZipConverter.shared
        let source1 = tempDirectory.appendingPathComponent("source1.zip")
        let source2 = tempDirectory.appendingPathComponent("source2.zip")
        let firstData = try archiveMaker.buildZipArchive(entries: [
            (path: "Resources/1.64.1/Ages/item_a.txt", data: Data("A".utf8))
        ])
        let secondData = try archiveMaker.buildZipArchive(entries: [
            (path: "Resources/1.64.1/Ages/item_b.txt", data: Data("B".utf8))
        ])
        try firstData.write(to: source1, options: .atomic)
        try secondData.write(to: source2, options: .atomic)
        let first = try await AovModMergerEngine.shared.mergeModArchives(
            inputURLs: [source1, source2], progress: { _, _ in }
        )
        defer { try? FileManager.default.removeItem(at: first.outputZipURL) }
        let firstBytes = try Data(contentsOf: first.outputZipURL)
        let second = try await AovModMergerEngine.shared.mergeModArchives(
            inputURLs: [source1, source2], progress: { _, _ in }
        )
        defer { try? FileManager.default.removeItem(at: second.outputZipURL) }
        XCTAssertNotEqual(first.outputZipURL, second.outputZipURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.outputZipURL.path))
        XCTAssertEqual(try Data(contentsOf: first.outputZipURL), firstBytes)
        XCTAssertEqual(first.totalFilesWritten, 2)
        XCTAssertEqual(second.totalFilesWritten, 2)
    }
'''
contents=contents[:-len(end)]+extra+end
tests.write_text(contents, encoding="utf-8")
print(f"Regression XCTest added: {tests}")
