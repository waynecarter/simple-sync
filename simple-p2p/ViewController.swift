//
//  ViewController.swift
//  simple-p2p
//
//  Created by Wayne Carter on 4/29/23.
//

import UIKit
import CouchbaseLiteSwift

class ViewController: UIViewController {
    var storeService: AppService!
    var collection: Collection!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        // Set up the database and collection.
        let database = try! Database(name: "store")
        collection = try! database.defaultCollection()
        
        // Get the identity and CA async and then start the app service.
        Credentials.async { [self] identity, ca in
            storeService = AppService(
                name: "store",
                database: database,
                collections: [collection],
                identity: identity,
                ca: ca
            )
            storeService.start()
        }
        
        applyProfileColor()
        func applyProfileColor() {
            // Read the color from the profile and set the background color.
            if let profile = try? collection.document(id: "profile"),
               let color = Colors.colorFromHex(profile.string(forKey: "color"))
            {
                view.backgroundColor = color
            }
        }
        
        // Listen for changes to the profile document.
        _ = collection.addDocumentChangeListener(id: "profile") { _ in
            applyProfileColor()
        }
        
        // Listen for taps on the screen.
       let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(viewTapped))
       view.addGestureRecognizer(tapRecognizer)
    }
    
    @objc func viewTapped() {
        // Change the profile color.
        let color = Colors.randomColor(excluding: view.backgroundColor)
        let profile = (try? collection.document(id: "profile")?.toMutable()) ?? MutableDocument(id: "profile")
        profile.setString(Colors.hexFromColor(color), forKey: "color")
        
        try? collection.save(document: profile)
    }
}

