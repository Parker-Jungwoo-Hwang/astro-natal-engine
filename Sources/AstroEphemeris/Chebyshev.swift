import Foundation

struct Chebyshev {
    struct EvaluationResult: Sendable, Equatable {
        let value: Double
        let derivative: Double
    }

    /// Evaluates a Chebyshev series and its derivative with respect to the
    /// normalized independent variable `x` in the interval [-1, 1].
    ///
    /// The SPK Type 2 evaluator later divides the derivative by the record radius
    /// to convert from d/dx to d/dt.
    static func evaluateWithDerivative(coefficients: [Double], x: Double) -> EvaluationResult {
        guard !coefficients.isEmpty else {
            return EvaluationResult(value: 0, derivative: 0)
        }

        if coefficients.count == 1 {
            return EvaluationResult(value: coefficients[0], derivative: 0)
        }

        var value = coefficients[0] + coefficients[1] * x
        var derivative = coefficients[1]

        var tMinusTwo = 1.0
        var tMinusOne = x

        // U_0(x) = 1. For n >= 2, dT_n/dx = n * U_{n-1}(x).
        var uMinusTwo = 1.0
        var uMinusOne = 2.0 * x

        if coefficients.count == 2 {
            return EvaluationResult(value: value, derivative: derivative)
        }

        for degree in 2 ..< coefficients.count {
            let t = 2.0 * x * tMinusOne - tMinusTwo
            value += coefficients[degree] * t
            derivative += Double(degree) * coefficients[degree] * uMinusOne

            let u = 2.0 * x * uMinusOne - uMinusTwo
            tMinusTwo = tMinusOne
            tMinusOne = t
            uMinusTwo = uMinusOne
            uMinusOne = u
        }

        return EvaluationResult(value: value, derivative: derivative)
    }
}
