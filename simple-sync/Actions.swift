//
//  Actions.swift
//  simple-sync
//
//  Created by Wayne Carter on 7/7/23.
//

import UIKit

class Actions {
    
    static func info(for demo: String) -> UIAlertController {
        let exploreCodeUrl = "https://github.com/waynecarter/simple-sync/blob/main/README.md#\(demo)"
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(openURLAction(title: "Explore the Code", urlString: exploreCodeUrl))
        alert.addAction(openURLAction(title: "Settings", urlString: UIApplication.openSettingsURLString))
        alert.addAction(openURLAction(title: "Terms of Use", urlString: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"))
        alert.addAction(openURLAction(title: "Privacy Policy", urlString: "https://github.com/waynecarter/simple-sync/blob/main/PRIVACY"))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in
            alert.dismiss(animated: true)
        }))
        
        return alert
    }

    private static func openURLAction(title: String, urlString: String) -> UIAlertAction {
        return UIAlertAction(title: title, style: .default) { action in
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    static func share(for viewController: UIViewController) -> UIActivityViewController {
        let appStoreURL = "https://apps.apple.com/us/app/simple-data-sync/id6449199482"
        let qrCodeActivity = QRCodeActivity(for: viewController, appURL: appStoreURL)
        
        let activityViewController = UIActivityViewController(activityItems: [appStoreURL], applicationActivities: [qrCodeActivity])
        return activityViewController
    }
    
    private class QRCodeActivity: UIActivity {
        private let viewController: UIViewController
        private let appURL: String
        
        init(for viewController: UIViewController, appURL: String) {
            self.viewController = viewController
            self.appURL = appURL
        }
        
        override var activityTitle: String? {
            return "Show QR Code"
        }
        
        override var activityImage: UIImage? {
            return UIImage(systemName: "qrcode")
        }
        
        override func canPerform(withActivityItems activityItems: [Any]) -> Bool {
            return true
        }
        
        override func perform() {
            let qrCodeViewController = QRCodeViewController(appURL: appURL)
            viewController.present(qrCodeViewController, animated: true, completion: nil)
            
            activityDidFinish(true)
        }
        
        private class QRCodeViewController: UIViewController {
            private let appURL: String
                
            init(appURL: String) {
                self.appURL = appURL
                super.init(nibName: nil, bundle: nil)
            }
            
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override func viewDidLoad() {
                super.viewDidLoad()

                self.view.backgroundColor = .systemBackground
                
                // Close button
                let closeButton = UIButton(type: .close, primaryAction: UIAction { action in
                    self.dismiss(animated: true, completion: nil)
                })
                closeButton.tintColor = .systemGray
                closeButton.configuration = {
                    var config = UIButton.Configuration.gray()
                    config.cornerStyle = .capsule
                    return config
                }()
                closeButton.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(closeButton)
                
                // Create an attributed string for the label.
                let titleText = "Simple Sync"
                let instructionsText = "Scan the QR code to get the app"
                let attributedString = NSMutableAttributedString(string: "\(titleText)\n\(instructionsText)")
                attributedString.addAttribute(NSAttributedString.Key.font, value: UIFont.systemFont(ofSize: ceil(UIFont.labelFontSize * 1.15), weight: .bold), range: NSRange(location: 0, length: titleText.count))
                        
                // Label
                let label = UILabel()
                label.numberOfLines = 0
                label.textAlignment = .center
                label.attributedText = attributedString
                label.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(label)
                
                // Image container for shadow and corner radius.
                let imageContainerView = UIView()
                imageContainerView.backgroundColor = .white
                imageContainerView.layer.cornerRadius = 10
                imageContainerView.layer.shadowColor = UIColor.black.cgColor
                imageContainerView.layer.shadowOffset = CGSize(width: 0, height: 2)
                imageContainerView.layer.shadowOpacity = 0.4
                imageContainerView.layer.shadowRadius = 5
                imageContainerView.layer.masksToBounds = false
                imageContainerView.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(imageContainerView)

                // Image
                let imageView = UIImageView(image: {
                    // Create the QR code image.
                    let data = appURL.data(using: String.Encoding.ascii)
                    if let filter = CIFilter(name: "CIQRCodeGenerator") {
                        filter.setValue(data, forKey: "inputMessage")
                        let transform = CGAffineTransform(scaleX: 10, y: 10)

                        if let output = filter.outputImage?.transformed(by: transform) {
                            return UIImage(ciImage: output.transformed(by: transform))
                        }
                    }
                    return nil
                }())
                imageView.contentMode = .scaleAspectFit
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageContainerView.addSubview(imageView)

                // Set up layout constraints with a margin.
                NSLayoutConstraint.activate([
                    // Close
                    closeButton.heightAnchor.constraint(equalTo: closeButton.widthAnchor),
                    closeButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
                    closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

                    // Label
                    label.bottomAnchor.constraint(equalTo: imageContainerView.topAnchor, constant: -20),
                    label.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor),
                    label.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor),

                    // Image Container
                    imageContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
                    imageContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
                    imageContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                    imageContainerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                    imageContainerView.heightAnchor.constraint(equalTo: imageContainerView.widthAnchor),

                    // Image
                    imageView.leadingAnchor.constraint(equalTo: imageContainerView.leadingAnchor, constant: 10),
                    imageView.trailingAnchor.constraint(equalTo: imageContainerView.trailingAnchor, constant: -10),
                    imageView.topAnchor.constraint(equalTo: imageContainerView.topAnchor, constant: 10),
                    imageView.bottomAnchor.constraint(equalTo: imageContainerView.bottomAnchor, constant: -10)
                ])
            }
        }
    }
}
