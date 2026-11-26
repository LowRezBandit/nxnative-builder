import Foundation

enum PackageHeaderReader {
    private static let pfs0TitleIDRegex = try? NSRegularExpression(
        pattern: #"^((?:0100|0400)[0-9A-Fa-f]{12}).*\.(?:tik|cnmt\.xml)$"#,
        options: [.caseInsensitive]
    )

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func readUInt64LE(_ data: Data, at offset: Int) -> UInt64 {
        var val: UInt64 = 0
        for i in 0..<8 {
            val |= UInt64(data[offset + i]) << (i * 8)
        }
        return val
    }

    static func readNupContents(at url: URL) -> [PackageContentRecord]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let superData = try? handle.read(upToCount: 0x80), superData.count == 0x80 else { return nil }
        guard superData[0] == 0x4E, superData[1] == 0x55, superData[2] == 0x50, superData[3] == 0x01 else {
            return nil
        }

        let tocOff = readUInt64LE(superData, at: 0x08)
        let tocSize = readUInt64LE(superData, at: 0x10)
        let npkg = Int(readUInt32LE(superData, at: 0x48))
        guard npkg > 0, npkg <= 1024, tocSize >= UInt64(0x30 + npkg * 0x40), tocSize <= 16 * 1024 * 1024 else {
            return nil
        }

        do {
            try handle.seek(toOffset: tocOff)
        } catch {
            return nil
        }

        let needBytes = 0x30 + npkg * 0x40
        guard let tocData = try? handle.read(upToCount: needBytes), tocData.count == needBytes else { return nil }
        guard tocData[0] == 0x54, tocData[1] == 0x4F, tocData[2] == 0x43, tocData[3] == 0x01 else {
            return nil
        }

        var records: [PackageContentRecord] = []
        for i in 0..<npkg {
            let base = 0x30 + i * 0x40
            let titleID = readUInt64LE(tocData, at: base)
            let version = readUInt32LE(tocData, at: base + 0x14)
            let kindByte = tocData[base + 0x18]

            let kindName: String
            switch kindByte {
            case 0: kindName = "Application"
            case 1: kindName = "Patch"
            case 2, 3: kindName = "AddOnContent"
            default: continue
            }

            records.append(PackageContentRecord(
                kind: kindName,
                titleID: String(format: "%016llX", titleID),
                version: version
            ))
        }
        return records.isEmpty ? nil : records
    }

    static func readPFS0TitleID(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 0x10), header.count == 0x10 else { return nil }
        guard header[0] == 0x50, header[1] == 0x46, header[2] == 0x53, header[3] == 0x30 else { return nil }

        let fileCount = Int(readUInt32LE(header, at: 0x04))
        let strTableSize = Int(readUInt32LE(header, at: 0x08))
        guard fileCount > 0, fileCount <= 4096, strTableSize > 0, strTableSize <= 65536 else { return nil }

        let skipBytes = fileCount * 24
        do {
            try handle.seek(toOffset: UInt64(0x10 + skipBytes))
        } catch {
            return nil
        }
        guard let strData = try? handle.read(upToCount: strTableSize), !strData.isEmpty else { return nil }

        let names = strData.split(separator: 0).compactMap { String(data: Data($0), encoding: .utf8) }
        guard let regex = pfs0TitleIDRegex else { return nil }

        for name in names {
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            if let match = regex.firstMatch(in: name, range: range),
               let tidRange = Range(match.range(at: 1), in: name) {
                return String(name[tidRange]).uppercased()
            }
        }
        return nil
    }
}
