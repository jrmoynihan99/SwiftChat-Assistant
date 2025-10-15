//
//  Item.swift
//  SwiftChat Assistant
//
//  Created by Jason Moynihan on 10/15/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
