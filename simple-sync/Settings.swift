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
        if endpointEnabled,
           let endpointUrlString = userDefaults.string(forKey: "endpoint_url"),
           let endpointUrl = URL(string: endpointUrlString)
        {
            // Construct the URL from it's component parts, only allowing web-socket schemes.
            if let scheme = endpointUrl.scheme?.lowercased(),
               scheme == "wss" || scheme == "ws",
               let host = endpointUrl.host,
               let port = endpointUrl.port
            {
                var components = URLComponents()
                components.scheme = scheme
                components.host = host
                components.port = port

                // If we are able to construct a valid URL, create a new endpoint.
                if let url = components.url {
                    newEndpoint = App.Endpoint(
                        url: url,
                        username: userDefaults.string(forKey: "endpoint_username"),
                        password: userDefaults.string(forKey: "endpoint_password")
                    )
                }
            }
        }
        
        // If the endpoint has changed, update it.
        if newEndpoint != endpoint {
            endpoint = newEndpoint
        }
    }
}
