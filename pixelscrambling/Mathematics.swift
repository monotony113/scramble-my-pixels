//
//  PixelPermutations.swift
//  pixelscrambling
//
//  Created by Tony Wu on 1/8/19.
//  Copyright © 2019 Tony Wu. All rights reserved.
//

import Foundation

func mapElementToIndex<T, C>(_ elements: [T], with indexes: [C]) throws -> [T] where C: Comparable {
    if elements.count != indexes.count {
        throw RuntimeError.lengthMismatch
    }
    return zip(elements, indexes.enumerated()).sorted() { e1, e2 in
        pseudoStableSort2DAscending(e1.1.element, e1.1.offset, e2.1.element, e2.1.offset)
        }.map() { arg0 in arg0.0  }
}

func pseudoStableSort2DAscending<C1: Comparable, C2: Comparable>(_ e11: C1, _ e12: C2, _ e21: C1, _ e22: C2) -> Bool {
    return e11 < e21 || e11 == e21 && e12 < e22
}

func normalizeInteger(_ x: Int, d: ClosedRange<Int>, r: ClosedRange<Int>) -> Int {
    var n = x
    if n > d.upperBound { n = d.upperBound }
    if n < d.lowerBound { n = d.lowerBound }
    return Int(Float(r.lowerBound) + Float(n) / Float(d.upperBound - d.lowerBound) * Float(r.upperBound - r.lowerBound))
}
func factorize(_ n: Int, ge: Int, le: Int) -> [Int] {
    var divisors: [Int] = []
    for i in ge...le {
        if n % i == 0 { divisors.append(i) }
    }
    return divisors
}
