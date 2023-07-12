//
//  PhotoViewController.swift
//  simple-sync
//
//  Created by Wayne Carter on 6/28/23.
//

import UIKit
import Combine
import CouchbaseLiteSwift

class PhotoViewController: UIViewController {
    private let database: CouchbaseLiteSwift.Database
    private let collection: CouchbaseLiteSwift.Collection
    private var app: App!
    
    private var cancellables = Set<AnyCancellable>()
    private var documentChangeListener: ListenerToken!
    
    required init?(coder: NSCoder) {
        database = try! CouchbaseLiteSwift.Database(name: "photo")
        collection = try! database.defaultCollection()
        
        super.init(coder: coder)
        
        // Get the identity and CA, then start the app. The app syncs
        // with nearby devices using peer-to-peer and the endpoint
        // specified in the app settings using the Internet.
        Credentials.async { [self] identity, ca in
            app = App(
                database: database,
                endpoint: Settings.shared.endpoint,
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
        
        // When the item document changes, update the displayed photo.
        documentChangeListener = collection.addDocumentChangeListener(id: "profile") { [weak self] _ in
            guard self?.isViewLoaded == true else { return }
            self?.showPhoto()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // When the screen is tapped, set a new photo.
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(setNewPhoto))
        view.addGestureRecognizer(tapRecognizer)
        
        // Show the current photo.
        showPhoto()
    }
    
    @objc private func setNewPhoto() {
        // Change the profile photo.
        let profile = collection["profile"].document?.toMutable() ?? MutableDocument(id: "profile")
        let emoji = profile["emoji"].string
        let nextEmoji = Photos.nextEmoji(emoji)
        let newPhoto = Photos[nextEmoji]
        
        if let pngData = newPhoto.pngData() {
            profile["emoji"].string = nextEmoji
            profile["photo"].blob = Blob(contentType: "image/png", data: pngData)
            try? collection.save(document: profile)
        }
    }
    
    private func showPhoto() {
        // Read the color from the profile.
        if let profile = collection["profile"].document,
           let imageBlob = profile["photo"].blob,
           let imageData = imageBlob.content
        {
            // Set the displayed image to the profile image.
            let image = UIImage(data: imageData)
            imageView.image = image
            
            // Hide the instructions view the first time we show a color.
            if !instructionsView.isHidden {
                imageView.isHidden = false
                instructionsView.isHidden = true
            }
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        // Stop the app.
        app?.stop()
        
        // Remove the document change listener.
        documentChangeListener.remove()
    }
    
    // MARK: - UI
    
    @IBOutlet weak var instructionsView: UIView!
    
    @IBOutlet weak var imageView: UIImageView! {
        didSet {
            // Add a drop shadow to the image view.
            imageView.layer.shadowColor = UIColor.black.cgColor
            imageView.layer.shadowOffset = CGSize(width: 0, height: 1)
            imageView.layer.shadowOpacity = 0.5
            imageView.layer.shadowRadius = 4
            imageView.layer.masksToBounds = false
        }
    }
    
    // MARK: - Utility

    private class Photos {
        private static let emojis: [String] = ["🦁","🦊","🐻‍❄️","🐱","🐶","🐰"]
        
        static subscript(emoji: String) -> UIImage {
            return image(emoji)
        }
        
        static func nextEmoji(_ emoji: String?) -> String {
            let index = (emoji != nil ? emojis.firstIndex(of: emoji!) : nil) ?? -1
            let nextIndex = (index + 1) % emojis.count
            let nextEmoji = emojis[nextIndex]
            return nextEmoji
        }
        
        private static func image(_ emoji: String) -> UIImage {
            let nsString = emoji as NSString
            let font = UIFont.systemFont(ofSize: 160)
            let stringAttributes = [NSAttributedString.Key.font: font]
            let imageSize = nsString.size(withAttributes: stringAttributes)

            let renderer = UIGraphicsImageRenderer(size: imageSize)
            let image = renderer.image { _ in
                nsString.draw(at: CGPoint.zero, withAttributes: stringAttributes)
            }

            return image
        }
    }
    
    // MARK: - Info
    
    @IBAction func infoButtonPressed(_ sender: UIBarButtonItem) {
        let alert = Alerts.info
        alert.popoverPresentationController?.sourceItem = sender
        alert.title = "Tap the screen, change the photo, and sync with devices around you"
        
        self.present(alert, animated: true)
    }
}
