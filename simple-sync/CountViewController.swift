//
//  CountViewController.swift
//  simple-sync
//
//  Created by Wayne Carter on 6/10/23.
//

import UIKit
import Combine
import CouchbaseLiteSwift

class CountViewController: UIViewController {
    private let database: CouchbaseLiteSwift.Database
    private let collection: CouchbaseLiteSwift.Collection
    private var app: App!
    
    private var cancellables = Set<AnyCancellable>()
    private var documentChangeListener: ListenerToken!
    
    required init?(coder: NSCoder) {
        database = try! CouchbaseLiteSwift.Database(name: "count")
        collection = try! database.defaultCollection()
        
        super.init(coder: coder)
        
        // Get the identity and CA, then start the app. The app syncs
        // with nearby devices using peer-to-peer and the endpoint
        // specified in the app settings using the Internet.
        Credentials.async { [self] identity, ca in
            app = App(
                database: database,
                endpoint: Settings.shared.endpoint,
                conflictResolver: ConflictResolver.crdt,
                identity: identity,
                ca: ca
            )
            app.start()
            
            // When the endpoint settings change, update the app.
            Settings.shared.$endpoint
                .dropFirst()
                .sink { [weak self] newEndpoint in
                    self?.app.endpoint = newEndpoint
                }.store(in: &cancellables)
        }
        
        // When the item document changes, update the displayed count.
        documentChangeListener = collection.addDocumentChangeListener(id: "item") { [weak self] _ in
            guard self?.isViewLoaded == true else { return }
            self?.showCount()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Show the current count.
        showCount()
    }
    
    @IBAction func incrementCount(_ sender: Any) {
        var saved = false
        while !saved {
            // Read the count from the item doc and increment it.
            let document = collection["item"].document?.toMutable() ?? MutableDocument(id: "item")
            let count: MutableCounter = document.counter(forKey: "count", actor: database.uuid)
            count.increment(by: 1)
            
            // Save with concurrency control and retry on failure.
            saved = (try? collection.save(document: document, concurrencyControl: .failOnConflict)) ?? false
        }
    }
    
    @IBAction func decrementCount(_ sender: Any) {
        var saved = false
        while !saved {
            // Read the count from the item doc and decrement it.
            let document = collection["item"].document?.toMutable() ?? MutableDocument(id: "item")
            let count: MutableCounter = document.counter(forKey: "count", actor: database.uuid)
            count.decrement(by: 1)
            
            // Save with concurrency control and retry on failure.
            saved = (try? collection.save(document: document, concurrencyControl: .failOnConflict)) ?? false
        }
    }
    
    private func showCount() {
        // Read the count from the item doc.
        let item = collection["item"].document
        let counter = item?.counter(forKey: "count")
        let count = counter?.value ?? 0
        
        // Update the UI.
        countLabel.text = String(count)
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Stop the app.
        app?.stop()
        
        // Remove the document change listener.
        documentChangeListener?.remove()
    }
    
    // MARK: - UI
    
    @IBOutlet weak var countLabel: UILabel!
    
    // MARK: - Actions
    
    @IBAction func infoButtonPressed(_ sender: UIBarButtonItem) {
        let alert = Actions.info
        alert.popoverPresentationController?.sourceItem = sender
        alert.title = "Tap the buttons, change the count, and sync with devices around you"
        present(alert, animated: true)
    }
    
    @IBAction func share(_ sender: UIBarButtonItem) {
        let activity = Actions.share(for: self)
        activity.popoverPresentationController?.sourceItem = sender
        present(activity, animated: true)
    }
}
