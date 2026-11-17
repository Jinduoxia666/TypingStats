import Foundation
import Combine

final class CalculatorModel: ObservableObject {
    static let scientificKeys = ["(", ")", "xʸ", "x²", "√", "sin", "cos", "tan", "ln", "log", "π", "e", "1/x", "10ˣ", "eˣ"]
    @Published private(set) var display = "0"
    @Published private(set) var scientific = false
    @Published private(set) var degrees = true
    @Published private var tokens: [String] = []
    @Published private var finished = false
    private var editingNumber = false
    private var repeatOperation: String?
    private var repeatOperand: Decimal?
    var operation: String? { tokens.last.flatMap { CalculatorExpression.operators.contains($0) ? $0 : nil } }
    var expression: String { snapshot.expression }

    struct Snapshot: Codable {
        var display: String
        // Legacy fields remain decodable for already-installed widgets.
        var operation: String?
        var accumulator: Decimal?
        var startsEntry: Bool
        var repeatOperation: String?
        var repeatOperand: Decimal?
        var completedExpression: String?
        var tokens: [String]?
        var finished: Bool?
        var editingNumber: Bool?
        var scientific: Bool?
        var degrees: Bool?

        var expression: String {
            if let tokens {
                let text = tokens.isEmpty ? "0" : CalculatorExpression.text(tokens)
                return text + (finished == true ? " =" : "")
            }
            if let operation, let accumulator {
                let prefix = "\(NSDecimalNumber(decimal: accumulator).stringValue) \(operation)"
                return startsEntry ? prefix : "\(prefix) \(display)"
            }
            return completedExpression ?? display
        }
    }

    var snapshot: Snapshot {
        Snapshot(display: display, startsEntry: !editingNumber, repeatOperation: repeatOperation,
                 repeatOperand: repeatOperand, tokens: tokens, finished: finished,
                 editingNumber: editingNumber, scientific: scientific, degrees: degrees)
    }

    init(snapshot: Snapshot? = nil) {
        guard let snapshot else { return }
        display = snapshot.display
        scientific = snapshot.scientific ?? false
        degrees = snapshot.degrees ?? true
        repeatOperation = snapshot.repeatOperation
        repeatOperand = snapshot.repeatOperand
        if let saved = snapshot.tokens {
            tokens = saved
            finished = snapshot.finished ?? false
            editingNumber = snapshot.editingNumber ?? false
        } else if let op = snapshot.operation, let lhs = snapshot.accumulator {
            tokens = [NSDecimalNumber(decimal: lhs).stringValue, op]
            if !snapshot.startsEntry { tokens.append(display) }
            editingNumber = !snapshot.startsEntry
        } else {
            tokens = [display == "错误" ? "0" : display]
            finished = snapshot.startsEntry
            editingNumber = !snapshot.startsEntry
        }
    }

    func press(_ key: String) {
        if key == "SCI" { scientific.toggle(); return }
        if key == "DEG" { degrees.toggle(); return }
        if key == "C" { clear(); return }
        if display == "错误" { clear() }
        if tokens.count >= 240 && !["=", "⌫"].contains(key) { return }
        switch key {
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "00", ".": enterNumber(key)
        case "+", "−", "×", "÷", "xʸ", "^":
            if finished { tokens = ["("] + tokens + [")"]; finished = false }
            if tokens.isEmpty { tokens = ["0"] }
            let op = key == "xʸ" ? "^" : key
            if operation != nil { tokens[tokens.count - 1] = op }
            else if tokens.last != "(" { tokens.append(op) }
            editingNumber = false
            repeatOperation = nil
        case "(":
            startFreshIfFinished()
            if hasOperand { tokens.append("×") }
            tokens.append("(")
            editingNumber = false
        case ")":
            if hasOperand && balance > 0 { tokens.append(")"); editingNumber = false }
        case "π", "e":
            startFreshIfFinished()
            if hasOperand { tokens.append("×") }
            tokens.append(key)
            editingNumber = false
            previewOperand()
        case "⌫":
            if finished { clear(); return }
            guard !tokens.isEmpty else { return }
            if editingNumber, tokens.last!.count > 1 {
                tokens[tokens.count - 1].removeLast()
                if tokens.last == "-" { tokens[tokens.count - 1] = "0" }
            } else {
                let removed = tokens.removeLast()
                if removed == "(", let last = tokens.last, CalculatorExpression.functions.contains(last) {
                    tokens.removeLast()
                }
            }
            editingNumber = tokens.last.flatMap { Decimal(string: $0) } != nil
            display = editingNumber ? tokens.last! : "0"
        case "±":
            if editingNumber, let last = tokens.last {
                tokens[tokens.count - 1] = last.hasPrefix("-") ? String(last.dropFirst()) : "-" + last
                display = tokens.last!
            } else { applyFunction("neg") }
        case "%": percent()
        case "x²", "√", "sin", "cos", "tan", "ln", "log", "1/x", "10ˣ", "eˣ":
            let names = ["x²": "square", "1/x": "inv", "10ˣ": "pow10", "eˣ": "exp"]
            applyFunction(names[key] ?? key)
        case "=": evaluate()
        default: break
        }
    }

    private var balance: Int { tokens.filter { $0 == "(" }.count - tokens.filter { $0 == ")" }.count }
    private var hasOperand: Bool { !tokens.isEmpty && operation == nil && tokens.last != "(" && !CalculatorExpression.functions.contains(tokens.last!) }

    private func startFreshIfFinished() { if finished { clear() } }

    private func enterNumber(_ key: String) {
        startFreshIfFinished()
        if !editingNumber {
            if hasOperand { tokens.append("×") }
            tokens.append("0")
            editingNumber = true
        }
        var number = tokens.last!
        if key == "." {
            if !number.contains(".") { number += "." }
        } else {
            for digit in key where number.filter({ $0.isNumber }).count < 14 {
                if number == "0" { number = String(digit) }
                else if number == "-0" { number = "-" + String(digit) }
                else { number += String(digit) }
            }
        }
        tokens[tokens.count - 1] = number
        display = number
        repeatOperation = nil
    }

    private func operandStart() -> Int? {
        guard hasOperand else { return nil }
        var start = tokens.count - 1
        if tokens[start] == ")" {
            var depth = 1
            while start > 0 {
                start -= 1
                if tokens[start] == ")" { depth += 1 }
                if tokens[start] == "(" { depth -= 1 }
                if depth == 0 { break }
            }
            if start > 0, CalculatorExpression.functions.contains(tokens[start - 1]) { start -= 1 }
        }
        return start
    }

    private func applyFunction(_ function: String) {
        if finished { tokens = ["("] + tokens + [")"]; finished = false }
        if let start = operandStart() {
            tokens.insert(contentsOf: [function, "("], at: start)
            tokens.append(")")
            previewOperand()
        } else {
            tokens.append(contentsOf: [function, "("])
        }
        editingNumber = false
    }

    private func previewOperand() {
        guard let start = operandStart() else { return }
        var parser = CalculatorExpression(Array(tokens[start...]), degrees: degrees)
        do { display = CalculatorExpression.formatted(try parser.evaluate().value) }
        catch { display = "错误" }
    }

    private func percent() {
        if finished {
            tokens = ["("] + tokens + [")", "÷", "100"]
            finished = false
            evaluate()
            return
        }
        guard let start = operandStart() else { return }
        var operand = CalculatorExpression(Array(tokens[start...]), degrees: degrees)
        do {
            var value = try operand.evaluate().value / 100
            // Preserve pocket-calculator percentages for a simple a +/- b%.
            if start == 2, ["+", "−"].contains(tokens[1]), let lhs = Decimal(string: tokens[0]) { value *= lhs }
            let text = CalculatorExpression.formatted(value)
            tokens.replaceSubrange(start..., with: [text])
            display = text
            editingNumber = false
            finished = false
        } catch { display = "错误" }
    }

    private func evaluate() {
        if finished {
            guard let repeatOperation, let repeatOperand else { return }
            // Parentheses preserve the previous result's meaning in the history.
            tokens = ["("] + tokens + [")", repeatOperation, NSDecimalNumber(decimal: repeatOperand).stringValue]
        }
        if tokens.isEmpty { tokens = ["0"] }
        if balance > 0 { tokens += Array(repeating: ")", count: balance) }
        var parser = CalculatorExpression(tokens, degrees: degrees)
        do {
            let result = try parser.evaluate()
            display = CalculatorExpression.formatted(result.value)
            repeatOperation = result.repeated?.0
            repeatOperand = result.repeated?.1
        } catch { display = "错误"; repeatOperation = nil; repeatOperand = nil }
        editingNumber = false
        finished = true
    }

    private func clear() {
        tokens = []
        display = "0"
        finished = false
        editingNumber = false
        repeatOperation = nil
        repeatOperand = nil
    }
}
