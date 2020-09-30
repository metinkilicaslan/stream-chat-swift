//
//  UIEdgeInsets+Extensions.swift
//  StreamChat
//
//  Created by Alexey Bukhtin on 07/04/2019.
//  Copyright © 2019 Stream.io Inc. All rights reserved.
//

import UIKit

extension UIEdgeInsets: Hashable {
    
    /// Create an UIEdgeInsets with equal sides values.
    ///
    /// - Parameter value: a side value.
    public init(all value: CGFloat) {
        self.init(top: value, leading: value, bottom: value, trailing: value)
    }
    
    /// Create an UIEdgeInsets with equal sides values.
    ///
    /// - Parameter value: a side value.
    /// - Returns: a UIEdgeInsets with equal sides.
    public static func all(_ value: CGFloat) -> UIEdgeInsets {
        return UIEdgeInsets(all: value)
    }
    
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        let direction = UIApplication.shared.userInterfaceLayoutDirection

        switch direction {
        case .leftToRight:
            self.init(top: top, left: leading, bottom: bottom, right: trailing)
        case .rightToLeft:
            self.init(top: top, left: trailing, bottom: bottom, right: leading)
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(top)
        hasher.combine(left)
        hasher.combine(bottom)
        hasher.combine(right)
    }
}
