import Foundation

/// The timeline and button intents both execute inside this extension. Keeping
/// state here avoids granting the widget access to the host's typing history.
actor CalculatorWidgetStore {
    static let shared = CalculatorWidgetStore()
    private let key = "calculatorStateV1"

    func snapshot() -> CalculatorModel.Snapshot {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(CalculatorModel.Snapshot.self, from: data)
        else { return CalculatorModel().snapshot }
        return snapshot
    }

    func press(_ key: String) throws {
        let model = CalculatorModel(snapshot: snapshot())
        model.press(key)
        let data = try JSONEncoder().encode(model.snapshot)
        UserDefaults.standard.set(data, forKey: self.key)
        // WidgetKit reloads the timeline after an interactive intent completes.
    }
}
