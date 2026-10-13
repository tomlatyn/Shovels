//
//  ShovelsFonts.swift
//  Shovels
//
//  Created by Tomas Latyn on 13.10.26.
//

import CoreText
import Foundation

enum ShovelsFonts {
    /// Registers the bundled fonts for this process only. Nothing is installed system-wide.
    static func register() {
        for name in ["PressStart2P-Regular", "VT323-Regular"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
