import Foundation
enum RustBalanceDecoder {
    static func uint64Field(_ field: String, from json: String) -> UInt64? {
        guard let obj = parseObject(json) else { return nil }
        if let n = obj[field] as? NSNumber { return n.uint64Value }
        if let s = obj[field] as? String   { return UInt64(s) }
        return nil
    }
    static func int64Field(_ field: String, from json: String) -> Int64? {
        guard let obj = parseObject(json) else { return nil }
        if let n = obj[field] as? NSNumber { return n.int64Value }
        if let s = obj[field] as? String   { return Int64(s) }
        return nil
    }
    static func uint128StringField(_ field: String, from json: String) -> Double? {
        guard let obj = parseObject(json) else { return nil }
        if let n = obj[field] as? NSNumber { return n.doubleValue }
        if let s = obj[field] as? String   { return Double(s) }
        return nil
    }
    static func evmNativeBalance(from json: String) -> Double? {
        guard let obj = parseObject(json) else { return nil }
        if let s = obj["balance_display"] as? String, let v = Double(s) { return v }
        if let n = obj["balance_wei"] as? NSNumber { return n.doubleValue / 1e18 }
        if let s = obj["balance_wei"] as? String, let wei = Double(s) { return wei / 1e18 }
        return nil
    }
    static func yoctoNearToDouble(from json: String) -> Double? {
        guard let obj = parseObject(json) else { return nil }
        if let s = obj["near_display"] as? String, let v = Double(s) { return v }
        if let s = obj["yocto_near"] as? String, let yocto = Double(s) { return yocto / 1e24 }
        if let n = obj["yocto_near"] as? NSNumber { return n.doubleValue / 1e24 }
        return nil
    }
    private static func parseObject(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
