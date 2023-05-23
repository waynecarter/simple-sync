//
//  Database.swift
//  color-sync
//
//  Created by Wayne Carter on 5/23/23.
//

import Foundation
import CouchbaseLiteSwift

class Database {
    private static let name = "color-sync"
    
    static let shared = try! CouchbaseLiteSwift.Database(name: name)
    
    static var exists: Bool {
        CouchbaseLiteSwift.Database.exists(withName: name)
    }
}
