import Foundation
import IOKit

struct CPUTemperatureReader {
    func readCelsius() -> Double? {
        guard let smc = SMCReader() else { return nil }
        defer { smc.close() }

        for key in ["TC0P", "TC0E", "TC0F", "TC0D", "TC0H"] {
            if let value = smc.readTemperature(key) {
                return value
            }
        }
        return nil
    }
}

private final class SMCReader {
    private var connection: io_connect_t = 0

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
    }

    func close() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    func readTemperature(_ key: String) -> Double? {
        guard var value = read(key), value.dataSize >= 2 else { return nil }

        let first = value.byte(at: 0)
        let second = value.byte(at: 1)

        switch string(from: value.dataType) {
        case "sp78":
            return Double(Int(first)) + Double(second) / 256.0
        case "flt ":
            guard value.dataSize >= 4 else { return nil }
            let bits = UInt32(first) << 24
                | UInt32(second) << 16
                | UInt32(value.byte(at: 2)) << 8
                | UInt32(value.byte(at: 3))
            return Double(Float(bitPattern: bits))
        default:
            return nil
        }
    }

    private func read(_ key: String) -> SMCValue? {
        let keyCode = fourCharCode(key)
        guard let keyInfo = readKeyInfo(keyCode) else { return nil }

        var input = SMCKeyData()
        var output = SMCKeyData()
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride

        input.key = keyCode
        input.keyInfo = keyInfo
        input.data8 = SMCCommand.readBytes.rawValue

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCSelector.call.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else { return nil }

        return SMCValue(
            key: keyCode,
            dataSize: keyInfo.dataSize,
            dataType: keyInfo.dataType,
            bytes: output.bytes
        )
    }

    private func readKeyInfo(_ key: UInt32) -> SMCKeyInfo? {
        var input = SMCKeyData()
        var output = SMCKeyData()
        let inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride

        input.key = key
        input.data8 = SMCCommand.readKeyInfo.rawValue

        let result = IOConnectCallStructMethod(
            connection,
            UInt32(SMCSelector.call.rawValue),
            &input,
            inputSize,
            &output,
            &outputSize
        )
        guard result == kIOReturnSuccess else { return nil }
        return output.keyInfo
    }
}

private enum SMCSelector: UInt8 {
    case call = 2
}

private enum SMCCommand: UInt8 {
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCPowerLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCVersion()
    var pLimitData = SMCPowerLimitData()
    var keyInfo = SMCKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes = SMCBytes()
}

private struct SMCValue {
    var key: UInt32
    var dataSize: UInt32
    var dataType: UInt32
    var bytes: SMCBytes

    mutating func byte(at index: Int) -> UInt8 {
        withUnsafeBytes(of: &bytes) { rawBuffer in
            rawBuffer[index]
        }
    }
}

private struct SMCBytes {
    var b0: UInt8 = 0
    var b1: UInt8 = 0
    var b2: UInt8 = 0
    var b3: UInt8 = 0
    var b4: UInt8 = 0
    var b5: UInt8 = 0
    var b6: UInt8 = 0
    var b7: UInt8 = 0
    var b8: UInt8 = 0
    var b9: UInt8 = 0
    var b10: UInt8 = 0
    var b11: UInt8 = 0
    var b12: UInt8 = 0
    var b13: UInt8 = 0
    var b14: UInt8 = 0
    var b15: UInt8 = 0
    var b16: UInt8 = 0
    var b17: UInt8 = 0
    var b18: UInt8 = 0
    var b19: UInt8 = 0
    var b20: UInt8 = 0
    var b21: UInt8 = 0
    var b22: UInt8 = 0
    var b23: UInt8 = 0
    var b24: UInt8 = 0
    var b25: UInt8 = 0
    var b26: UInt8 = 0
    var b27: UInt8 = 0
    var b28: UInt8 = 0
    var b29: UInt8 = 0
    var b30: UInt8 = 0
    var b31: UInt8 = 0
}

private func fourCharCode(_ string: String) -> UInt32 {
    var result: UInt32 = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + UInt32(scalar.value)
    }
    return result
}

private func string(from code: UInt32) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]
    return String(bytes: bytes, encoding: .ascii) ?? ""
}
