//
//  Settings.swift
//  simple-sync
//
//  Created by Wayne Carter on 7/1/23.
//

import Foundation
import Combine

class Settings: ObservableObject {
    static let shared = Settings()
    
    @Published var endpoint: App.Endpoint?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Observe UserDefaults changes.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                self?.updateEndpoint()
            }
            .store(in: &cancellables)
        
        updateEndpoint()
    }
    
    private func updateEndpoint() {
        let userDefaults = UserDefaults.standard
        var newEndpoint: App.Endpoint?
        
        // Get the endpoint.
        let endpointEnabled = userDefaults.bool(forKey: "endpoint_enabled")
        if endpointEnabled, let endpointUrl = userDefaults.string(forKey: "endpoint_url").flatMap(URL.init) {
            newEndpoint = App.Endpoint(
                url: endpointUrl,
                username: userDefaults.string(forKey: "endpoint_username"),
                password: userDefaults.string(forKey: "endpoint_password")
            )
        }
        
        // If the remote endpoint has changed, update it.
        if newEndpoint != endpoint {
            endpoint = newEndpoint
        }
    }
}
