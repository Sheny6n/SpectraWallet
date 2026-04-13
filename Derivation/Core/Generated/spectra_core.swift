import Foundation
#if canImport(spectra_coreFFI)
import spectra_coreFFI
#endif
fileprivate extension RustBuffer {
    init(bytes: [UInt8]) {
        let rbuf = bytes.withUnsafeBufferPointer { ptr in RustBuffer.from(ptr) }
        self.init(capacity: rbuf.capacity, len: rbuf.len, data: rbuf.data)
    }
    static func empty() -> RustBuffer { RustBuffer(capacity: 0, len:0, data: nil) }
    static func from(_ ptr: UnsafeBufferPointer<UInt8>) -> RustBuffer {
        try! rustCall { ffi_spectra_core_rustbuffer_from_bytes(ForeignBytes(bufferPointer: ptr), $0) }}
    func deallocate() {
        try! rustCall { ffi_spectra_core_rustbuffer_free(self, $0) }}
}
fileprivate extension ForeignBytes {
    init(bufferPointer: UnsafeBufferPointer<UInt8>) {
        self.init(len: Int32(bufferPointer.count), data: bufferPointer.baseAddress)
    }
}
fileprivate extension Data {
    init(rustBuffer: RustBuffer) {
        self.init(
            bytesNoCopy: rustBuffer.data!, count: Int(rustBuffer.len), deallocator: .none
        )
    }
}
fileprivate func createReader(data: Data) -> (data: Data, offset: Data.Index) {
    (data: data, offset: 0)
}
fileprivate func readInt<T: FixedWidthInteger>(_ reader: inout (data: Data, offset: Data.Index)) throws -> T {
    let range = reader.offset..<reader.offset + MemoryLayout<T>.size
    guard reader.data.count >= range.upperBound else { throw UniffiInternalError.bufferOverflow }
    if T.self == UInt8.self {
        let value = reader.data[reader.offset]
        reader.offset += 1
        return value as! T
    }
    var value: T = 0
    let _ = withUnsafeMutableBytes(of: &value, { reader.data.copyBytes(to: $0, from: range)})
    reader.offset = range.upperBound
    return value.bigEndian
}
fileprivate func readBytes(_ reader: inout (data: Data, offset: Data.Index), count: Int) throws -> Array<UInt8> {
    let range = reader.offset..<(reader.offset+count)
    guard reader.data.count >= range.upperBound else { throw UniffiInternalError.bufferOverflow }
    var value = [UInt8](repeating: 0, count: count)
    value.withUnsafeMutableBufferPointer({ buffer in reader.data.copyBytes(to: buffer, from: range) })
    reader.offset = range.upperBound
    return value
}
fileprivate func readFloat(_ reader: inout (data: Data, offset: Data.Index)) throws -> Float {
    return Float(bitPattern: try readInt(&reader))
}
fileprivate func readDouble(_ reader: inout (data: Data, offset: Data.Index)) throws -> Double {
    return Double(bitPattern: try readInt(&reader))
}
fileprivate func hasRemaining(_ reader: (data: Data, offset: Data.Index)) -> Bool {
    return reader.offset < reader.data.count
}
fileprivate func createWriter() -> [UInt8] {
    return []
}
fileprivate func writeBytes<S>(_ writer: inout [UInt8], _ byteArr: S) where S: Sequence, S.Element == UInt8 {
    writer.append(contentsOf: byteArr)
}
fileprivate func writeInt<T: FixedWidthInteger>(_ writer: inout [UInt8], _ value: T) {
    var value = value.bigEndian
    withUnsafeBytes(of: &value) { writer.append(contentsOf: $0) }
}
fileprivate func writeFloat(_ writer: inout [UInt8], _ value: Float) {
    writeInt(&writer, value.bitPattern)
}
fileprivate func writeDouble(_ writer: inout [UInt8], _ value: Double) {
    writeInt(&writer, value.bitPattern)
}
fileprivate protocol FfiConverter {
    associatedtype FfiType
    associatedtype SwiftType
    static func lift(_ value: FfiType) throws -> SwiftType
    static func lower(_ value: SwiftType) -> FfiType
    static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> SwiftType
    static func write(_ value: SwiftType, into buf: inout [UInt8])
}
fileprivate protocol FfiConverterPrimitive: FfiConverter where FfiType == SwiftType { }
extension FfiConverterPrimitive {
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public static func lift(_ value: FfiType) throws -> SwiftType { return value }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public static func lower(_ value: SwiftType) -> FfiType { return value }
}
fileprivate protocol FfiConverterRustBuffer: FfiConverter where FfiType == RustBuffer {}
extension FfiConverterRustBuffer {
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public static func lift(_ buf: RustBuffer) throws -> SwiftType {
        var reader = createReader(data: Data(rustBuffer: buf))
        let value = try read(from: &reader)
        if hasRemaining(reader) { throw UniffiInternalError.incompleteData }
        buf.deallocate()
        return value
    }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public static func lower(_ value: SwiftType) -> RustBuffer {
          var writer = createWriter()
          write(value, into: &writer)
          return RustBuffer(bytes: writer)
    }
}
fileprivate enum UniffiInternalError: LocalizedError {
    case bufferOverflow
    case incompleteData
    case unexpectedOptionalTag
    case unexpectedEnumCase
    case unexpectedNullPointer
    case unexpectedRustCallStatusCode
    case unexpectedRustCallError
    case unexpectedStaleHandle
    case rustPanic(_ message: String)
    public var errorDescription: String? {
        switch self {
        case .bufferOverflow: return "Reading the requested value would read past the end of the buffer"
        case .incompleteData: return "The buffer still has data after lifting its containing value"
        case .unexpectedOptionalTag: return "Unexpected optional tag; should be 0 or 1"
        case .unexpectedEnumCase: return "Raw enum value doesn't match any cases"
        case .unexpectedNullPointer: return "Raw pointer value was null"
        case .unexpectedRustCallStatusCode: return "Unexpected RustCallStatus code"
        case .unexpectedRustCallError: return "CALL_ERROR but no errorClass specified"
        case .unexpectedStaleHandle: return "The object in the handle map has been dropped already"
        case let .rustPanic(message): return message
        }}
}
fileprivate extension NSLock {
    func withLock<T>(f: () throws -> T) rethrows -> T {
        self.lock()
        defer { self.unlock() }
        return try f()
    }
}
fileprivate let CALL_SUCCESS: Int8 = 0
fileprivate let CALL_ERROR: Int8 = 1
fileprivate let CALL_UNEXPECTED_ERROR: Int8 = 2
fileprivate let CALL_CANCELLED: Int8 = 3
fileprivate extension RustCallStatus {
    init() {
        self.init(
            code: CALL_SUCCESS, errorBuf: RustBuffer.init(
                capacity: 0, len: 0, data: nil
            )
        )
    }
}
private func rustCall<T>(_ callback: (UnsafeMutablePointer<RustCallStatus>) -> T) throws -> T {
    let neverThrow: ((RustBuffer) throws -> Never)? = nil
    return try makeRustCall(callback, errorHandler: neverThrow)
}
private func rustCallWithError<T, E: Swift.Error>(
    _ errorHandler: @escaping (RustBuffer) throws -> E, _ callback: (UnsafeMutablePointer<RustCallStatus>) -> T) throws -> T {
    try makeRustCall(callback, errorHandler: errorHandler)
}
private func makeRustCall<T, E: Swift.Error>(
    _ callback: (UnsafeMutablePointer<RustCallStatus>) -> T, errorHandler: ((RustBuffer) throws -> E)?
) throws -> T {
    uniffiEnsureSpectraDerivationInitialized()
    var callStatus = RustCallStatus.init()
    let returnedVal = callback(&callStatus)
    try uniffiCheckCallStatus(callStatus: callStatus, errorHandler: errorHandler)
    return returnedVal
}
private func uniffiCheckCallStatus<E: Swift.Error>(
    callStatus: RustCallStatus, errorHandler: ((RustBuffer) throws -> E)?
) throws {
    switch callStatus.code {
        case CALL_SUCCESS: return
        case CALL_ERROR: if let errorHandler = errorHandler { throw try errorHandler(callStatus.errorBuf) } else {
                callStatus.errorBuf.deallocate()
                throw UniffiInternalError.unexpectedRustCallError
            }
        case CALL_UNEXPECTED_ERROR: if callStatus.errorBuf.len > 0 { throw UniffiInternalError.rustPanic(try FfiConverterString.lift(callStatus.errorBuf)) } else {
                callStatus.errorBuf.deallocate()
                throw UniffiInternalError.rustPanic("Rust panic")
            }
        case CALL_CANCELLED: fatalError("Cancellation not supported yet")
        default: throw UniffiInternalError.unexpectedRustCallStatusCode
    }
}
private func uniffiTraitInterfaceCall<T>(
    callStatus: UnsafeMutablePointer<RustCallStatus>, makeCall: () throws -> T, writeReturn: (T) -> ()
) {
    do {
        try writeReturn(makeCall())
    } catch let error {
        callStatus.pointee.code = CALL_UNEXPECTED_ERROR
        callStatus.pointee.errorBuf = FfiConverterString.lower(String(describing: error))
    }
}
private func uniffiTraitInterfaceCallWithError<T, E>(
    callStatus: UnsafeMutablePointer<RustCallStatus>, makeCall: () throws -> T, writeReturn: (T) -> (), lowerError: (E) -> RustBuffer
) {
    do {
        try writeReturn(makeCall())
    } catch let error as E {
        callStatus.pointee.code = CALL_ERROR
        callStatus.pointee.errorBuf = lowerError(error)
    } catch {
        callStatus.pointee.code = CALL_UNEXPECTED_ERROR
        callStatus.pointee.errorBuf = FfiConverterString.lower(String(describing: error))
    }
}
fileprivate final class UniffiHandleMap<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [UInt64: T] = [:]
    private var currentHandle: UInt64 = 1
    func insert(obj: T) -> UInt64 {
        lock.withLock {
            let handle = currentHandle
            currentHandle += 1
            map[handle] = obj
            return handle
        }}
     func get(handle: UInt64) throws -> T {
        try lock.withLock {
            guard let obj = map[handle] else { throw UniffiInternalError.unexpectedStaleHandle }
            return obj
        }}
    @discardableResult
    func remove(handle: UInt64) throws -> T {
        try lock.withLock {
            guard let obj = map.removeValue(forKey: handle) else { throw UniffiInternalError.unexpectedStaleHandle }
            return obj
        }}
    var count: Int {
        get {
            map.count
        }}
}
private let IDX_CALLBACK_FREE: Int32 = 0
private let UNIFFI_CALLBACK_SUCCESS: Int32 = 0
private let UNIFFI_CALLBACK_ERROR: Int32 = 1
private let UNIFFI_CALLBACK_UNEXPECTED_ERROR: Int32 = 2
fileprivate struct FfiConverterUInt32: FfiConverterPrimitive {
    typealias FfiType = UInt32
    typealias SwiftType = UInt32
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> UInt32 { return try lift(readInt(&buf)) }
    public static func write(_ value: SwiftType, into buf: inout [UInt8]) { writeInt(&buf, lower(value)) }
}
fileprivate struct FfiConverterUInt64: FfiConverterPrimitive {
    typealias FfiType = UInt64
    typealias SwiftType = UInt64
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> UInt64 { return try lift(readInt(&buf)) }
    public static func write(_ value: SwiftType, into buf: inout [UInt8]) { writeInt(&buf, lower(value)) }
}
fileprivate struct FfiConverterDouble: FfiConverterPrimitive {
    typealias FfiType = Double
    typealias SwiftType = Double
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> Double { return try lift(readDouble(&buf)) }
    public static func write(_ value: Double, into buf: inout [UInt8]) { writeDouble(&buf, lower(value)) }
}
fileprivate struct FfiConverterBool : FfiConverter {
    typealias FfiType = Int8
    typealias SwiftType = Bool
    public static func lift(_ value: Int8) throws -> Bool { return value != 0 }
    public static func lower(_ value: Bool) -> Int8 { return value ? 1 : 0 }
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> Bool { return try lift(readInt(&buf)) }
    public static func write(_ value: Bool, into buf: inout [UInt8]) { writeInt(&buf, lower(value)) }
}
fileprivate struct FfiConverterString: FfiConverter {
    typealias SwiftType = String
    typealias FfiType = RustBuffer
    public static func lift(_ value: RustBuffer) throws -> String {
        defer {
            value.deallocate()
        }
        if value.data == nil { return String() }
        let bytes = UnsafeBufferPointer<UInt8>(start: value.data!, count: Int(value.len))
        return String(bytes: bytes, encoding: String.Encoding.utf8)!
    }
    public static func lower(_ value: String) -> RustBuffer {
        return value.utf8CString.withUnsafeBufferPointer { ptr in
            ptr.withMemoryRebound(to: UInt8.self) { ptr in
                let buf = UnsafeBufferPointer(rebasing: ptr.prefix(upTo: ptr.count - 1))
                return RustBuffer.from(buf)
            }}}
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> String {
        let len: Int32 = try readInt(&buf)
        return String(bytes: try readBytes(&buf, count: Int(len)), encoding: String.Encoding.utf8)!
    }
    public static func write(_ value: String, into buf: inout [UInt8]) {
        let len = Int32(value.utf8.count)
        writeInt(&buf, len)
        writeBytes(&buf, value.utf8)
    }
}
fileprivate struct FfiConverterData: FfiConverterRustBuffer {
    typealias SwiftType = Data
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> Data {
        let len: Int32 = try readInt(&buf)
        return Data(try readBytes(&buf, count: Int(len)))
    }
    public static func write(_ value: Data, into buf: inout [UInt8]) {
        let len = Int32(value.count)
        writeInt(&buf, len)
        writeBytes(&buf, value)
    }
}
public protocol BalanceObserver: AnyObject, Sendable {
    func onBalanceUpdated(chainId: UInt32, walletId: String, balanceJson: String) 
    func onRefreshCycleComplete(refreshed: UInt32, errors: UInt32) 
}
open class BalanceObserverImpl: BalanceObserver, @unchecked Sendable {
    fileprivate let pointer: UnsafeMutableRawPointer!
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public struct NoPointer {
        public init() {}}
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    required public init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        self.pointer = pointer
    }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public init(noPointer: NoPointer) {
        self.pointer = nil
    }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public func uniffiClonePointer() -> UnsafeMutableRawPointer {
        return try! rustCall { uniffi_spectra_core_fn_clone_balanceobserver(self.pointer, $0) }}
    deinit {
        guard let pointer = pointer else { return }
        try! rustCall { uniffi_spectra_core_fn_free_balanceobserver(pointer, $0) }}
open func onBalanceUpdated(chainId: UInt32, walletId: String, balanceJson: String) { try! rustCall() { uniffi_spectra_core_fn_method_balanceobserver_on_balance_updated(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(walletId), FfiConverterString.lower(balanceJson),$0) } }
open func onRefreshCycleComplete(refreshed: UInt32, errors: UInt32) { try! rustCall() { uniffi_spectra_core_fn_method_balanceobserver_on_refresh_cycle_complete(self.uniffiClonePointer(), FfiConverterUInt32.lower(refreshed), FfiConverterUInt32.lower(errors),$0) } }
}
fileprivate struct UniffiCallbackInterfaceBalanceObserver {
    static let vtable: [UniffiVTableCallbackInterfaceBalanceObserver] = [UniffiVTableCallbackInterfaceBalanceObserver(
        onBalanceUpdated: { (
            uniffiHandle: UInt64, chainId: UInt32, walletId: RustBuffer, balanceJson: RustBuffer, uniffiOutReturn: UnsafeMutableRawPointer, uniffiCallStatus: UnsafeMutablePointer<RustCallStatus>
        ) in
            let makeCall = {
                () throws -> () in
                guard let uniffiObj = try? FfiConverterTypeBalanceObserver.handleMap.get(handle: uniffiHandle) else { throw UniffiInternalError.unexpectedStaleHandle }
                return uniffiObj.onBalanceUpdated(
                     chainId: try FfiConverterUInt32.lift(chainId), walletId: try FfiConverterString.lift(walletId), balanceJson: try FfiConverterString.lift(balanceJson)
                )
            }
            let writeReturn = { () }
            uniffiTraitInterfaceCall(
                callStatus: uniffiCallStatus, makeCall: makeCall, writeReturn: writeReturn
            )
        }, onRefreshCycleComplete: { (
            uniffiHandle: UInt64, refreshed: UInt32, errors: UInt32, uniffiOutReturn: UnsafeMutableRawPointer, uniffiCallStatus: UnsafeMutablePointer<RustCallStatus>
        ) in
            let makeCall = {
                () throws -> () in
                guard let uniffiObj = try? FfiConverterTypeBalanceObserver.handleMap.get(handle: uniffiHandle) else { throw UniffiInternalError.unexpectedStaleHandle }
                return uniffiObj.onRefreshCycleComplete(
                     refreshed: try FfiConverterUInt32.lift(refreshed), errors: try FfiConverterUInt32.lift(errors)
                )
            }
            let writeReturn = { () }
            uniffiTraitInterfaceCall(
                callStatus: uniffiCallStatus, makeCall: makeCall, writeReturn: writeReturn
            )
        }, uniffiFree: { (uniffiHandle: UInt64) -> () in
            let result = try? FfiConverterTypeBalanceObserver.handleMap.remove(handle: uniffiHandle)
            if result == nil { print("Uniffi callback interface BalanceObserver: handle missing in uniffiFree") }}
    )]
}
private func uniffiCallbackInitBalanceObserver() {
    uniffi_spectra_core_fn_init_callback_vtable_balanceobserver(UniffiCallbackInterfaceBalanceObserver.vtable)
}
public struct FfiConverterTypeBalanceObserver: FfiConverter {
    fileprivate static let handleMap = UniffiHandleMap<BalanceObserver>()
    typealias FfiType = UnsafeMutableRawPointer
    typealias SwiftType = BalanceObserver
    public static func lift(_ pointer: UnsafeMutableRawPointer) throws -> BalanceObserver { return BalanceObserverImpl(unsafeFromRawPointer: pointer) }
    public static func lower(_ value: BalanceObserver) -> UnsafeMutableRawPointer {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: UInt(truncatingIfNeeded: handleMap.insert(obj: value))) else { fatalError("Cast to UnsafeMutableRawPointer failed") }
        return ptr
    }
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> BalanceObserver {
        let v: UInt64 = try readInt(&buf)
        let ptr = UnsafeMutableRawPointer(bitPattern: UInt(truncatingIfNeeded: v))
        if (ptr == nil) { throw UniffiInternalError.unexpectedNullPointer }
        return try lift(ptr!)
    }
    public static func write(_ value: BalanceObserver, into buf: inout [UInt8]) { writeInt(&buf, UInt64(bitPattern: Int64(Int(bitPattern: lower(value))))) }
}
public func FfiConverterTypeBalanceObserver_lift(_ pointer: UnsafeMutableRawPointer) throws -> BalanceObserver {
    return try FfiConverterTypeBalanceObserver.lift(pointer)
}
public func FfiConverterTypeBalanceObserver_lower(_ value: BalanceObserver) -> UnsafeMutableRawPointer {
    return FfiConverterTypeBalanceObserver.lower(value)
}
public protocol BalanceRefreshEngineProtocol: AnyObject, Sendable {
    func clearObserver() 
    func setEntries(entriesJson: String) 
    func setObserver(observer: BalanceObserver) 
    func start(intervalSecs: UInt64) async 
    func stop() 
    func triggerImmediate() async 
}
open class BalanceRefreshEngine: BalanceRefreshEngineProtocol, @unchecked Sendable {
    fileprivate let pointer: UnsafeMutableRawPointer!
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public struct NoPointer {
        public init() {}}
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    required public init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        self.pointer = pointer
    }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public init(noPointer: NoPointer) {
        self.pointer = nil
    }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public func uniffiClonePointer() -> UnsafeMutableRawPointer {
        return try! rustCall { uniffi_spectra_core_fn_clone_balancerefreshengine(self.pointer, $0) }}
public convenience init(walletService: WalletService) {
    let pointer =
        try! rustCall() {
    uniffi_spectra_core_fn_constructor_balancerefreshengine_new(FfiConverterTypeWalletService_lower(walletService),$0)
}
    self.init(unsafeFromRawPointer: pointer)
}
    deinit {
        guard let pointer = pointer else { return }
        try! rustCall { uniffi_spectra_core_fn_free_balancerefreshengine(pointer, $0) }}
open func clearObserver() { try! rustCall() { uniffi_spectra_core_fn_method_balancerefreshengine_clear_observer(self.uniffiClonePointer(),$0) } }
open func setEntries(entriesJson: String) { try! rustCall() { uniffi_spectra_core_fn_method_balancerefreshengine_set_entries(self.uniffiClonePointer(), FfiConverterString.lower(entriesJson),$0) } }
open func setObserver(observer: BalanceObserver) { try! rustCall() { uniffi_spectra_core_fn_method_balancerefreshengine_set_observer(self.uniffiClonePointer(), FfiConverterTypeBalanceObserver_lower(observer),$0) } }
open func start(intervalSecs: UInt64)async { return try! await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_balancerefreshengine_start(self.uniffiClonePointer(), FfiConverterUInt64.lower(intervalSecs)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: nil) }
open func stop() { try! rustCall() { uniffi_spectra_core_fn_method_balancerefreshengine_stop(self.uniffiClonePointer(),$0) } }
open func triggerImmediate()async { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_balancerefreshengine_trigger_immediate(self.uniffiClonePointer()) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: nil) } }
public struct FfiConverterTypeBalanceRefreshEngine: FfiConverter {
    typealias FfiType = UnsafeMutableRawPointer
    typealias SwiftType = BalanceRefreshEngine
    public static func lift(_ pointer: UnsafeMutableRawPointer) throws -> BalanceRefreshEngine { return BalanceRefreshEngine(unsafeFromRawPointer: pointer) }
    public static func lower(_ value: BalanceRefreshEngine) -> UnsafeMutableRawPointer { return value.uniffiClonePointer() }
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> BalanceRefreshEngine {
        let v: UInt64 = try readInt(&buf)
        let ptr = UnsafeMutableRawPointer(bitPattern: UInt(truncatingIfNeeded: v))
        if (ptr == nil) { throw UniffiInternalError.unexpectedNullPointer }
        return try lift(ptr!)
    }
    public static func write(_ value: BalanceRefreshEngine, into buf: inout [UInt8]) { writeInt(&buf, UInt64(bitPattern: Int64(Int(bitPattern: lower(value))))) }
}
public func FfiConverterTypeBalanceRefreshEngine_lift(_ pointer: UnsafeMutableRawPointer) throws -> BalanceRefreshEngine {
    return try FfiConverterTypeBalanceRefreshEngine.lift(pointer)
}
public func FfiConverterTypeBalanceRefreshEngine_lower(_ value: BalanceRefreshEngine) -> UnsafeMutableRawPointer {
    return FfiConverterTypeBalanceRefreshEngine.lower(value)
}
public protocol SecretStore: AnyObject, Sendable {
    func loadSecret(key: String)  -> String? func saveSecret(key: String, value: String)  -> Bool
    func deleteSecret(key: String)  -> Bool
    func listKeys(prefixFilter: String)  -> [String]
}
open class SecretStoreImpl: SecretStore, @unchecked Sendable {
    fileprivate let pointer: UnsafeMutableRawPointer!
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public struct NoPointer {
        public init() {}}
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    required public init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        self.pointer = pointer
    }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public init(noPointer: NoPointer) {
        self.pointer = nil
    }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public func uniffiClonePointer() -> UnsafeMutableRawPointer {
        return try! rustCall { uniffi_spectra_core_fn_clone_secretstore(self.pointer, $0) }}
    deinit {
        guard let pointer = pointer else { return }
        try! rustCall { uniffi_spectra_core_fn_free_secretstore(pointer, $0) }}
open func loadSecret(key: String) -> String?  {
    return try!  FfiConverterOptionString.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_secretstore_load_secret(self.uniffiClonePointer(), FfiConverterString.lower(key),$0)
})
}
open func saveSecret(key: String, value: String) -> Bool  {
    return try!  FfiConverterBool.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_secretstore_save_secret(self.uniffiClonePointer(), FfiConverterString.lower(key), FfiConverterString.lower(value),$0)
})
}
open func deleteSecret(key: String) -> Bool  {
    return try!  FfiConverterBool.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_secretstore_delete_secret(self.uniffiClonePointer(), FfiConverterString.lower(key),$0)
})
}
open func listKeys(prefixFilter: String) -> [String]  {
    return try!  FfiConverterSequenceString.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_secretstore_list_keys(self.uniffiClonePointer(), FfiConverterString.lower(prefixFilter),$0)
})
}
}
fileprivate struct UniffiCallbackInterfaceSecretStore {
    static let vtable: [UniffiVTableCallbackInterfaceSecretStore] = [UniffiVTableCallbackInterfaceSecretStore(
        loadSecret: { (
            uniffiHandle: UInt64, key: RustBuffer, uniffiOutReturn: UnsafeMutablePointer<RustBuffer>, uniffiCallStatus: UnsafeMutablePointer<RustCallStatus>
        ) in
            let makeCall = {
                () throws -> String? in
                guard let uniffiObj = try? FfiConverterTypeSecretStore.handleMap.get(handle: uniffiHandle) else { throw UniffiInternalError.unexpectedStaleHandle }
                return uniffiObj.loadSecret(
                     key: try FfiConverterString.lift(key)
                )
            }
            let writeReturn = { uniffiOutReturn.pointee = FfiConverterOptionString.lower($0) }
            uniffiTraitInterfaceCall(
                callStatus: uniffiCallStatus, makeCall: makeCall, writeReturn: writeReturn
            )
        }, saveSecret: { (
            uniffiHandle: UInt64, key: RustBuffer, value: RustBuffer, uniffiOutReturn: UnsafeMutablePointer<Int8>, uniffiCallStatus: UnsafeMutablePointer<RustCallStatus>
        ) in
            let makeCall = {
                () throws -> Bool in
                guard let uniffiObj = try? FfiConverterTypeSecretStore.handleMap.get(handle: uniffiHandle) else { throw UniffiInternalError.unexpectedStaleHandle }
                return uniffiObj.saveSecret(
                     key: try FfiConverterString.lift(key), value: try FfiConverterString.lift(value)
                )
            }
            let writeReturn = { uniffiOutReturn.pointee = FfiConverterBool.lower($0) }
            uniffiTraitInterfaceCall(
                callStatus: uniffiCallStatus, makeCall: makeCall, writeReturn: writeReturn
            )
        }, deleteSecret: { (
            uniffiHandle: UInt64, key: RustBuffer, uniffiOutReturn: UnsafeMutablePointer<Int8>, uniffiCallStatus: UnsafeMutablePointer<RustCallStatus>
        ) in
            let makeCall = {
                () throws -> Bool in
                guard let uniffiObj = try? FfiConverterTypeSecretStore.handleMap.get(handle: uniffiHandle) else { throw UniffiInternalError.unexpectedStaleHandle }
                return uniffiObj.deleteSecret(
                     key: try FfiConverterString.lift(key)
                )
            }
            let writeReturn = { uniffiOutReturn.pointee = FfiConverterBool.lower($0) }
            uniffiTraitInterfaceCall(
                callStatus: uniffiCallStatus, makeCall: makeCall, writeReturn: writeReturn
            )
        }, listKeys: { (
            uniffiHandle: UInt64, prefixFilter: RustBuffer, uniffiOutReturn: UnsafeMutablePointer<RustBuffer>, uniffiCallStatus: UnsafeMutablePointer<RustCallStatus>
        ) in
            let makeCall = {
                () throws -> [String] in
                guard let uniffiObj = try? FfiConverterTypeSecretStore.handleMap.get(handle: uniffiHandle) else { throw UniffiInternalError.unexpectedStaleHandle }
                return uniffiObj.listKeys(
                     prefixFilter: try FfiConverterString.lift(prefixFilter)
                )
            }
            let writeReturn = { uniffiOutReturn.pointee = FfiConverterSequenceString.lower($0) }
            uniffiTraitInterfaceCall(
                callStatus: uniffiCallStatus, makeCall: makeCall, writeReturn: writeReturn
            )
        }, uniffiFree: { (uniffiHandle: UInt64) -> () in
            let result = try? FfiConverterTypeSecretStore.handleMap.remove(handle: uniffiHandle)
            if result == nil { print("Uniffi callback interface SecretStore: handle missing in uniffiFree") }}
    )]
}
private func uniffiCallbackInitSecretStore() {
    uniffi_spectra_core_fn_init_callback_vtable_secretstore(UniffiCallbackInterfaceSecretStore.vtable)
}
public struct FfiConverterTypeSecretStore: FfiConverter {
    fileprivate static let handleMap = UniffiHandleMap<SecretStore>()
    typealias FfiType = UnsafeMutableRawPointer
    typealias SwiftType = SecretStore
    public static func lift(_ pointer: UnsafeMutableRawPointer) throws -> SecretStore { return SecretStoreImpl(unsafeFromRawPointer: pointer) }
    public static func lower(_ value: SecretStore) -> UnsafeMutableRawPointer {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: UInt(truncatingIfNeeded: handleMap.insert(obj: value))) else { fatalError("Cast to UnsafeMutableRawPointer failed") }
        return ptr
    }
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> SecretStore {
        let v: UInt64 = try readInt(&buf)
        let ptr = UnsafeMutableRawPointer(bitPattern: UInt(truncatingIfNeeded: v))
        if (ptr == nil) { throw UniffiInternalError.unexpectedNullPointer }
        return try lift(ptr!)
    }
    public static func write(_ value: SecretStore, into buf: inout [UInt8]) { writeInt(&buf, UInt64(bitPattern: Int64(Int(bitPattern: lower(value))))) }
}
public func FfiConverterTypeSecretStore_lift(_ pointer: UnsafeMutableRawPointer) throws -> SecretStore {
    return try FfiConverterTypeSecretStore.lift(pointer)
}
public func FfiConverterTypeSecretStore_lower(_ value: SecretStore) -> UnsafeMutableRawPointer {
    return FfiConverterTypeSecretStore.lower(value)
}
public protocol SendStateMachineProtocol: AnyObject, Sendable {
    func applyEvent(eventJson: String) throws  -> String
    func currentStateJson() throws  -> String
    func reset() 
}
open class SendStateMachine: SendStateMachineProtocol, @unchecked Sendable {
    fileprivate let pointer: UnsafeMutableRawPointer!
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public struct NoPointer {
        public init() {}}
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    required public init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        self.pointer = pointer
    }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public init(noPointer: NoPointer) {
        self.pointer = nil
    }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public func uniffiClonePointer() -> UnsafeMutableRawPointer {
        return try! rustCall { uniffi_spectra_core_fn_clone_sendstatemachine(self.pointer, $0) }}
public convenience init() {
    let pointer =
        try! rustCall() { uniffi_spectra_core_fn_constructor_sendstatemachine_new($0  ) }
    self.init(unsafeFromRawPointer: pointer)
}
    deinit {
        guard let pointer = pointer else { return }
        try! rustCall { uniffi_spectra_core_fn_free_sendstatemachine(pointer, $0) }}
open func applyEvent(eventJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_method_sendstatemachine_apply_event(self.uniffiClonePointer(), FfiConverterString.lower(eventJson),$0)
})
}
open func currentStateJson()throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_method_sendstatemachine_current_state_json(self.uniffiClonePointer(),$0)
})
}
open func reset() { try! rustCall() { uniffi_spectra_core_fn_method_sendstatemachine_reset(self.uniffiClonePointer(),$0) } }
}
public struct FfiConverterTypeSendStateMachine: FfiConverter {
    typealias FfiType = UnsafeMutableRawPointer
    typealias SwiftType = SendStateMachine
    public static func lift(_ pointer: UnsafeMutableRawPointer) throws -> SendStateMachine { return SendStateMachine(unsafeFromRawPointer: pointer) }
    public static func lower(_ value: SendStateMachine) -> UnsafeMutableRawPointer { return value.uniffiClonePointer() }
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> SendStateMachine {
        let v: UInt64 = try readInt(&buf)
        let ptr = UnsafeMutableRawPointer(bitPattern: UInt(truncatingIfNeeded: v))
        if (ptr == nil) { throw UniffiInternalError.unexpectedNullPointer }
        return try lift(ptr!)
    }
    public static func write(_ value: SendStateMachine, into buf: inout [UInt8]) { writeInt(&buf, UInt64(bitPattern: Int64(Int(bitPattern: lower(value))))) }
}
public func FfiConverterTypeSendStateMachine_lift(_ pointer: UnsafeMutableRawPointer) throws -> SendStateMachine {
    return try FfiConverterTypeSendStateMachine.lift(pointer)
}
public func FfiConverterTypeSendStateMachine_lower(_ value: SendStateMachine) -> UnsafeMutableRawPointer {
    return FfiConverterTypeSendStateMachine.lower(value)
}
public protocol WalletServiceProtocol: AnyObject, Sendable {
    func advanceHistoryCursor(chainId: UInt32, walletId: String, nextCursor: String?) 
    func advanceHistoryPage(chainId: UInt32, walletId: String, isLast: Bool) 
    func applyNativeAmountInternal(walletId: String, chainId: UInt32, amount: Double) async throws  -> String? func broadcastRaw(chainId: UInt32, payload: String) async throws  -> String
    func cacheBalance(chainId: UInt32, address: String, balanceJson: String) 
    func cacheHistory(chainId: UInt32, address: String, historyJson: String) 
    func cachedBalance(chainId: UInt32, address: String)  -> String? func cachedHistory(chainId: UInt32, address: String)  -> String? func deleteKeypoolForChain(dbPath: String, chainName: String) async throws 
    func deleteKeypoolForWallet(dbPath: String, walletId: String) async throws 
    func deleteOwnedAddressesForChain(dbPath: String, chainName: String) async throws 
    func deleteOwnedAddressesForWallet(dbPath: String, walletId: String) async throws 
    func deleteSecret(key: String)  -> Bool
    func deleteWalletRelationalData(dbPath: String, walletId: String) async throws 
    func deriveBitcoinAccountXpub(mnemonicPhrase: String, passphrase: String, accountPath: String) throws  -> String
    func deriveBitcoinHdAddresses(xpub: String, change: UInt32, startIndex: UInt32, count: UInt32) async throws  -> String
    func evictExpiredBalanceCache() 
    func fetchBalance(chainId: UInt32, address: String) async throws  -> String
    func fetchBalanceAuto(chainId: UInt32, address: String) async throws  -> String
    func fetchBalanceCached(chainId: UInt32, address: String) async throws  -> String
    func fetchBitcoinNextUnusedAddress(xpub: String, change: UInt32, gapLimit: UInt32) async throws  -> String
    func fetchBitcoinXpubBalance(xpub: String, receiveCount: UInt32, changeCount: UInt32) async throws  -> String
    func fetchEvmCode(chainId: UInt32, address: String) async throws  -> String
    func fetchEvmHistoryPage(chainId: UInt32, address: String, tokensJson: String, page: UInt32, pageSize: UInt32) async throws  -> String
    func fetchEvmReceipt(chainId: UInt32, txHash: String) async throws  -> String
    func fetchEvmSendPreview(chainId: UInt32, from: String, to: String, valueWei: String, dataHex: String) async throws  -> String
    func fetchEvmTokenBalancesBatch(chainId: UInt32, address: String, tokensJson: String) async throws  -> String
    func fetchEvmTxNonce(chainId: UInt32, txHash: String) async throws  -> String
    func fetchFeeEstimate(chainId: UInt32) async throws  -> String
    func fetchFiatRates(provider: String, currenciesJson: String) async throws  -> String
    func fetchHistory(chainId: UInt32, address: String) async throws  -> String
    func fetchHistoryCached(chainId: UInt32, address: String) async throws  -> String
    func fetchPrices(provider: String, coinsJson: String, apiKey: String) async throws  -> String
    func fetchTokenBalance(chainId: UInt32, paramsJson: String) async throws  -> String
    func fetchTokenBalances(chainId: UInt32, address: String, tokensJson: String) async throws  -> String
    func fetchTronSendPreview(address: String, symbol: String, contractAddress: String) async throws  -> String
    func fetchUtxoFeePreview(chainId: UInt32, address: String, feeRateSvb: UInt64) async throws  -> String
    func fetchUtxoTxStatus(chainId: UInt32, txid: String) async throws  -> String
    func historyNextCursor(chainId: UInt32, walletId: String)  -> String? func historyNextPage(chainId: UInt32, walletId: String)  -> UInt32
    func initWalletState(walletsJson: String) async throws 
    func invalidateCachedBalance(chainId: UInt32, address: String) 
    func invalidateCachedHistory(chainId: UInt32, address: String) 
    func isHistoryExhausted(chainId: UInt32, walletId: String)  -> Bool
    func listBuiltinTokens(chainId: UInt32) async throws  -> String
    func listSecretKeys(prefixFilter: String)  -> [String]
    func listWalletsJson() async throws  -> String
    func loadAllKeypoolState(dbPath: String) async throws  -> String
    func loadAllOwnedAddresses(dbPath: String) async throws  -> String
    func loadAppSettings(dbPath: String) async throws  -> String
    func loadKeypoolState(dbPath: String, walletId: String, chainName: String) async throws  -> String? func loadOwnedAddresses(dbPath: String, walletId: String, chainName: String) async throws  -> String
    func loadSecret(key: String)  -> String? func loadState(dbPath: String, key: String) async throws  -> String
    func loadWalletSnapshot(dbPath: String) async throws  -> String
    func removeWalletJson(walletId: String) async throws  -> String
    func resetAllHistory() 
    func resetHistory(chainId: UInt32, walletId: String) 
    func resetHistoryForChain(chainId: UInt32) 
    func resetHistoryForWallet(walletId: String) 
    func resolveEnsName(name: String) async throws  -> String
    func saveAppSettings(dbPath: String, settingsJson: String) async throws 
    func saveKeypoolState(dbPath: String, walletId: String, chainName: String, stateJson: String) async throws 
    func saveOwnedAddress(dbPath: String, recordJson: String) async throws 
    func saveSecret(key: String, value: String)  -> Bool
    func saveState(dbPath: String, key: String, stateJson: String) async throws 
    func saveWalletSnapshot(dbPath: String, snapshotJson: String) async throws 
    func setHistoryExhausted(chainId: UInt32, walletId: String, exhausted: Bool) 
    func setHistoryPage(chainId: UInt32, walletId: String, page: UInt32) 
    func setNativeBalance(walletId: String, chainId: UInt32, amount: Double) async throws  -> String? func setSecretStore(store: SecretStore) 
    func signAndSend(chainId: UInt32, paramsJson: String) async throws  -> String
    func signAndSendToken(chainId: UInt32, paramsJson: String) async throws  -> String
    func updateEndpoints(endpointsJson: String) async throws 
    func updateNativeBalance(walletId: String, chainId: UInt32, balanceJson: String) async throws  -> String? func upsertWalletJson(walletJson: String) async throws  -> String
}
open class WalletService: WalletServiceProtocol, @unchecked Sendable {
    fileprivate let pointer: UnsafeMutableRawPointer!
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public struct NoPointer {
        public init() {}}
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    required public init(unsafeFromRawPointer pointer: UnsafeMutableRawPointer) {
        self.pointer = pointer
    }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public init(noPointer: NoPointer) {
        self.pointer = nil
    }
#if swift(>=5.8)
    @_documentation(visibility: private)
#endif
    public func uniffiClonePointer() -> UnsafeMutableRawPointer {
        return try! rustCall { uniffi_spectra_core_fn_clone_walletservice(self.pointer, $0) }}
public convenience init(endpointsJson: String)throws {
    let pointer =
        try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_constructor_walletservice_new(FfiConverterString.lower(endpointsJson),$0)
}
    self.init(unsafeFromRawPointer: pointer)
}
    deinit {
        guard let pointer = pointer else { return }
        try! rustCall { uniffi_spectra_core_fn_free_walletservice(pointer, $0) }}
open func advanceHistoryCursor(chainId: UInt32, walletId: String, nextCursor: String?) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_advance_history_cursor(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(walletId), FfiConverterOptionString.lower(nextCursor),$0) } }
open func advanceHistoryPage(chainId: UInt32, walletId: String, isLast: Bool) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_advance_history_page(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(walletId), FfiConverterBool.lower(isLast),$0) } }
open func applyNativeAmountInternal(walletId: String, chainId: UInt32, amount: Double)async throws  -> String?  { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_apply_native_amount_internal(self.uniffiClonePointer(), FfiConverterString.lower(walletId),FfiConverterUInt32.lower(chainId),FfiConverterDouble.lower(amount)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterOptionString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func broadcastRaw(chainId: UInt32, payload: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_broadcast_raw(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(payload)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func cacheBalance(chainId: UInt32, address: String, balanceJson: String) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_cache_balance(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(address), FfiConverterString.lower(balanceJson),$0) } }
open func cacheHistory(chainId: UInt32, address: String, historyJson: String) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_cache_history(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(address), FfiConverterString.lower(historyJson),$0) } }
open func cachedBalance(chainId: UInt32, address: String) -> String?  {
    return try!  FfiConverterOptionString.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_walletservice_cached_balance(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(address),$0)
})
}
open func cachedHistory(chainId: UInt32, address: String) -> String?  {
    return try!  FfiConverterOptionString.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_walletservice_cached_history(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(address),$0)
})
}
open func deleteKeypoolForChain(dbPath: String, chainName: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_delete_keypool_for_chain(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(chainName)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func deleteKeypoolForWallet(dbPath: String, walletId: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_delete_keypool_for_wallet(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(walletId)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func deleteOwnedAddressesForChain(dbPath: String, chainName: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_delete_owned_addresses_for_chain(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(chainName)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func deleteOwnedAddressesForWallet(dbPath: String, walletId: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_delete_owned_addresses_for_wallet(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(walletId)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func deleteSecret(key: String) -> Bool  {
    return try!  FfiConverterBool.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_walletservice_delete_secret(self.uniffiClonePointer(), FfiConverterString.lower(key),$0)
})
}
open func deleteWalletRelationalData(dbPath: String, walletId: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_delete_wallet_relational_data(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(walletId)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func deriveBitcoinAccountXpub(mnemonicPhrase: String, passphrase: String, accountPath: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_method_walletservice_derive_bitcoin_account_xpub(self.uniffiClonePointer(), FfiConverterString.lower(mnemonicPhrase), FfiConverterString.lower(passphrase), FfiConverterString.lower(accountPath),$0)
})
}
open func deriveBitcoinHdAddresses(xpub: String, change: UInt32, startIndex: UInt32, count: UInt32)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_derive_bitcoin_hd_addresses(self.uniffiClonePointer(), FfiConverterString.lower(xpub),FfiConverterUInt32.lower(change),FfiConverterUInt32.lower(startIndex),FfiConverterUInt32.lower(count)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func evictExpiredBalanceCache() { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_evict_expired_balance_cache(self.uniffiClonePointer(),$0) } }
open func fetchBalance(chainId: UInt32, address: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_balance(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(address)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchBalanceAuto(chainId: UInt32, address: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_balance_auto(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(address)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchBalanceCached(chainId: UInt32, address: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_balance_cached(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(address)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchBitcoinNextUnusedAddress(xpub: String, change: UInt32, gapLimit: UInt32)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_bitcoin_next_unused_address(self.uniffiClonePointer(), FfiConverterString.lower(xpub),FfiConverterUInt32.lower(change),FfiConverterUInt32.lower(gapLimit)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchBitcoinXpubBalance(xpub: String, receiveCount: UInt32, changeCount: UInt32)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_bitcoin_xpub_balance(self.uniffiClonePointer(), FfiConverterString.lower(xpub),FfiConverterUInt32.lower(receiveCount),FfiConverterUInt32.lower(changeCount)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchEvmCode(chainId: UInt32, address: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_evm_code(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(address)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchEvmHistoryPage(chainId: UInt32, address: String, tokensJson: String, page: UInt32, pageSize: UInt32)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_evm_history_page(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(address),FfiConverterString.lower(tokensJson),FfiConverterUInt32.lower(page),FfiConverterUInt32.lower(pageSize)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchEvmReceipt(chainId: UInt32, txHash: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_evm_receipt(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(txHash)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchEvmSendPreview(chainId: UInt32, from: String, to: String, valueWei: String, dataHex: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_evm_send_preview(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(from),FfiConverterString.lower(to),FfiConverterString.lower(valueWei),FfiConverterString.lower(dataHex)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchEvmTokenBalancesBatch(chainId: UInt32, address: String, tokensJson: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_evm_token_balances_batch(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(address),FfiConverterString.lower(tokensJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchEvmTxNonce(chainId: UInt32, txHash: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_evm_tx_nonce(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(txHash)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchFeeEstimate(chainId: UInt32)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_fee_estimate(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchFiatRates(provider: String, currenciesJson: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_fiat_rates(self.uniffiClonePointer(), FfiConverterString.lower(provider),FfiConverterString.lower(currenciesJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchHistory(chainId: UInt32, address: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_history(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(address)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchHistoryCached(chainId: UInt32, address: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_history_cached(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(address)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchPrices(provider: String, coinsJson: String, apiKey: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_prices(self.uniffiClonePointer(), FfiConverterString.lower(provider),FfiConverterString.lower(coinsJson),FfiConverterString.lower(apiKey)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchTokenBalance(chainId: UInt32, paramsJson: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_token_balance(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(paramsJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchTokenBalances(chainId: UInt32, address: String, tokensJson: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_token_balances(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(address),FfiConverterString.lower(tokensJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchTronSendPreview(address: String, symbol: String, contractAddress: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_tron_send_preview(self.uniffiClonePointer(), FfiConverterString.lower(address),FfiConverterString.lower(symbol),FfiConverterString.lower(contractAddress)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchUtxoFeePreview(chainId: UInt32, address: String, feeRateSvb: UInt64)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_utxo_fee_preview(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(address),FfiConverterUInt64.lower(feeRateSvb)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func fetchUtxoTxStatus(chainId: UInt32, txid: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_fetch_utxo_tx_status(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(txid)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func historyNextCursor(chainId: UInt32, walletId: String) -> String?  {
    return try!  FfiConverterOptionString.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_walletservice_history_next_cursor(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(walletId),$0)
})
}
open func historyNextPage(chainId: UInt32, walletId: String) -> UInt32  {
    return try!  FfiConverterUInt32.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_walletservice_history_next_page(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(walletId),$0)
})
}
open func initWalletState(walletsJson: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_init_wallet_state(self.uniffiClonePointer(), FfiConverterString.lower(walletsJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func invalidateCachedBalance(chainId: UInt32, address: String) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_invalidate_cached_balance(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(address),$0) } }
open func invalidateCachedHistory(chainId: UInt32, address: String) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_invalidate_cached_history(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(address),$0) } }
open func isHistoryExhausted(chainId: UInt32, walletId: String) -> Bool  {
    return try!  FfiConverterBool.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_walletservice_is_history_exhausted(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(walletId),$0)
})
}
open func listBuiltinTokens(chainId: UInt32)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_list_builtin_tokens(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func listSecretKeys(prefixFilter: String) -> [String]  {
    return try!  FfiConverterSequenceString.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_walletservice_list_secret_keys(self.uniffiClonePointer(), FfiConverterString.lower(prefixFilter),$0)
})
}
open func listWalletsJson()async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_list_wallets_json(self.uniffiClonePointer()) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func loadAllKeypoolState(dbPath: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_load_all_keypool_state(self.uniffiClonePointer(), FfiConverterString.lower(dbPath)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func loadAllOwnedAddresses(dbPath: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_load_all_owned_addresses(self.uniffiClonePointer(), FfiConverterString.lower(dbPath)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func loadAppSettings(dbPath: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_load_app_settings(self.uniffiClonePointer(), FfiConverterString.lower(dbPath)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func loadKeypoolState(dbPath: String, walletId: String, chainName: String)async throws  -> String?  { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_load_keypool_state(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(walletId),FfiConverterString.lower(chainName)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterOptionString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func loadOwnedAddresses(dbPath: String, walletId: String, chainName: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_load_owned_addresses(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(walletId),FfiConverterString.lower(chainName)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func loadSecret(key: String) -> String?  {
    return try!  FfiConverterOptionString.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_walletservice_load_secret(self.uniffiClonePointer(), FfiConverterString.lower(key),$0)
})
}
open func loadState(dbPath: String, key: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_load_state(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(key)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func loadWalletSnapshot(dbPath: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_load_wallet_snapshot(self.uniffiClonePointer(), FfiConverterString.lower(dbPath)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func removeWalletJson(walletId: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_remove_wallet_json(self.uniffiClonePointer(), FfiConverterString.lower(walletId)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func resetAllHistory() { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_reset_all_history(self.uniffiClonePointer(),$0) } }
open func resetHistory(chainId: UInt32, walletId: String) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_reset_history(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(walletId),$0) } }
open func resetHistoryForChain(chainId: UInt32) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_reset_history_for_chain(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),$0) } }
open func resetHistoryForWallet(walletId: String) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_reset_history_for_wallet(self.uniffiClonePointer(), FfiConverterString.lower(walletId),$0) } }
open func resolveEnsName(name: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_resolve_ens_name(self.uniffiClonePointer(), FfiConverterString.lower(name)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func saveAppSettings(dbPath: String, settingsJson: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_save_app_settings(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(settingsJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func saveKeypoolState(dbPath: String, walletId: String, chainName: String, stateJson: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_save_keypool_state(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(walletId),FfiConverterString.lower(chainName),FfiConverterString.lower(stateJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func saveOwnedAddress(dbPath: String, recordJson: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_save_owned_address(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(recordJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func saveSecret(key: String, value: String) -> Bool  {
    return try!  FfiConverterBool.lift(try! rustCall() {
    uniffi_spectra_core_fn_method_walletservice_save_secret(self.uniffiClonePointer(), FfiConverterString.lower(key), FfiConverterString.lower(value),$0)
})
}
open func saveState(dbPath: String, key: String, stateJson: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_save_state(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(key),FfiConverterString.lower(stateJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func saveWalletSnapshot(dbPath: String, snapshotJson: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_save_wallet_snapshot(self.uniffiClonePointer(), FfiConverterString.lower(dbPath),FfiConverterString.lower(snapshotJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func setHistoryExhausted(chainId: UInt32, walletId: String, exhausted: Bool) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_set_history_exhausted(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(walletId), FfiConverterBool.lower(exhausted),$0) } }
open func setHistoryPage(chainId: UInt32, walletId: String, page: UInt32) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_set_history_page(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId), FfiConverterString.lower(walletId), FfiConverterUInt32.lower(page),$0) } }
open func setNativeBalance(walletId: String, chainId: UInt32, amount: Double)async throws  -> String?  { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_set_native_balance(self.uniffiClonePointer(), FfiConverterString.lower(walletId),FfiConverterUInt32.lower(chainId),FfiConverterDouble.lower(amount)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterOptionString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func setSecretStore(store: SecretStore) { try! rustCall() { uniffi_spectra_core_fn_method_walletservice_set_secret_store(self.uniffiClonePointer(), FfiConverterTypeSecretStore_lower(store),$0) } }
open func signAndSend(chainId: UInt32, paramsJson: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_sign_and_send(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(paramsJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func signAndSendToken(chainId: UInt32, paramsJson: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_sign_and_send_token(self.uniffiClonePointer(), FfiConverterUInt32.lower(chainId),FfiConverterString.lower(paramsJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func updateEndpoints(endpointsJson: String)async throws { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_update_endpoints(self.uniffiClonePointer(), FfiConverterString.lower(endpointsJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_void, completeFunc: ffi_spectra_core_rust_future_complete_void, freeFunc: ffi_spectra_core_rust_future_free_void, liftFunc: { $0 }, errorHandler: FfiConverterTypeSpectraBridgeError_lift) }
open func updateNativeBalance(walletId: String, chainId: UInt32, balanceJson: String)async throws  -> String?  { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_update_native_balance(self.uniffiClonePointer(), FfiConverterString.lower(walletId),FfiConverterUInt32.lower(chainId),FfiConverterString.lower(balanceJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterOptionString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
open func upsertWalletJson(walletJson: String)async throws -> String { return try await uniffiRustCallAsync(rustFutureFunc: { uniffi_spectra_core_fn_method_walletservice_upsert_wallet_json(self.uniffiClonePointer(), FfiConverterString.lower(walletJson)) }, pollFunc: ffi_spectra_core_rust_future_poll_rust_buffer, completeFunc: ffi_spectra_core_rust_future_complete_rust_buffer, freeFunc: ffi_spectra_core_rust_future_free_rust_buffer, liftFunc: FfiConverterString.lift, errorHandler: FfiConverterTypeSpectraBridgeError_lift
        )
}
}
public struct FfiConverterTypeWalletService: FfiConverter {
    typealias FfiType = UnsafeMutableRawPointer
    typealias SwiftType = WalletService
    public static func lift(_ pointer: UnsafeMutableRawPointer) throws -> WalletService { return WalletService(unsafeFromRawPointer: pointer) }
    public static func lower(_ value: WalletService) -> UnsafeMutableRawPointer { return value.uniffiClonePointer() }
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> WalletService {
        let v: UInt64 = try readInt(&buf)
        let ptr = UnsafeMutableRawPointer(bitPattern: UInt(truncatingIfNeeded: v))
        if (ptr == nil) { throw UniffiInternalError.unexpectedNullPointer }
        return try lift(ptr!)
    }
    public static func write(_ value: WalletService, into buf: inout [UInt8]) { writeInt(&buf, UInt64(bitPattern: Int64(Int(bitPattern: lower(value))))) }
}
public func FfiConverterTypeWalletService_lift(_ pointer: UnsafeMutableRawPointer) throws -> WalletService {
    return try FfiConverterTypeWalletService.lift(pointer)
}
public func FfiConverterTypeWalletService_lower(_ value: WalletService) -> UnsafeMutableRawPointer {
    return FfiConverterTypeWalletService.lower(value)
}
public enum SpectraBridgeError: Swift.Error {
    case Failure(message: String  )
}
public struct FfiConverterTypeSpectraBridgeError: FfiConverterRustBuffer {
    typealias SwiftType = SpectraBridgeError
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> SpectraBridgeError {
        let variant: Int32 = try readInt(&buf)
        switch variant {
        case 1: return .Failure(
            message: try FfiConverterString.read(from: &buf)
            )
         default: throw UniffiInternalError.unexpectedEnumCase
        }}
    public static func write(_ value: SpectraBridgeError, into buf: inout [UInt8]) {
        switch value {
        case let .Failure(message): writeInt(&buf, Int32(1))
            FfiConverterString.write(message, into: &buf)
        }}
}
public func FfiConverterTypeSpectraBridgeError_lift(_ buf: RustBuffer) throws -> SpectraBridgeError {
    return try FfiConverterTypeSpectraBridgeError.lift(buf)
}
public func FfiConverterTypeSpectraBridgeError_lower(_ value: SpectraBridgeError) -> RustBuffer {
    return FfiConverterTypeSpectraBridgeError.lower(value)
}
extension SpectraBridgeError: Equatable, Hashable {}
extension SpectraBridgeError: Foundation.LocalizedError {
    public var errorDescription: String? { String(reflecting: self) }
}
fileprivate struct FfiConverterOptionString: FfiConverterRustBuffer {
    typealias SwiftType = String? public static func write(_ value: SwiftType, into buf: inout [UInt8]) {
        guard let value = value else {
            writeInt(&buf, Int8(0))
            return
        }
        writeInt(&buf, Int8(1))
        FfiConverterString.write(value, into: &buf)
    }
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> SwiftType {
        switch try readInt(&buf) as Int8 {
        case 0: return nil
        case 1: return try FfiConverterString.read(from: &buf)
        default: throw UniffiInternalError.unexpectedOptionalTag
        }}
}
fileprivate struct FfiConverterSequenceString: FfiConverterRustBuffer {
    typealias SwiftType = [String]
    public static func write(_ value: [String], into buf: inout [UInt8]) {
        let len = Int32(value.count)
        writeInt(&buf, len)
        for item in value { FfiConverterString.write(item, into: &buf) }}
    public static func read(from buf: inout (data: Data, offset: Data.Index)) throws -> [String] {
        let len: Int32 = try readInt(&buf)
        var seq = [String]()
        seq.reserveCapacity(Int(len))
        for _ in 0 ..< len { seq.append(try FfiConverterString.read(from: &buf)) }
        return seq
    }
}
private let UNIFFI_RUST_FUTURE_POLL_READY: Int8 = 0
private let UNIFFI_RUST_FUTURE_POLL_MAYBE_READY: Int8 = 1
fileprivate let uniffiContinuationHandleMap = UniffiHandleMap<UnsafeContinuation<Int8, Never>>()
fileprivate func uniffiRustCallAsync<F, T>(
    rustFutureFunc: () -> UInt64, pollFunc: (UInt64, @escaping UniffiRustFutureContinuationCallback, UInt64) -> (), completeFunc: (UInt64, UnsafeMutablePointer<RustCallStatus>) -> F, freeFunc: (UInt64) -> (), liftFunc: (F) throws -> T, errorHandler: ((RustBuffer) throws -> Swift.Error)?
) async throws -> T {
    uniffiEnsureSpectraDerivationInitialized()
    let rustFuture = rustFutureFunc()
    defer {
        freeFunc(rustFuture)
    }
    var pollResult: Int8;
    repeat {
        pollResult = await withUnsafeContinuation {
            pollFunc(
                rustFuture, uniffiFutureContinuationCallback, uniffiContinuationHandleMap.insert(obj: $0)
            )
        }
    } while pollResult != UNIFFI_RUST_FUTURE_POLL_READY
    return try liftFunc(makeRustCall( { completeFunc(rustFuture, $0) }, errorHandler: errorHandler
    ))
}
fileprivate func uniffiFutureContinuationCallback(handle: UInt64, pollResult: Int8) {
    if let continuation = try? uniffiContinuationHandleMap.remove(handle: handle) { continuation.resume(returning: pollResult) } else { print("uniffiFutureContinuationCallback invalid handle") }
}
public func appCoreAppChainDescriptorsJson()throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_app_chain_descriptors_json($0  )
})
}
public func appCoreBitcoinEsploraBaseUrlsJson(network: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_bitcoin_esplora_base_urls_json(FfiConverterString.lower(network),$0)
})
}
public func appCoreBitcoinWalletStoreDefaultBaseUrlsJson(network: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_bitcoin_wallet_store_default_base_urls_json(FfiConverterString.lower(network),$0)
})
}
public func appCoreBroadcastProviderOptionsJson(chainName: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_broadcast_provider_options_json(FfiConverterString.lower(chainName),$0)
})
}
public func appCoreChainBackendsJson()throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_chain_backends_json($0  )
})
}
public func appCoreChainPresetsJson()throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_chain_presets_json($0  )
})
}
public func appCoreDerivationPathsForPresetJson(accountIndex: UInt32)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_derivation_paths_for_preset_json(FfiConverterUInt32.lower(accountIndex),$0)
})
}
public func appCoreDiagnosticsChecksJson(chainName: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_diagnostics_checks_json(FfiConverterString.lower(chainName),$0)
})
}
public func appCoreEndpointForIdJson(id: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_endpoint_for_id_json(FfiConverterString.lower(id),$0)
})
}
public func appCoreEndpointRecordsForChainJson(chainName: String, roleMask: UInt32, settingsVisibleOnly: Bool)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_endpoint_records_for_chain_json(FfiConverterString.lower(chainName), FfiConverterUInt32.lower(roleMask), FfiConverterBool.lower(settingsVisibleOnly),$0)
})
}
public func appCoreEndpointRecordsJson()throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_endpoint_records_json($0  )
})
}
public func appCoreEndpointsForIdsJson(idsJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_endpoints_for_ids_json(FfiConverterString.lower(idsJson),$0)
})
}
public func appCoreEvmRpcEndpointsJson(chainName: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_evm_rpc_endpoints_json(FfiConverterString.lower(chainName),$0)
})
}
public func appCoreExplorerSupplementalEndpointsJson(chainName: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_explorer_supplemental_endpoints_json(FfiConverterString.lower(chainName),$0)
})
}
public func appCoreGroupedSettingsEntriesJson(chainName: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_grouped_settings_entries_json(FfiConverterString.lower(chainName),$0)
})
}
public func appCoreLiveChainNamesJson()throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_live_chain_names_json($0  )
})
}
public func appCoreRequestCompilationPresetsJson()throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_request_compilation_presets_json($0  )
})
}
public func appCoreResolveDerivationPathJson(chain: UInt32, derivationPath: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_resolve_derivation_path_json(FfiConverterUInt32.lower(chain), FfiConverterString.lower(derivationPath),$0)
})
}
public func appCoreTransactionExplorerEntryJson(chainName: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_app_core_transaction_explorer_entry_json(FfiConverterString.lower(chainName),$0)
})
}
public func bip39EnglishWordlist() -> String  {
    return try!  FfiConverterString.lift(try! rustCall() { uniffi_spectra_core_fn_func_bip39_english_wordlist($0  ) })
}
public func coreActiveMaintenancePlanJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_active_maintenance_plan_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreAggregateOwnedAddressesJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_aggregate_owned_addresses_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreBootstrapJson()throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_bootstrap_json($0  )
})
}
public func coreBuildPersistedSnapshotJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_build_persisted_snapshot_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreChainRefreshPlansJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_chain_refresh_plans_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreExportLegacyWalletStoreJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_export_legacy_wallet_store_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreHistoryRefreshPlansJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_history_refresh_plans_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreLocalizationDocumentJson(resourceName: String, preferredLocalesJson: String)throws -> Data {
    return try FfiConverterData.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_localization_document_json(FfiConverterString.lower(resourceName), FfiConverterString.lower(preferredLocalesJson),$0)
})
}
public func coreMergeBitcoinHistorySnapshotsJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_merge_bitcoin_history_snapshots_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreMergeTransactionsJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_merge_transactions_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreMigrateLegacyWalletStoreJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_migrate_legacy_wallet_store_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreNormalizeHistoryJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_normalize_history_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreOrderEndpointsByReliabilityJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_order_endpoints_by_reliability_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanBalanceRefreshHealthJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_balance_refresh_health_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanDogecoinRefreshTargetsJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_dogecoin_refresh_targets_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanEvmRefreshTargetsJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_evm_refresh_targets_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanReceiveSelectionJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_receive_selection_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanSelfSendConfirmationJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_self_send_confirmation_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanSendPreviewRoutingJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_send_preview_routing_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanSendSubmitPreflightJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_send_submit_preflight_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanStoreDerivedStateJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_store_derived_state_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanTransferAvailabilityJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_transfer_availability_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanUtxoPreviewJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_utxo_preview_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanUtxoSpendJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_utxo_spend_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanWalletBalanceRefreshJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_wallet_balance_refresh_json(FfiConverterString.lower(requestJson),$0)
})
}
public func corePlanWalletImportJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_plan_wallet_import_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreRecordEndpointAttemptJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_record_endpoint_attempt_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreReduceStateJson(stateJson: String, commandJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_reduce_state_json(FfiConverterString.lower(stateJson), FfiConverterString.lower(commandJson),$0)
})
}
public func coreRouteSendAssetJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_route_send_asset_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreShouldRunBackgroundMaintenanceJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_should_run_background_maintenance_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreStaticResourceJson(resourceName: String)throws -> Data {
    return try FfiConverterData.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_static_resource_json(FfiConverterString.lower(resourceName),$0)
})
}
public func coreStaticTextResourceUtf8(resourceName: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_static_text_resource_utf8(FfiConverterString.lower(resourceName),$0)
})
}
public func coreValidateAddressJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_validate_address_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreValidateStringIdentifierJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_validate_string_identifier_json(FfiConverterString.lower(requestJson),$0)
})
}
public func coreWalletSecretIndexJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_core_wallet_secret_index_json(FfiConverterString.lower(requestJson),$0)
})
}
public func derivationBuildMaterialFromPrivateKeyJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_derivation_build_material_from_private_key_json(FfiConverterString.lower(requestJson),$0)
})
}
public func derivationBuildMaterialJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_derivation_build_material_json(FfiConverterString.lower(requestJson),$0)
})
}
public func derivationDeriveAllAddressesJson(seedPhrase: String, chainPathsJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_derivation_derive_all_addresses_json(FfiConverterString.lower(seedPhrase), FfiConverterString.lower(chainPathsJson),$0)
})
}
public func derivationDeriveFromPrivateKeyJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_derivation_derive_from_private_key_json(FfiConverterString.lower(requestJson),$0)
})
}
public func derivationDeriveJson(requestJson: String)throws -> String {
    return try FfiConverterString.lift(try rustCallWithError(FfiConverterTypeSpectraBridgeError_lift) {
    uniffi_spectra_core_fn_func_derivation_derive_json(FfiConverterString.lower(requestJson),$0)
})
}
public func generateMnemonic(wordCount: UInt32) -> String  {
    return try!  FfiConverterString.lift(try! rustCall() {
    uniffi_spectra_core_fn_func_generate_mnemonic(FfiConverterUInt32.lower(wordCount),$0)
})
}
public func listBuiltinTokensJson(chainId: UInt32) -> String  {
    return try!  FfiConverterString.lift(try! rustCall() {
    uniffi_spectra_core_fn_func_list_builtin_tokens_json(FfiConverterUInt32.lower(chainId),$0)
})
}
public func validateMnemonic(phrase: String) -> Bool  {
    return try!  FfiConverterBool.lift(try! rustCall() {
    uniffi_spectra_core_fn_func_validate_mnemonic(FfiConverterString.lower(phrase),$0)
})
}
private enum InitializationResult {
    case ok
    case contractVersionMismatch
    case apiChecksumMismatch
}
private let initializationResult: InitializationResult = {
    let bindings_contract_version = 29
    let scaffolding_contract_version = ffi_spectra_core_uniffi_contract_version()
    if bindings_contract_version != scaffolding_contract_version { return InitializationResult.contractVersionMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_app_chain_descriptors_json() != 47342) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_bitcoin_esplora_base_urls_json() != 50813) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_bitcoin_wallet_store_default_base_urls_json() != 51452) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_broadcast_provider_options_json() != 55971) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_chain_backends_json() != 19839) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_chain_presets_json() != 6393) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_derivation_paths_for_preset_json() != 61113) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_diagnostics_checks_json() != 22292) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_endpoint_for_id_json() != 12350) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_endpoint_records_for_chain_json() != 45392) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_endpoint_records_json() != 61494) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_endpoints_for_ids_json() != 51423) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_evm_rpc_endpoints_json() != 39390) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_explorer_supplemental_endpoints_json() != 23382) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_grouped_settings_entries_json() != 51274) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_live_chain_names_json() != 32542) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_request_compilation_presets_json() != 50593) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_resolve_derivation_path_json() != 44674) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_app_core_transaction_explorer_entry_json() != 24637) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_bip39_english_wordlist() != 14036) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_active_maintenance_plan_json() != 27087) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_aggregate_owned_addresses_json() != 18759) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_bootstrap_json() != 64465) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_build_persisted_snapshot_json() != 44980) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_chain_refresh_plans_json() != 24361) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_export_legacy_wallet_store_json() != 11139) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_history_refresh_plans_json() != 60491) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_localization_document_json() != 65501) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_merge_bitcoin_history_snapshots_json() != 24244) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_merge_transactions_json() != 47208) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_migrate_legacy_wallet_store_json() != 64548) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_normalize_history_json() != 48086) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_order_endpoints_by_reliability_json() != 7156) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_balance_refresh_health_json() != 6941) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_dogecoin_refresh_targets_json() != 55537) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_evm_refresh_targets_json() != 47700) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_receive_selection_json() != 60395) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_self_send_confirmation_json() != 628) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_send_preview_routing_json() != 43864) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_send_submit_preflight_json() != 3857) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_store_derived_state_json() != 39225) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_transfer_availability_json() != 23034) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_utxo_preview_json() != 44907) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_utxo_spend_json() != 14746) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_wallet_balance_refresh_json() != 15428) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_plan_wallet_import_json() != 13086) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_record_endpoint_attempt_json() != 35418) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_reduce_state_json() != 25216) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_route_send_asset_json() != 57347) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_should_run_background_maintenance_json() != 49478) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_static_resource_json() != 26141) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_static_text_resource_utf8() != 44720) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_validate_address_json() != 51081) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_validate_string_identifier_json() != 721) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_core_wallet_secret_index_json() != 60671) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_derivation_build_material_from_private_key_json() != 61014) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_derivation_build_material_json() != 38055) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_derivation_derive_all_addresses_json() != 30725) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_derivation_derive_from_private_key_json() != 56242) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_derivation_derive_json() != 6641) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_generate_mnemonic() != 39172) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_list_builtin_tokens_json() != 30265) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_func_validate_mnemonic() != 27248) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_balanceobserver_on_balance_updated() != 53118) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_balanceobserver_on_refresh_cycle_complete() != 15795) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_balancerefreshengine_clear_observer() != 55697) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_balancerefreshengine_set_entries() != 10717) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_balancerefreshengine_set_observer() != 13622) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_balancerefreshengine_start() != 1780) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_balancerefreshengine_stop() != 35875) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_balancerefreshengine_trigger_immediate() != 32266) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_secretstore_load_secret() != 8153) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_secretstore_save_secret() != 55358) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_secretstore_delete_secret() != 49247) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_secretstore_list_keys() != 6647) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_sendstatemachine_apply_event() != 42159) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_sendstatemachine_current_state_json() != 36530) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_sendstatemachine_reset() != 40965) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_advance_history_cursor() != 9834) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_advance_history_page() != 39773) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_apply_native_amount_internal() != 47937) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_broadcast_raw() != 38543) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_cache_balance() != 63182) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_cache_history() != 48355) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_cached_balance() != 11298) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_cached_history() != 46360) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_delete_keypool_for_chain() != 51402) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_delete_keypool_for_wallet() != 36125) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_delete_owned_addresses_for_chain() != 32875) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_delete_owned_addresses_for_wallet() != 548) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_delete_secret() != 41759) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_delete_wallet_relational_data() != 50429) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_derive_bitcoin_account_xpub() != 47514) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_derive_bitcoin_hd_addresses() != 8315) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_evict_expired_balance_cache() != 28690) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_balance() != 63583) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_balance_auto() != 13111) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_balance_cached() != 2497) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_bitcoin_next_unused_address() != 59117) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_bitcoin_xpub_balance() != 14209) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_evm_code() != 60759) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_evm_history_page() != 20884) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_evm_receipt() != 22602) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_evm_send_preview() != 38832) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_evm_token_balances_batch() != 60573) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_evm_tx_nonce() != 5777) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_fee_estimate() != 54809) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_fiat_rates() != 2221) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_history() != 60708) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_history_cached() != 9674) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_prices() != 63918) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_token_balance() != 63267) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_token_balances() != 15634) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_tron_send_preview() != 52056) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_utxo_fee_preview() != 31374) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_fetch_utxo_tx_status() != 63431) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_history_next_cursor() != 57527) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_history_next_page() != 49091) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_init_wallet_state() != 42539) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_invalidate_cached_balance() != 26757) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_invalidate_cached_history() != 19770) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_is_history_exhausted() != 26898) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_list_builtin_tokens() != 46420) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_list_secret_keys() != 48708) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_list_wallets_json() != 40773) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_load_all_keypool_state() != 7734) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_load_all_owned_addresses() != 5452) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_load_app_settings() != 17220) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_load_keypool_state() != 59747) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_load_owned_addresses() != 62020) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_load_secret() != 7875) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_load_state() != 16054) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_load_wallet_snapshot() != 39295) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_remove_wallet_json() != 22014) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_reset_all_history() != 29033) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_reset_history() != 32130) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_reset_history_for_chain() != 61930) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_reset_history_for_wallet() != 41893) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_resolve_ens_name() != 38520) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_save_app_settings() != 49790) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_save_keypool_state() != 53908) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_save_owned_address() != 14657) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_save_secret() != 7030) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_save_state() != 39685) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_save_wallet_snapshot() != 53607) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_set_history_exhausted() != 59373) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_set_history_page() != 7406) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_set_native_balance() != 30501) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_set_secret_store() != 38476) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_sign_and_send() != 51633) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_sign_and_send_token() != 21782) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_update_endpoints() != 21147) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_update_native_balance() != 57088) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_method_walletservice_upsert_wallet_json() != 64861) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_constructor_balancerefreshengine_new() != 29789) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_constructor_sendstatemachine_new() != 17686) { return InitializationResult.apiChecksumMismatch }
    if (uniffi_spectra_core_checksum_constructor_walletservice_new() != 33034) { return InitializationResult.apiChecksumMismatch }
    uniffiCallbackInitBalanceObserver()
    uniffiCallbackInitSecretStore()
    return InitializationResult.ok
}()
public func uniffiEnsureSpectraDerivationInitialized() {
    switch initializationResult {
    case .ok: break
    case .contractVersionMismatch: fatalError("UniFFI contract version mismatch: try cleaning and rebuilding your project")
    case .apiChecksumMismatch: fatalError("UniFFI API checksum mismatch: try cleaning and rebuilding your project")
    }
}
// swiftlint:enable all