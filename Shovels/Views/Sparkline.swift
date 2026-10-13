//
//  Sparkline.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import SwiftUI

/// A thin line of usage values from 0 to 100, drawn at the window's color.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let clamped = min(max(value, 0), 100)
                let y = size.height * (1 - CGFloat(clamped) / 100)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .frame(height: 14)
    }
}
