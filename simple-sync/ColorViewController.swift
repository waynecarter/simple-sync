//
//  ColorViewController.swift
//  simple-sync
//
//  Created by Wayne Carter on 4/29/23.
//

import UIKit
import Combine
import CouchbaseLiteSwift

class ColorViewController: UIViewController {
    private let database: CouchbaseLiteSwift.Database
    private let collection: CouchbaseLiteSwift.Collection
    private var app: App!
    
    private var cancellables = Set<AnyCancellable>()
    private var documentChangeListener: ListenerToken!
    
    required init?(coder: NSCoder) {
        database = try! CouchbaseLiteSwift.Database(name: "color")
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

        // When the profile document changes, update the displayed color.
        documentChangeListener = collection.addDocumentChangeListener(id: "profile") { [weak self] _ in
            guard self?.isViewLoaded == true else { return }
            self?.showColor()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // When the screen is tapped, set a new color.
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(setNewColor))
        view.addGestureRecognizer(tapRecognizer)

        // Show the current color.
        showColor()
    }

    @objc private func setNewColor() {
        // Change the profile color.
        let profile = collection["profile"].document?.toMutable() ?? MutableDocument(id: "profile")
        let colorIndex = profile["color"].value as? Int ?? -1
        let newColorIndex = Colors.nextIndex(colorIndex)

        profile["color"].int = newColorIndex
        try? collection.save(document: profile)
    }

    private func showColor() {
        // Read the color from the profile.
        if let profile = collection["profile"].document {
            let colorIndex = profile["color"].int
            let color = Colors[colorIndex]

            // Set the displayed color to the profile color.
            colorView.backgroundColor = color

            // Hide the instructions view the first time we show a color.
            if !instructionsView.isHidden {
                colorView.isHidden = false
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

    @IBOutlet weak var colorView: UIView! {
        didSet {
            colorView.layer.cornerRadius = min(colorView.frame.width, colorView.frame.height) / 2
            colorView.layer.shadowColor = UIColor.black.cgColor
            colorView.layer.shadowOffset = CGSize(width: 0, height: 2)
            colorView.layer.shadowOpacity = 0.4
            colorView.layer.shadowRadius = 5
            colorView.layer.masksToBounds = false
        }
    }

    // MARK: - Utility

    private class Colors {
        private static let colors: [UIColor] = [.systemBlue, .systemGreen, .systemPink, .systemPurple, .systemYellow]

        static subscript(index: Int) -> UIColor {
            let clampedIndex = clamp(index)
            return colors[clampedIndex]
        }

        static func nextIndex(_ index: Int) -> Int {
            let clampedIndex = index == -1 ? index : clamp(index)
            let nextIndex = (clampedIndex + 1) % colors.count
            return nextIndex
        }

        private static func clamp(_ index: Int) -> Int {
            return max(min(index, colors.count - 1), 0)
        }
    }

    // MARK: - Actions

    @IBAction func infoButtonPressed(_ sender: UIBarButtonItem) {
        let alert = Actions.info
        alert.popoverPresentationController?.sourceItem = sender
        alert.title = "Tap the screen, change the color, and sync with devices around you"
        present(alert, animated: true)
    }
    
    @IBAction func share(_ sender: UIBarButtonItem) {
        let activity = Actions.share(for: self)
        activity.popoverPresentationController?.sourceItem = sender
        present(activity, animated: true)
    }
}
