//
//  AppService.swift
//  simple-p2p
//
//  Created by Wayne Carter on 4/29/23.
//

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
    private var messageEndpointListeners = [HashableObject : MessageEndpointListener]()
    private var replicators = [HashableObject : Replicator]()
    
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkQueue", target: .global())

    init(name: String, database: CouchbaseLiteSwift.Database, collections: [CouchbaseLiteSwift.Collection], identity: SecIdentity, ca: SecCertificate) {
        self.name = name
        self.database = database
        self.collections = collections
        self.identity = identity
        self.ca = ca
        
        // Monitor the network and pause/resume when connectivity changes.
        networkMonitor.pathUpdateHandler = { [weak self] path in
            switch path.status {
            case .satisfied: self?.resume()
            default: self?.pause()
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
        }
    }
    
    // MARK: Trust verification

    private let trustEvaluationQueue = DispatchQueue(label: "TrustEvaluationQueue")
    private func trustVerificationBlock(_ caCertificate: SecCertificate) -> sec_protocol_verify_t {
        return { sec_protocol_metadata, sec_trust, sec_protocol_verify_complete in
            self.trustEvaluationQueue.async {
                // Create a SecTrust object with the provided sec_trust
                var secTrust: SecTrust! = sec_trust_copy_ref(sec_trust).takeRetainedValue()
                
                // Set an X509 policy so that the hostname of the peer presenting
                // the certificate doesn't need to match the certificate CN.
                let policy = SecPolicyCreateBasicX509()
                SecTrustCreateWithCertificates(caCertificate, policy, &secTrust)
                
                // Set the trust anchor to the trusted root CA certificate.
                SecTrustSetAnchorCertificates(secTrust, [caCertificate] as CFArray)
                // Re-enable the system certificates.
                SecTrustSetAnchorCertificatesOnly(secTrust, false)
                
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
        sec_protocol_options_set_verify_block(tlsOptions.securityProtocolOptions, trustVerificationBlock(ca), trustEvaluationQueue)
        
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
            print("Failed to create listener: \(error)")
            return nil
        }

        // Handle new connections.
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        // Monitor the listener state.
        listener.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                print("Listener is ready")
            case .failed(let error):
                print("Listener stopped with error: \(error)")
            case .cancelled:
                print("Listener stopped with state: cancelled")
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
                    // Don't connect to the local service.
                    guard case let .service(name: serviceName, type: _, domain: _, interface: _) = result.endpoint, serviceName != self?.uuid else {
                        break
                    }
                    
                    print("Added service: \(result.endpoint)")
                    self?.handleNewEndpoint(result.endpoint)
                case .removed(let result):
                    print("Lost service: \(result.endpoint)")
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
                print("Browser is ready")
            case .failed(let error):
                print("Browser stopped with error: \(error)")
            case .cancelled:
                print("Browser stopped with state: cancelled")
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
                print("Connection ready: \(connection)")
                self?.connections.append(connection)
                self?.setupMessageEndpointListener(for: connection)
            case .failed:
                print("Connection failed: \(connection)")
                self?.cleanupConnection(connection)
            case .cancelled:
                print("Connection cancelled: \(connection)")
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
                print("Connection ready: \(connection)")
                self?.connections.append(connection)
                self?.setupReplicator(for: connection)
            case .failed:
                print("Connection failed: \(connection)")
                self?.cleanupConnection(connection)
            case .cancelled:
                print("Connection cancelled: \(connection)")
                self?.cleanupConnection(connection)
            default:
                break
            }
        }
        connection.start(queue: networkQueue)
    }

    // MARK: Replication
    
    private func setupMessageEndpointListener(for connection: NWConnection) {
        let config = MessageEndpointListenerConfiguration(collections: collections, protocolType: .byteStream)
        let messageEndpointConnection = NMMessageEndpointConnection(connection: connection)
        let messageEndpointListener = MessageEndpointListener(config: config)
        messageEndpointListener.accept(connection: messageEndpointConnection)
        
        messageEndpointListeners[HashableObject(connection)] = messageEndpointListener
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
            completion()
            // TODO: Stop recieving()
        }
        
        func send(message: CouchbaseLiteSwift.Message, completion: @escaping (Bool, CouchbaseLiteSwift.MessagingError?) -> Void) {
            let data = message.toData()
            print("Sending data: \(data)")
            connection.send(content: data, contentContext: .defaultMessage, isComplete: true, completion: .idempotent)
        }
        
        private func receive() {
            let minimumIncompleteLength = 1
            let maximumLength = 65536
            connection.receive(minimumIncompleteLength: minimumIncompleteLength, maximumLength: maximumLength) { [weak self] (data, _, _, error) in
                if let error = error {
                    print("Receive error: \(error)")
                    self?.connection.cancel()
                    return
                }

                if let data = data {
                    print("Received data: \(data)")
                    let message = Message.fromData(data)
                    self?.replicatorConnection?.receive(message: message)
                } else {
                    print("Received nil data")
                }

                // Continue listening for messages.
                self?.receive()
            }
        }
    }
    
    // MARK: Cleanup
    
    private func cleanupConnection(_ connection: NWConnection) {
        // For passive peers, remove and stop the endpoint listener.
        if let messageEndpointListener = messageEndpointListeners.removeValue(forKey: HashableObject(connection)) {
            messageEndpointListener.closeAll()
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
