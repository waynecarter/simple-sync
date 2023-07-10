//
//  ViewController.swift
//  simple-sync
//
//  Created by Wayne Carter on 6/29/23.
//

import UIKit

class ViewController: UITabBarController, UITabBarControllerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()

        self.delegate = self
        
        // Set the initial tab from UserDefaults.
        let initialTabIndex = UserDefaults.standard.integer(forKey: "selectedTab")
        self.selectedIndex = initialTabIndex
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect selectedViewController: UIViewController) {
        // Set that the tab bar needs to be layed out soth that it refreshes
        // correctly when switching between the different view controllers.
        tabBarController.view.setNeedsLayout()
        
        // Write the selected tab index to UserDefaults.
        UserDefaults.standard.set(selectedIndex, forKey: "selectedTab")
    }
}
