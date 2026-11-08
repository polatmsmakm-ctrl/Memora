import Foundation
import Compression

/// Minimal read-only ZIP reader (stored + deflate) used to open .docx files without
/// third-party dependencies. Apple's COMPRESSION_ZLIB decodes raw DEFLATE streams,
/// which is exactly what ZIP entries contain.
struct ZipArchiveReader {
    struct Entry {
        var name: String
        var method: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    enum ZipError: Error {
        case notZip, corrupt, unsupportedMethod, entryNotFound
    }

    private let bytes: [UInt8]
    let entries: [Entry]

    init(data: Data) throws {
        bytes = [UInt8](data)
        entries = try Self.readCentralDirectory(bytes)
    }

    func data(for name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else { throw ZipError.entryNotFound }
        return try extract(entry)
    }

    func extract(_ entry: Entry) throws -> Data {
        let o = entry.localHeaderOffset
        guard o + 30 <= bytes.count, Self.u32(bytes, o) == 0x0403_4b50 else { throw ZipError.corrupt }
        let nameLength = Int(Self.u16(bytes, o + 26))
        let extraLength = Int(Self.u16(bytes, o + 28))
        let start = o + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= bytes.count, start <= end else { throw ZipError.corrupt }
        let compressed = Array(bytes[start..<end])
        switch entry.method {
        case 0:
            return Data(compressed)
        case 8:
            return try Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedMethod
        }
    }

    private static func inflate(_ source: [UInt8], expectedSize: Int) throws -> Data {
        guard !source.isEmpty else { return Data() }
        var capacity = max(expectedSize, source.count * 4, 1024)
        for _ in 0..<4 {
            var destination = [UInt8](repeating: 0, count: capacity)
            let written = source.withUnsafeBufferPointer { src -> Int in
                destination.withUnsafeMutableBufferPointer { dst -> Int in
                    guard let s = src.baseAddress, let d = dst.baseAddress else { return 0 }
                    return compression_decode_buffer(d, dst.count, s, src.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written > 0 && (written < capacity || expectedSize == written) {
                return Data(destination.prefix(written))
            }
            capacity *= 4
        }
        throw ZipError.corrupt
    }

    private static func readCentralDirectory(_ b: [UInt8]) throws -> [Entry] {
        guard b.count >= 22 else { throw ZipError.notZip }
        var eocd = -1
        let lowerBound = max(0, b.count - 65_557)
        var i = b.count - 22
        while i >= lowerBound {
            if u32(b, i) == 0x0605_4b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }
        let count = Int(u16(b, eocd + 10))
        var offset = Int(u32(b, eocd + 16))
        var entries: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= b.count, u32(b, offset) == 0x0201_4b50 else { throw ZipError.corrupt }
            let method = u16(b, offset + 10)
            let compressed = Int(u32(b, offset + 20))
            let uncompressed = Int(u32(b, offset + 24))
            let nameLength = Int(u16(b, offset + 28))
            let extraLength = Int(u16(b, offset + 30))
            let commentLength = Int(u16(b, offset + 32))
            let localOffset = Int(u32(b, offset + 42))
            guard offset + 46 + nameLength <= b.count else { throw ZipError.corrupt }
            let name = String(decoding: b[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            entries.append(Entry(name: name, method: method, compressedSize: compressed,
                                 uncompressedSize: uncompressed, localHeaderOffset: localOffset))
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        guard o + 1 < b.count else { return 0 }
        return UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    private static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 3 < b.count else { return 0 }
        return UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }
}
