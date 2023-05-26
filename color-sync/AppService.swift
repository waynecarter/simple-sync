//
//  AppService.swift
//  color-sync
//
//  Created by Wayne Carter on 4/29/23.
//

import os
import Foundation
import Network
import UIKit
import CouchbaseLiteSwift

final class AppService {
    private let name: String
    private let database: CouchbaseLiteSwift.Database
    private let collections: [CouchbaseLiteSwift.Collection]
    private let identity: SecIdentity
    private let ca: SecCertificate
    
    private let uuid = UUID().uuidString
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections = [NWConnection]()
    private var messageEndpointListener: MessageEndpointListener
    private var messageEndpointConnections = [HashableObject : NMMessageEndpointConnection]()
    private var replicators = [HashableObject : Replicator]()
    
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkQueue", target: .global())

    init(name: String, database: CouchbaseLiteSwift.Database, collections: [CouchbaseLiteSwift.Collection], identity: SecIdentity, ca: SecCertificate) {
        self.name = name
        self.database = database
        self.collections = collections
        self.identity = identity
        self.ca = ca
        
        let config = MessageEndpointListenerConfiguration(collections: collections, protocolType: .byteStream)
        messageEndpointListener = MessageEndpointListener(config: config)
        
        // Monitor the network and pause/resume when connectivity changes.
        networkMonitor.pathUpdateHandler = { [weak self] path in
            switch path.status {
            case .satisfied:
                Log.info("Network is available")
                self?.pause()
                self?.resume()
            default:
                Log.info("Network is unavailable")
                self?.pause()
            }
        }
        networkMonitor.start(queue: networkQueue)
        
        // Monitor the app's background state and pause/resume when
        // it moves in and out of the background.
        NotificationCenter.default.addObserver( forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.networkQueue.async {
                self?.pause()
            }
        }
        NotificationCenter.default.addObserver( forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.networkQueue.async {
                self?.resume()
            }
        }
    }
    
    // Flag indicating whether the start method has been called.
    private var started = false

    func start() {
        // Start on the network queue so we don't have any race conditions.
        networkQueue.sync {
            started = true
            resume()
        }
    }

    func stop() {
        // Stop on the network queue so we don't have any race conditions.
        networkQueue.sync {
            pause()
            started = false
        }
    }
    
    // Flag indicating whether the listner/browser are currently running.
    private var running = false
    
    // Internal function for starting/resuming.
    private func resume() {
        if started, !running {
            running = true
            
            // Setup and start the listener and browser.
            listener = setupListener()
            browser = setupBrowser()
            listener?.start(queue: networkQueue)
            browser?.start(queue: networkQueue)
        }
    }
    
    // Internal function for stopping/pausing.
    private func pause() {
        if started, running {
            running = false
            
            // Cancel and nullify the listener and browser.
            listener?.cancel()
            browser?.cancel()
            listener = nil
            browser = nil
            
            // Clean up all connections.
            connections.forEach { connection in
                cleanupConnection(connection)
            }
            
            // Close all active message endpoint connections.
            messageEndpointListener.closeAll()
        }
    }
    
    // MARK: Trust verification

    private let trustEvaluationQueue = DispatchQueue(label: "TrustEvaluationQueue")
    private var trustVerificationBlock: sec_protocol_verify_t {
        return { sec_protocol_metadata, sec_trust, sec_protocol_verify_complete in
            self.trustEvaluationQueue.async {
                // Create a SecTrust object with the provided sec_trust
                let secTrust: SecTrust! = sec_trust_copy_ref(sec_trust).takeRetainedValue()
                
                // Create and set the security policy to SSL with a nil hostname. The peer will
                // go through SSL validation but it's hostname will not need to match the peer's
                // certificate CN.
                let policy = SecPolicyCreateSSL(false, nil)
                SecTrustSetPolicies(secTrust, policy)
                
                // Set the trust anchor to the trusted root CA certificate.
                SecTrustSetAnchorCertificates(secTrust, [self.ca] as CFArray)
                // Disable the built in system anchor certificates.
                SecTrustSetAnchorCertificatesOnly(secTrust, true)
                
                // Evaluate the trust of the certificate.
                SecTrustEvaluateAsyncWithError(secTrust, self.trustEvaluationQueue) { secTrust, trusted, error in
                    sec_protocol_verify_complete(trusted)
                }
            }
        }
    }
    
    // MARK: Network setup
    
    private var networkParameters: NWParameters {
        // Configure TLS options
        let tlsOptions = NWProtocolTLS.Options()
        let identity = sec_identity_create(identity)!
        sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, identity)
        sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, trustVerificationBlock, trustEvaluationQueue)
        
        // Configure the NWParameters with TLS
        let params = NWParameters(tls: tlsOptions)
        params.includePeerToPeer = true
        params.allowLocalEndpointReuse = true
        
        return params
    }

    private func setupListener() -> NWListener? {
        // Create the NWListener
        var listener: NWListener!
        do {
            listener = try NWListener(
                service: NWListener.Service(name: uuid, type: "_\(name)._tcp"),
                using: networkParameters
            )
        } catch {
            Log.info("Failed to create listener: \(error)")
            return nil
        }

        // Handle new connections.
        listener.newConnectionHandler = { [weak self] connection in
            // Don't connect to an endpoint more than once.
            if let serviceName = self?.serviceNameFor(connection.endpoint),
               self?.connections.contains(where: { self?.serviceNameFor($0.endpoint) == serviceName }) ?? false
            {
                Log.info("Skipping connection: \(serviceName)")
                self?.cleanupConnection(connection)
                return
            }
            
            self?.handleNewConnection(connection)
        }
        
        // Monitor the listener state.
        listener.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                Log.info("Listener is ready")
            case .failed(let error):
                Log.info("Listener stopped with error: \(error)")
            case .cancelled:
                Log.info("Listener stopped with state: cancelled")
            default:
                break
            }
        }

        return listener
    }

    private func setupBrowser()  -> NWBrowser? {
        // Create the NWBrowser
        let browserDescriptor = NWBrowser.Descriptor.bonjour(type: "_\(name)._tcp", domain: nil)
        let browser = NWBrowser(for: browserDescriptor, using: networkParameters)
        
        // Handle discovered endpoints
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            for change in changes {
                switch change {
                case .added(let result):
                    let serviceName = self?.serviceNameFor(result.endpoint)
                    
                    // Don't connect to the local service.
                    if serviceName == self?.uuid {
                        break
                    }
                    
                    // Don't connect to an endpoint more than once.
                    if let serviceName = serviceName,
                       self?.connections.contains(where: { self?.serviceNameFor($0.endpoint) == serviceName }) ?? false
                    {
                        Log.info("Skipping service: \(serviceName)")
                        break
                    }
                    
                    Log.info("Added service: \(result.endpoint)")
                    self?.handleNewEndpoint(result.endpoint)
                case .removed(let result):
                    Log.info("Lost service: \(result.endpoint)")
                    if let connection = self?.connections.first(where: { $0.endpoint == result.endpoint }) {
                        self?.cleanupConnection(connection)
                    }
                default:
                    break
                }
            }
        }
        
        // Monitor the browser state.
        browser.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                Log.info("Browser is ready")
            case .failed(let error):
                Log.info("Browser stopped with error: \(error)")
            case .cancelled:
                Log.info("Browser stopped with state: cancelled")
            default:
                break
            }
        }

        return browser
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                Log.info("Connection ready: \(connection)")
                self?.connections.append(connection)
                self?.setupMessageEndpointConnection(connection)
            case .failed:
                Log.info("Connection failed: \(connection)")
                self?.cleanupConnection(connection)
            case .cancelled:
                Log.info("Connection cancelled: \(connection)")
                self?.cleanupConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: networkQueue)
    }
    
    private func handleNewEndpoint(_ endpoint: NWEndpoint) {
        guard !connections.contains(where: { $0.endpoint == endpoint }) else {
            return
        }

        let connection = NWConnection(to: endpoint, using: networkParameters)
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                Log.info("Connection ready: \(connection)")
                self?.connections.append(connection)
                self?.setupReplicator(for: connection)
            case .failed:
                Log.info("Connection failed: \(connection)")
                self?.cleanupConnection(connection)
            case .cancelled:
                Log.info("Connection cancelled: \(connection)")
                self?.cleanupConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: networkQueue)
    }

    // MARK: Replication
    
    private func setupMessageEndpointConnection(_ connection: NWConnection) {
        let messageEndpointConnection = NMMessageEndpointConnection(connection: connection)
        messageEndpointListener.accept(connection: messageEndpointConnection)
        
        messageEndpointConnections[HashableObject(connection)] = messageEndpointConnection
    }
    
    private func setupReplicator(for connection: NWConnection) {
        let messageEndpointDelegate = NMMessageEndpointDelegate(connection: connection)
        let target = MessageEndpoint(uid: uuid, target: nil, protocolType: .byteStream, delegate: messageEndpointDelegate)
        var config = ReplicatorConfiguration(target: target)
        config.replicatorType = .pushAndPull
        config.continuous = true
        config.addCollections(collections)
        
        let replicator = Replicator(config: config)
        replicators[HashableObject(connection)] = replicator
        replicator.start()
    }
    
    private class NMMessageEndpointDelegate: CouchbaseLiteSwift.MessageEndpointDelegate {
        private let connection: NWConnection
        
        init(connection: NWConnection) {
            self.connection = connection
        }
        
        // MARK: - MessageEndpointDelegate
        
        func createConnection(endpoint: CouchbaseLiteSwift.MessageEndpoint) -> CouchbaseLiteSwift.MessageEndpointConnection {
            return NMMessageEndpointConnection(connection: connection)
        }
    }
    
    private class NMMessageEndpointConnection: CouchbaseLiteSwift.MessageEndpointConnection {
        private let connection: NWConnection
        private var replicatorConnection: ReplicatorConnection?
        
        init(connection: NWConnection) {
            self.connection = connection
        }
        
        // MARK: - MessageEndpointConnection
        
        func open(connection: CouchbaseLiteSwift.ReplicatorConnection, completion: @escaping (Bool, CouchbaseLiteSwift.MessagingError?) -> Void) {
            replicatorConnection = connection
            receive()
            completion(true, nil)
        }
        
        func close(error: Error?, completion: @escaping () -> Void) {
            replicatorConnection = nil
            connection.cancel()
            completion()
        }
        
        func send(message: CouchbaseLiteSwift.Message, completion: @escaping (Bool, CouchbaseLiteSwift.MessagingError?) -> Void) {
            let data = message.toData()
            Log.info("Sending data: \(data)")
            connection.send(content: data, contentContext: .defaultMessage, isComplete: true, completion: .contentProcessed({ error in
                if let error = error {
                    Log.info("Send error: \(error)")
                    completion(true, CouchbaseLiteSwift.MessagingError(error: error, isRecoverable: false))
                } else {
                    completion(true, nil)
                }
            }))
        }
        
        private func receive() {
            let minimumIncompleteLength = 1
            let maximumLength = 65536
            connection.receive(minimumIncompleteLength: minimumIncompleteLength, maximumLength: maximumLength) { [weak self] (data, _, _, error) in
                if let error = error {
                    Log.info("Receive error: \(error)")
                    self?.replicatorConnection?.close(
                        error: MessagingError(error: error, isRecoverable: false)
                    )
                } else {
                    if let data = data {
                        Log.info("Received data: \(data)")
                        let message = Message.fromData(data)
                        self?.replicatorConnection?.receive(message: message)
                    } else {
                        Log.info("Received data: nil")
                    }

                    // Continue listening for messages.
                    self?.receive()
                }
            }
        }
    }
    
    // MARK: Cleanup
    
    private func cleanupConnection(_ connection: NWConnection) {
        // For passive peers, remove and stop the endpoint listener.
        if let messageEndpointConnection = messageEndpointConnections.removeValue(forKey: HashableObject(connection)) {
            messageEndpointListener.close(connection: messageEndpointConnection)
        }

        // For active peers, remove and stop the replicator.
        if let replicator = replicators.removeValue(forKey: HashableObject(connection)) {
            replicator.stop()
        }
        
        // Cancel and remove the connection.
        connection.cancel()
        connections.removeAll { $0 === connection }
    }
    
    // MARK: - Utility
    
    private func serviceNameFor(_ endpoint: NWEndpoint) -> String? {
        switch endpoint {
        case .service(let serviceName, _, _, _): return serviceName
        default: return nil
        }
    }
    
    class Log {
        static private let logger = OSLog(subsystem: "color-sync", category: "network")
        
        static func info(_ message: String) {
            let isDebuggerAttached = isatty(STDERR_FILENO) != 0
            
            if isDebuggerAttached {
                print(message)
            } else {
                os_log("%{public}@", log: logger, type: .info, message)
            }
        }
    }
    
    private class HashableObject: Hashable {
        let object: AnyObject

        init(_ object: AnyObject) {
            self.object = object
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(object))
        }

        static func ==(lhs: HashableObject, rhs: HashableObject) -> Bool {
            return lhs.object === rhs.object
        }
    }
}
