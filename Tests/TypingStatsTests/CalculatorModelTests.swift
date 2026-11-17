import XCTest
@testable import TypingStats

final class CalculatorModelTests: XCTestCase {
    private func calculate(_ keys: [String]) -> CalculatorModel {
        let model = CalculatorModel()
        keys.forEach(model.press)
        return model
    }

    func testDecimalArithmetic() {
        XCTAssertEqual(calculate(["0", ".", "1", "+", "0", ".", "2", "="]).display, "0.3")
        XCTAssertEqual(calculate(["9", "−", "3", "="]).display, "6")
        XCTAssertEqual(calculate(["6", "×", "7", "="]).display, "42")
        XCTAssertEqual(calculate(["7", "÷", "2", "="]).display, "3.5")
    }

    func testPrecedenceAndOperatorReplacement() {
        XCTAssertEqual(calculate(["2", "+", "3", "×", "4", "="]).display, "14")
        XCTAssertEqual(calculate(["8", "+", "÷", "2", "="]).display, "4")
    }

    func testRepeatedEqualsAndFreshEntry() {
        let model = calculate(["2", "+", "3", "=", "="])
        XCTAssertEqual(model.display, "8")
        model.press("4")
        model.press("=")
        model.press("=")
        XCTAssertEqual(model.display, "4")
    }

    func testPercentage() {
        XCTAssertEqual(calculate(["2", "00", "+", "1", "0", "%", "="]).display, "220")
        XCTAssertEqual(calculate(["2", "00", "×", "1", "0", "%", "="]).display, "20")
        XCTAssertEqual(calculate(["5", "0", "%"]).display, "0.5")
    }

    func testEditingAndReset() {
        XCTAssertEqual(calculate(["1", "2", "⌫", ".", ".", "5", "±"]).display, "-1.5")
        XCTAssertEqual(calculate(["2", "+", "C", "3", "="]).display, "3")
        XCTAssertEqual(calculate(["00", "7", "00"]).display, "700")
    }

    func testDivisionByZeroRecovers() {
        let model = calculate(["8", "÷", "0", "="])
        XCTAssertEqual(model.display, "错误")
        model.press("7")
        XCTAssertEqual(model.display, "7")
        XCTAssertNil(model.operation)
    }

    func testWidgetRestoresEveryKeyAcrossProcesses() throws {
        var model = CalculatorModel()
        for key in ["1", ".", "5", "+", "2", "=", "="] {
            let data = try JSONEncoder().encode(model.snapshot)
            model = CalculatorModel(snapshot: try JSONDecoder().decode(CalculatorModel.Snapshot.self, from: data))
            model.press(key)
        }
        XCTAssertEqual(model.display, "5.5")
        XCTAssertEqual(model.expression, "(1.5 + 2) + 2 =")
    }

    func testExpressionDistinguishesRepeatedOperand() {
        let model = calculate(["9"])
        XCTAssertEqual(model.expression, "9")
        model.press("+")
        XCTAssertEqual(model.expression, "9 +")
        model.press("9")
        XCTAssertEqual(model.expression, "9 + 9")
        model.press("=")
        XCTAssertEqual(model.expression, "9 + 9 =")
        XCTAssertEqual(model.display, "18")
        model.press("4")
        XCTAssertEqual(model.expression, "4")
    }

    func testExpressionTracksEditingAndFullHistory() {
        let model = calculate(["9", "+", "1", "2", "⌫"])
        XCTAssertEqual(model.expression, "9 + 1")
        model.press("±")
        XCTAssertEqual(model.expression, "9 + -1")
        model.press("×")
        XCTAssertEqual(model.expression, "9 + -1 ×")
        model.press("÷")
        XCTAssertEqual(model.expression, "9 + -1 ÷")
        model.press("0")
        model.press("=")
        XCTAssertEqual(model.expression, "9 + -1 ÷ 0 =")
        XCTAssertEqual(model.display, "错误")
        model.press("C")
        XCTAssertEqual(model.expression, "0")
        XCTAssertEqual(calculate(["2", "00", "+", "1", "0", "%"]).expression, "200 + 20")
    }

    func testRestoresLegacyWidgetStateWithoutExpression() throws {
        let data = Data(#"{"display":"9","operation":"+","accumulator":9,"startsEntry":true}"#.utf8)
        let state = try JSONDecoder().decode(CalculatorModel.Snapshot.self, from: data)
        XCTAssertEqual(CalculatorModel(snapshot: state).expression, "9 +")
    }
    func testFullExpressionSurvivesOperatorsAndEquals() {
        let model = calculate(["9", "+", "9", "×", "2"])
        XCTAssertEqual(model.expression, "9 + 9 × 2")
        model.press("=")
        XCTAssertEqual(model.display, "27")
        XCTAssertEqual(model.expression, "9 + 9 × 2 =")
        model.press("×")
        model.press("2")
        model.press("=")
        XCTAssertEqual(model.display, "54")
        XCTAssertEqual(model.expression, "(9 + 9 × 2) × 2 =")
    }

    func testScientificFunctionsAndParentheses() {
        XCTAssertEqual(calculate(["(", "9", "+", "9", ")", "×", "2", "="]).display, "36")
        XCTAssertEqual(calculate(["2", "xʸ", "3", "xʸ", "2", "="]).display, "512")
        XCTAssertEqual(calculate(["9", "√", "="]).display, "3")
        XCTAssertEqual(calculate(["3", "x²", "="]).display, "9")
        XCTAssertEqual(calculate(["2", "1/x", "="]).display, "0.5")
        XCTAssertEqual(calculate(["1", "0", "0", "log", "="]).display, "2")
        XCTAssertEqual(calculate(["e", "ln", "="]).display, "1")
        XCTAssertEqual(calculate(["2", "10ˣ", "="]).display, "100")
        XCTAssertEqual(calculate(["0", "eˣ", "="]).display, "1")
    }

    func testAnglesAndFunctionEntry() {
        XCTAssertEqual(calculate(["3", "0", "sin", "="]).display, "0.5")
        XCTAssertEqual(calculate(["sin", "3", "0", "="]).display, "0.5")
        XCTAssertEqual(calculate(["6", "0", "cos", "="]).display, "0.5")
        XCTAssertEqual(calculate(["4", "5", "tan", "="]).display, "1")
        XCTAssertEqual(calculate(["DEG", "sin", "π", "÷", "2", ")", "="]).display, "1")
    }

    func testScientificDomainErrorsAndRecovery() {
        for keys in [["1", "±", "√"], ["0", "ln"], ["9", "0", "tan"], ["0", "1/x"], ["9", "9", "9", "eˣ"]] {
            let model = calculate(keys)
            XCTAssertEqual(model.display, "错误", "\(keys)")
            model.press("7")
            XCTAssertEqual(model.display, "7")
        }
    }

    func testModeSwitchAndWidgetStatePreserveExpression() throws {
        var model = calculate(["(", "9", "+", "9", ")", "×", "2", "SCI", "DEG"])
        let expression = model.expression
        let data = try JSONEncoder().encode(model.snapshot)
        model = CalculatorModel(snapshot: try JSONDecoder().decode(CalculatorModel.Snapshot.self, from: data))
        XCTAssertTrue(model.scientific)
        XCTAssertFalse(model.degrees)
        model.press("SCI")
        XCTAssertEqual(model.expression, expression)
        model.press("=")
        XCTAssertEqual(model.display, "36")
    }

    func testFunctionEditingAndResultPercent() {
        XCTAssertEqual(calculate(["sin", "⌫", "9", "="]).display, "9")
        XCTAssertEqual(calculate(["2", "00", "+", "2", "0", "=", "%"]).display, "2.2")
        let model = calculate(["sin", "2", "0", "+", "1", "0", ")", "="])
        model.press("=")
        XCTAssertEqual(model.display, "0.5")
    }

}
