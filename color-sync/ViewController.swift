//
//  ViewController.swift
//  color-sync
//
//  Created by Wayne Carter on 4/29/23.
//

import UIKit
import CouchbaseLiteSwift

class ViewController: UIViewController {
    var storeService: AppService!
    var collection: Collection!

    @IBOutlet weak var label: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
        
        // Listen for changes to the profile document.
        _ = collection.addDocumentChangeListener(id: "profile") { [weak self] _ in
            self?.applyProfileColor()
        }
        
        // Listen for taps on the screen.
       let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(viewTapped))
       view.addGestureRecognizer(tapRecognizer)
        
        applyProfileColor()
    }
    
    @objc func viewTapped() {
        // Change the profile color.
        let color = Colors.randomColor(excluding: view.backgroundColor)
        let profile = (try? collection.document(id: "profile")?.toMutable()) ?? MutableDocument(id: "profile")
        profile.setString(Colors.hexFromColor(color), forKey: "color")
        
        try? collection.save(document: profile)
    }
    
    private func applyProfileColor() {
        // Read the color from the profile and set the background color.
        if let profile = try? collection.document(id: "profile"),
           let color = Colors.colorFromHex(profile.string(forKey: "color"))
        {
            view.backgroundColor = color
            label.isHidden = true
        }
    }
}
