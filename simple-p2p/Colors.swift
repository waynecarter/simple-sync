//
//  Colors.swift
//  simple-p2p
//
//  Created by Wayne Carter on 4/29/23.
//

import UIKit

class Colors {
    static func randomColor(excluding excluded: UIColor?) -> UIColor {
        let colors: [UIColor] = [
            UIColor(red: 0.4, green: 0.7, blue: 0.8, alpha: 1.0), // Light blue
            UIColor(red: 0.7, green: 0.9, blue: 0.7, alpha: 1.0), // Light green
            UIColor(red: 1.0, green: 0.7, blue: 0.8, alpha: 1.0), // Light pink
            UIColor(red: 0.9, green: 0.7, blue: 0.9, alpha: 1.0), // Light purple
            UIColor(red: 0.7, green: 0.8, blue: 0.9, alpha: 1.0), // Light periwinkle
        ]
        
        let randomIndex = Int(arc4random_uniform(UInt32(colors.count)))
        let color = colors[randomIndex]
        
        // If the color is the same as the excluded color, choose again.
        if hexFromColor(color) == hexFromColor(excluded) {
            return randomColor(excluding: excluded)
        } else {
            return color
        }
    }
    
    static func hexFromColor(_ color: UIColor?) -> String? {
        guard let color = color else { return nil }
        
        let components = color.cgColor.components
        let r: CGFloat = components?.count ?? 0 > 0 ? components![0] : 0.0
        let g: CGFloat = components?.count ?? 0 > 1 ? components![1] : 0.0
        let b: CGFloat = components?.count ?? 0 > 2 ? components![2] : 0.0
        let a: CGFloat = components?.count ?? 0 > 3 ? components![3] : 0.0

        let hexString = String.init(format: "#%02lX%02lX%02lX%02lX", lroundf(Float(r * 255)), lroundf(Float(g * 255)), lroundf(Float(b * 255)), lroundf(Float(a * 255)))
        return hexString
    }

    static func colorFromHex(_ hex: String?) -> UIColor? {
        guard let hex = hex else { return nil }

        var cString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if cString.hasPrefix("#") {
            cString.remove(at: cString.startIndex)
        }

        if cString.count != 8 {
            return nil
        }

        var rgbaValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbaValue)

        let red = CGFloat((rgbaValue & 0xFF000000) >> 24) / 255.0
        let green = CGFloat((rgbaValue & 0x00FF0000) >> 16) / 255.0
        let blue = CGFloat((rgbaValue & 0x0000FF00) >> 8) / 255.0
        let alpha = CGFloat(rgbaValue & 0x000000FF) / 255.0

        return UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}
