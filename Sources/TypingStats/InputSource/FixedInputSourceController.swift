import Carbon
import Foundation

struct InputSourceOption: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor
final class FixedInputSourceController: ObservableObject {
    @Published private(set) var availableInputSources: [InputSourceOption] = []
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            if isEnabled {
                enforceSelection()
            }
        }
    }
    @Published var selectedInputSourceID: String {
        didSet {
            defaults.set(selectedInputSourceID, forKey: Keys.selectedInputSourceID)
            if isEnabled {
                enforceSelection()
            }
        }
    }

    private enum Keys {
        static let isEnabled = "fixedInputSourceEnabled"
        static let selectedInputSourceID = "fixedInputSourceID"
    }

    private let defaults: UserDefaults
    private var inputSourcesByID: [String: TISInputSource] = [:]
    private var selectedSourceObserver: NSObjectProtocol?
    private var enabledSourcesObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isEnabled = defaults.bool(forKey: Keys.isEnabled)
        self.selectedInputSourceID = defaults.string(forKey: Keys.selectedInputSourceID) ?? ""

        refreshInputSources()
        observeInputSourceChanges()
        if isEnabled {
            enforceSelection()
        }
    }

    deinit {
        if let selectedSourceObserver {
            DistributedNotificationCenter.default().removeObserver(selectedSourceObserver)
        }
        if let enabledSourcesObserver {
            DistributedNotificationCenter.default().removeObserver(enabledSourcesObserver)
        }
    }

    private func observeInputSourceChanges() {
        selectedSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.enforceSelection()
            }
        }

        enabledSourcesObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshInputSources()
                self?.enforceSelection()
            }
        }
    }

    private func refreshInputSources() {
        let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        let selectableSources = sources.filter {
            Self.stringProperty($0, key: kTISPropertyInputSourceCategory)
                == kTISCategoryKeyboardInputSource as String
                && Self.boolProperty($0, key: kTISPropertyInputSourceIsSelectCapable)
        }

        inputSourcesByID = Dictionary(
            uniqueKeysWithValues: selectableSources.compactMap { source in
                guard let id = Self.stringProperty(source, key: kTISPropertyInputSourceID) else {
                    return nil
                }
                return (id, source)
            }
        )

        availableInputSources = selectableSources.compactMap { source in
            guard let id = Self.stringProperty(source, key: kTISPropertyInputSourceID),
                  let name = Self.stringProperty(source, key: kTISPropertyLocalizedName) else {
                return nil
            }
            return InputSourceOption(id: id, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        if !inputSourcesByID.keys.contains(selectedInputSourceID),
           let currentID = Self.currentInputSourceID(),
           inputSourcesByID.keys.contains(currentID) {
            selectedInputSourceID = currentID
        }
    }

    private func enforceSelection() {
        guard isEnabled,
              Self.currentInputSourceID() != selectedInputSourceID,
              let inputSource = inputSourcesByID[selectedInputSourceID] else {
            return
        }
        TISSelectInputSource(inputSource)
    }

    private static func currentInputSourceID() -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        return stringProperty(source, key: kTISPropertyInputSourceID)
    }

    private static func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func boolProperty(_ source: TISInputSource, key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return false }
        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }
}
