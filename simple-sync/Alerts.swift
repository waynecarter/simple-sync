//
//  Alerts.swift
//  simple-sync
//
//  Created by Wayne Carter on 7/7/23.
//

import UIKit

class Alerts {
    
    static var info: UIAlertController {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "Explore the Code", style: .default, handler: { action in
            if let url = URL(string: "https://github.com/waynecarter/simple-sync/") {
                UIApplication.shared.open(url)
            }
        }))
        
        alert.addAction(UIAlertAction(title: "Settings", style: .default, handler: { action in
            if let appSettings = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(appSettings)
            }
        }))
        
        alert.addAction(UIAlertAction(title: "Terms of Use", style: .default, handler: { action in
            if let url = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") {
                UIApplication.shared.open(url)
            }
        }))
        
        alert.addAction(UIAlertAction(title: "Privacy Policy", style: .default, handler: { action in
            if let url = URL(string: "https://github.com/waynecarter/simple-sync/blob/main/PRIVACY") {
                UIApplication.shared.open(url)
            }
        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in
            alert.dismiss(animated: true)
        }))
        
        return alert
    }
}
