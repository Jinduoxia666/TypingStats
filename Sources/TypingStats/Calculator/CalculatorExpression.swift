import Foundation

/// A bounded arithmetic parser; never evaluates arbitrary code or expressions.
struct CalculatorExpression {
    enum Failure: Error { case invalid, domain }
    static let operators: Set<String> = ["+", "−", "×", "÷", "^"]
    static let functions: Set<String> = ["sin", "cos", "tan", "ln", "log", "√", "neg", "inv", "square", "pow10", "exp"]
    var tokens: [String]
    var degrees: Bool
    private var index = 0
    private var repeated: (String, Decimal)?

    init(_ tokens: [String], degrees: Bool) {
        self.tokens = tokens
        self.degrees = degrees
    }

    mutating func evaluate() throws -> (value: Decimal, repeated: (String, Decimal)?) {
        guard !tokens.isEmpty, tokens.count <= 256 else { throw Failure.invalid }
        let value = try sum()
        guard index == tokens.count, !value.isNaN else { throw Failure.invalid }
        return (value, repeated)
    }

    private mutating func take(_ token: String) -> Bool {
        guard index < tokens.count, tokens[index] == token else { return false }
        index += 1
        return true
    }

    private mutating func sum() throws -> Decimal {
        var value = try product()
        while index < tokens.count, ["+", "−"].contains(tokens[index]) {
            let op = tokens[index]; index += 1
            let rhs = try product()
            value = op == "+" ? value + rhs : value - rhs
            repeated = (op, rhs)
        }
        return value
    }

    private mutating func product() throws -> Decimal {
        var value = try power()
        while index < tokens.count, ["×", "÷"].contains(tokens[index]) {
            let op = tokens[index]; index += 1
            let rhs = try power()
            if op == "÷", rhs == 0 { throw Failure.domain }
            value = op == "×" ? value * rhs : value / rhs
            repeated = (op, rhs)
        }
        return value
    }

    private mutating func power() throws -> Decimal {
        let lhs = try atom()
        if take("^") {
            let rhs = try power()
            let result = try decimal(pow(NSDecimalNumber(decimal: lhs).doubleValue, NSDecimalNumber(decimal: rhs).doubleValue))
            repeated = ("^", rhs)
            return result
        }
        return lhs
    }

    private mutating func atom() throws -> Decimal {
        guard index < tokens.count else { throw Failure.invalid }
        if take("(") {
            let result = try sum()
            guard take(")") else { throw Failure.invalid }
            return result
        }
        let token = tokens[index]; index += 1
        if Self.functions.contains(token) {
            guard take("(") else { throw Failure.invalid }
            let priorRepeated = repeated
            let value = try sum()
            guard take(")") else { throw Failure.invalid }
            repeated = priorRepeated
            return try apply(token, value)
        }
        if token == "π" { return try decimal(.pi) }
        if token == "e" { return try decimal(exp(1)) }
        guard let value = Decimal(string: token, locale: Locale(identifier: "en_US_POSIX")) else { throw Failure.invalid }
        return value
    }

    private func apply(_ function: String, _ value: Decimal) throws -> Decimal {
        let x = NSDecimalNumber(decimal: value).doubleValue
        let angle = degrees ? x * .pi / 180 : x
        switch function {
        case "neg": return -value
        case "square": return value * value
        case "inv":
            guard value != 0 else { throw Failure.domain }
            return 1 / value
        case "√": return try decimal(sqrt(x))
        case "ln": return try decimal(log(x))
        case "log": return try decimal(log10(x))
        case "sin": return try decimal(sin(angle))
        case "cos": return try decimal(cos(angle))
        case "tan":
            guard abs(cos(angle)) > 1e-14 else { throw Failure.domain }
            return try decimal(tan(angle))
        case "pow10": return try decimal(pow(10, x))
        default: return try decimal(exp(x))
        }
    }

    private func decimal(_ value: Double) throws -> Decimal {
        guard value.isFinite,
              let decimal = Decimal(string: String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), value)),
              !decimal.isNaN else { throw Failure.domain }
        return decimal
    }

    static func formatted(_ value: Decimal) -> String {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 10, .plain)
        // Preserve very small scientific results rather than rounding to zero.
        return NSDecimalNumber(decimal: rounded == 0 && value != 0 ? value : rounded).stringValue
    }

    static func text(_ tokens: [String]) -> String {
        let names = ["neg": "−", "inv": "1/", "square": "sqr", "pow10": "10^", "exp": "exp"]
        var text = ""
        for token in tokens {
            if operators.contains(token) { text += " \(token) " }
            else { text += names[token] ?? token }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
