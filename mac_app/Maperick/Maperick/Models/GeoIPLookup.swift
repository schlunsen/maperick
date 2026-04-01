import Foundation

// MARK: - GeoIP Result

struct GeoIPResult {
    let city: String
    let country: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
}

// MARK: - Minimal MMDB Reader

/// A minimal MaxMind DB (MMDB) reader in pure Swift.
/// Supports IPv4 lookups for City database format (DB-IP / MaxMind).
/// Marked nonisolated so it can be used from Task.detached for background polling.
nonisolated class GeoIPService {
    private var data: Data?
    private var nodeCount: Int = 0
    private var recordSize: Int = 0
    private var ipVersion: Int = 0
    private var treeSize: Int = 0
    private var dataSectionStart: Int = 0
    private var cache: [String: GeoIPResult?] = [:]

    init() {
        loadDatabase()
    }

    private func loadDatabase() {
        let path = AppConstants.geoDBPath
        guard AppConstants.geoDBExists else {
            print("[Maperick] GeoIP database not found at \(path.path)")
            return
        }

        do {
            data = try Data(contentsOf: path, options: .alwaysMapped)
            parseMetadata()
        } catch {
            print("[Maperick] Failed to load GeoIP database: \(error)")
        }
    }

    /// Look up geo information for an IP address string
    func lookup(_ ipString: String) -> GeoIPResult? {
        // Check cache first
        if let cached = cache[ipString] {
            return cached
        }

        let result = performLookup(ipString)
        cache[ipString] = result
        return result
    }

    /// Perform the actual MMDB lookup (uncached)
    private func performLookup(_ ipString: String) -> GeoIPResult? {
        guard let data = data, nodeCount > 0, recordSize > 0 else { return nil }

        // Parse IPv4 address
        let ipParts = ipString.split(separator: ".")
        guard ipParts.count == 4,
              let b0 = UInt8(ipParts[0]),
              let b1 = UInt8(ipParts[1]),
              let b2 = UInt8(ipParts[2]),
              let b3 = UInt8(ipParts[3]) else {
            return nil
        }

        let ipBytes: [UInt8] = [b0, b1, b2, b3]

        var node = 0

        // For IPv4 in an IPv6 tree, skip through 96 zero bits first
        if ipVersion == 6 {
            for _ in 0..<96 {
                let (left, _) = readNode(node, data: data)
                node = left
                if node >= nodeCount { return nil }
            }
        }

        // Traverse the 32 IPv4 bits
        for i in 0..<32 {
            let byteIndex = i / 8
            let bitOffset = 7 - (i % 8)
            let bit = Int((ipBytes[byteIndex] >> bitOffset) & 1)

            let (left, right) = readNode(node, data: data)
            node = bit == 0 ? left : right

            if node == nodeCount {
                return nil // empty record
            } else if node > nodeCount {
                // Found data
                let dataOffset = node - nodeCount - 16
                let actualOffset = dataSectionStart + dataOffset
                return parseDataRecord(in: data, offset: actualOffset)
            }
        }

        return nil
    }

    // MARK: - Node Reading

    private func readNode(_ node: Int, data: Data) -> (Int, Int) {
        let offset = node * (recordSize * 2 / 8)
        guard offset + (recordSize * 2 / 8) <= data.count else { return (0, 0) }

        switch recordSize {
        case 24:
            let left = Int(data[offset]) << 16 | Int(data[offset + 1]) << 8 | Int(data[offset + 2])
            let right = Int(data[offset + 3]) << 16 | Int(data[offset + 4]) << 8 | Int(data[offset + 5])
            return (left, right)
        case 28:
            let middle = data[offset + 3]
            let left = (Int(middle & 0xF0) << 20) | (Int(data[offset]) << 16) | (Int(data[offset + 1]) << 8) | Int(data[offset + 2])
            let right = (Int(middle & 0x0F) << 24) | (Int(data[offset + 4]) << 16) | (Int(data[offset + 5]) << 8) | Int(data[offset + 6])
            return (left, right)
        case 32:
            let left = Int(data[offset]) << 24 | Int(data[offset + 1]) << 16 | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            let right = Int(data[offset + 4]) << 24 | Int(data[offset + 5]) << 16 | Int(data[offset + 6]) << 8 | Int(data[offset + 7])
            return (left, right)
        default:
            return (0, 0)
        }
    }

    // MARK: - Data Record Parsing

    private func parseDataRecord(in data: Data, offset: Int) -> GeoIPResult? {
        guard offset < data.count else { return nil }

        var parser = MMDBParser(data: data, offset: offset, sectionStart: dataSectionStart)
        guard let dict = parser.parse() as? [String: Any] else { return nil }

        var city = ""
        var country = ""
        var countryCode = ""
        var latitude = 0.0
        var longitude = 0.0

        if let cityDict = dict["city"] as? [String: Any],
           let names = cityDict["names"] as? [String: Any] {
            city = names["en"] as? String ?? ""
        }

        if let countryDict = dict["country"] as? [String: Any] {
            if let names = countryDict["names"] as? [String: Any] {
                country = names["en"] as? String ?? ""
            }
            if let isoCode = countryDict["iso_code"] as? String {
                countryCode = isoCode
            }
        }

        if let locationDict = dict["location"] as? [String: Any] {
            latitude = locationDict["latitude"] as? Double ?? 0
            longitude = locationDict["longitude"] as? Double ?? 0
        }

        guard latitude != 0 || longitude != 0 else { return nil }

        return GeoIPResult(
            city: city,
            country: country,
            countryCode: countryCode,
            latitude: latitude,
            longitude: longitude
        )
    }

    // MARK: - Metadata Parsing

    private func parseMetadata() {
        guard let data = data else { return }

        let marker = Data([0xAB, 0xCD, 0xEF, 0x4D, 0x61, 0x78, 0x4D, 0x69, 0x6E, 0x64, 0x2E, 0x63, 0x6F, 0x6D])
        guard let markerRange = data.range(of: marker) else { return }

        let metaStart = markerRange.upperBound
        guard metaStart < data.count else { return }

        var parser = MMDBParser(data: data, offset: metaStart, sectionStart: metaStart)
        guard let metaDict = parser.parse() as? [String: Any] else { return }

        nodeCount = metaDict["node_count"] as? Int ?? 0
        recordSize = metaDict["record_size"] as? Int ?? 28
        ipVersion = metaDict["ip_version"] as? Int ?? 4
        treeSize = nodeCount * (recordSize * 2 / 8)
        dataSectionStart = treeSize + 16 // 16 bytes of null padding after tree
    }
}

// MARK: - MMDB Data Parser

/// Parses MMDB data section values (maps, arrays, strings, numbers, etc.)
nonisolated private struct MMDBParser {
    let data: Data
    var offset: Int
    let sectionStart: Int  // base offset for resolving pointers

    mutating func parse() -> Any? {
        guard offset >= 0, offset < data.count else { return nil }

        let ctrl = data[offset]
        offset += 1

        var type = UInt8((ctrl >> 5) & 0x07)

        // Pointer (type 1) — handle before extended type check
        if type == 1 {
            return parsePointer(ctrl: ctrl)
        }

        var size = Int(ctrl & 0x1F)

        // Extended type: type bits = 0 means read next byte + 7
        if type == 0 {
            guard offset < data.count else { return nil }
            type = data[offset] + 7
            offset += 1
        }

        // Extended size
        if size == 29 {
            guard offset < data.count else { return nil }
            size = 29 + Int(data[offset]); offset += 1
        } else if size == 30 {
            guard offset + 1 < data.count else { return nil }
            size = 285 + Int(data[offset]) * 256 + Int(data[offset + 1]); offset += 2
        } else if size == 31 {
            guard offset + 2 < data.count else { return nil }
            size = 65821 + Int(data[offset]) * 65536 + Int(data[offset + 1]) * 256 + Int(data[offset + 2]); offset += 3
        }

        switch type {
        case 2: // UTF-8 string
            return parseString(size: size)
        case 3: // double (big-endian IEEE 754)
            return parseDouble(size: size)
        case 4: // bytes
            offset += size; return nil
        case 5, 6, 9: // uint16, uint32, uint64
            return parseUint(size: size)
        case 7: // map
            return parseMap(size: size)
        case 8: // int32
            return parseInt32(size: size)
        case 11: // array
            return parseArray(size: size)
        case 14: // boolean
            return size != 0
        case 15: // float (big-endian IEEE 754)
            return parseFloat(size: size)
        default:
            offset += size; return nil
        }
    }

    private mutating func parsePointer(ctrl: UInt8) -> Any? {
        let ptrSize = Int((ctrl >> 3) & 0x03)
        let lowBits = Int(ctrl & 0x07)
        var ptrValue = 0

        switch ptrSize {
        case 0:
            guard offset < data.count else { return nil }
            ptrValue = (lowBits << 8) | Int(data[offset]); offset += 1
        case 1:
            guard offset + 1 < data.count else { return nil }
            ptrValue = 2048 + ((lowBits << 16) | (Int(data[offset]) << 8) | Int(data[offset + 1])); offset += 2
        case 2:
            guard offset + 2 < data.count else { return nil }
            ptrValue = 526336 + ((lowBits << 24) | (Int(data[offset]) << 16) | (Int(data[offset + 1]) << 8) | Int(data[offset + 2])); offset += 3
        case 3:
            guard offset + 3 < data.count else { return nil }
            ptrValue = (Int(data[offset]) << 24) | (Int(data[offset + 1]) << 16) | (Int(data[offset + 2]) << 8) | Int(data[offset + 3]); offset += 4
        default:
            return nil
        }

        // Resolve pointer relative to section start
        let savedOffset = offset
        var subParser = MMDBParser(data: data, offset: sectionStart + ptrValue, sectionStart: sectionStart)
        let result = subParser.parse()
        offset = savedOffset
        return result
    }

    private mutating func parseMap(size: Int) -> [String: Any]? {
        var result: [String: Any] = [:]
        for _ in 0..<size {
            guard let key = parse() as? String else { return result }
            let value = parse()
            result[key] = value
        }
        return result
    }

    private mutating func parseArray(size: Int) -> [Any]? {
        var result: [Any] = []
        for _ in 0..<size {
            if let value = parse() {
                result.append(value)
            }
        }
        return result
    }

    private mutating func parseString(size: Int) -> String? {
        guard offset + size <= data.count else { return nil }
        let str = String(data: data[offset..<(offset + size)], encoding: .utf8)
        offset += size
        return str
    }

    private mutating func parseDouble(size: Int) -> Double? {
        guard size == 8, offset + 8 <= data.count else {
            offset += size; return nil
        }
        // Big-endian to little-endian
        var bytes = [UInt8](data[offset..<(offset + 8)])
        bytes.reverse()
        offset += 8
        return bytes.withUnsafeBytes { $0.load(as: Double.self) }
    }

    private mutating func parseFloat(size: Int) -> Double? {
        guard size == 4, offset + 4 <= data.count else {
            offset += size; return nil
        }
        var bytes = [UInt8](data[offset..<(offset + 4)])
        bytes.reverse()
        offset += 4
        return Double(bytes.withUnsafeBytes { $0.load(as: Float.self) })
    }

    private mutating func parseUint(size: Int) -> Int? {
        guard offset + size <= data.count else { return nil }
        var value = 0
        for i in 0..<size {
            value = value << 8 | Int(data[offset + i])
        }
        offset += size
        return value
    }

    private mutating func parseInt32(size: Int) -> Int? {
        guard offset + size <= data.count else { return nil }
        var value: Int32 = 0
        for i in 0..<size {
            value = value << 8 | Int32(data[offset + i])
        }
        offset += size
        return Int(value)
    }
}
