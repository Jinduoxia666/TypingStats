import CoreGraphics
import Foundation

final class ToolPanelKeyInterceptor {
    private let keyCodes: Set<Int64>
    private let handler: @MainActor (UInt16) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(keyCodes: Set<UInt16>, handler: @escaping @MainActor (UInt16) -> Void) {
        self.keyCodes = Set(keyCodes.map(Int64.init))
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: toolPanelKeyTapCallback,
            userInfo: refcon
        ) else {
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
    }

    fileprivate func handle(_ event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCodes.contains(keyCode) else { return false }
        Task { @MainActor in handler(UInt16(keyCode)) }
        return true
    }

    fileprivate func reEnable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

private func toolPanelKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let owner = Unmanaged<ToolPanelKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()

    switch type {
    case .keyDown:
        return owner.handle(event) ? nil : Unmanaged.passUnretained(event)
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        owner.reEnable()
        return Unmanaged.passUnretained(event)
    default:
        return Unmanaged.passUnretained(event)
    }
}
