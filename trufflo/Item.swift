//
//  Item.swift
//  trufflo
//
//  Created by Guillaume Flambard on 04/10/2026.
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
