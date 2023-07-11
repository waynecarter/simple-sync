//
//  AppService.swift
//  simple-sync
//
//  Created by Wayne Carter on 4/29/23.
//

import os
import Foundation
import Network
import UIKit
import CouchbaseLiteSwift
import Combine

final class App {
    private let name: String
    private let database: CouchbaseLiteSwift.Database
    private let collections: [CouchbaseLiteSwift.Collection]
    var endpoint: App.Endpoint? {
        didSet {
            // When the endpoint changes, restart.
            if endpoint != oldValue {
                restart()
            }
        }
    }
    private let conflictResolver: ConflictResolverProtocol?
    private let identity: SecIdentity
    private let ca: SecCertificate
    
    private let uuid = UUID().uuidString
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections = [NWConnection]()
    private var messageEndpointListener: MessageEndpointListener
    private var messageEndpointConnections = [HashableObject : NMMessageEndpointConnection]()
    private var replicators = [HashableObject : Replicator]()
    private var endpointReplicator: Replicator?
    
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkQueue", target: .global())
    
    private var cancellables = Set<AnyCancellable>()
    
    struct Endpoint: Equatable {
        let url: URL
        let username: String?
        let password: String?

        static func == (lhs: Endpoint, rhs: Endpoint) -> Bool {
            return lhs.url == rhs.url &&
                   lhs.username == rhs.username &&
                   lhs.password == rhs.password
        }
    }
    
    // MARK: - Init
    
    convenience init(database: CouchbaseLiteSwift.Database, identity: SecIdentity, ca: SecCertificate) {
        self.init(database: database, conflictResolver: nil, identity: identity, ca: ca)
    }

    convenience init(database: CouchbaseLiteSwift.Database, conflictResolver: ConflictResolverProtocol?, identity: SecIdentity, ca: SecCertificate) {
        self.init(name: database.name, database: database, collections: [try! database.defaultCollection()], endpoint: nil, conflictResolver: conflictResolver, identity: identity, ca: ca)
    }

    convenience init(database: CouchbaseLiteSwift.Database, endpoint: App.Endpoint?, identity: SecIdentity, ca: SecCertificate) {
        self.init(database: database, endpoint: endpoint, conflictResolver: nil, identity: identity, ca: ca)
    }

    convenience init(database: CouchbaseLiteSwift.Database, endpoint: App.Endpoint?, conflictResolver: ConflictResolverProtocol?, identity: SecIdentity, ca: SecCertificate) {
        self.init(name: database.name, database: database, collections: [try! database.defaultCollection()], endpoint: endpoint, conflictResolver: conflictResolver, identity: identity, ca: ca)
    }

    init(name: String, database: CouchbaseLiteSwift.Database, collections: [CouchbaseLiteSwift.Collection], endpoint: App.Endpoint?, conflictResolver: ConflictResolverProtocol?, identity: SecIdentity, ca: SecCertificate) {
        self.name = name
        self.database = database
        self.collections = collections
        self.conflictResolver = conflictResolver
        self.endpoint = endpoint
        self.identity = identity
        self.ca = ca
        
        // Create the message endpoint lister for incoming connections.
        let config = MessageEndpointListenerConfiguration(collections: collections, protocolType: .byteStream)
        messageEndpointListener = MessageEndpointListener(config: config)
        
        // Monitor the network and pause/resume when connectivity changes.
        networkMonitor.pathUpdateHandler = { [weak self] path in
            switch path.status {
            case .satisfied:
                Log.info("Network is available")
                self?.restart()
            default:
                Log.info("Network is unavailable")
                self?.pause()
            }
        }
        networkMonitor.start(queue: networkQueue)
        
        // Monitor the app's background state and, when the app enters the background, start a background task.
        var backgroundTask: UIBackgroundTaskIdentifier?
        NotificationCenter.default.addObserver( forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            backgroundTask = UIApplication.shared.beginBackgroundTask {
                self?.networkQueue.sync { [weak self] in
                    self?.pause()
                    
                    // If we have a background task, end it.
                    if let backgroundTask = backgroundTask {
                        UIApplication.shared.endBackgroundTask(backgroundTask)
                    }
                    backgroundTask = nil
                }
            }
        }
        
        // Monitor the app's background state and restart when the app enters the foreground.
        var willEnterForeground = false
        NotificationCenter.default.addObserver( forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
            willEnterForeground = true
            
            // If we have a background task, end it.
            if let backgroundTask = backgroundTask {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            backgroundTask = nil
            
            // Restart the replicator.
            self?.restart()
        }
        
        // Monitor the app's actve state and restart when the app becomes active.
        NotificationCenter.default.addObserver( forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            if willEnterForeground == false {
                self?.restart()
            }
            willEnterForeground = false
        }
    }
    
    // MARK: - Deinit
    
    deinit {
        // Stop the app.
        pause()
        
        // Cancel app background state observers.
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        
        // Cancel app active state observer.
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    // MARK: - Start/Stop
    
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
            
            // Create and start the listener and browser.
            listener = createListener()
            browser = createBrowser()
            listener?.start(queue: networkQueue)
            browser?.start(queue: networkQueue)
            
            // Create and start the endpoint replicator.
            endpointReplicator = createEndpointReplicator()
            endpointReplicator?.start()
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
            
            // Stop and nullify the endpoint replicator.
            endpointReplicator?.stop()
            endpointReplicator = nil
            
            // Clean up all connections.
            connections.forEach { connection in
                cleanupConnection(connection)
            }
            
            // Close all active message endpoint connections.
            messageEndpointListener.closeAll()
        }
    }
    
    // Internal function for pausing/resuming.
    private func restart() {
        networkQueue.async { [weak self] in
            self?.pause()
            self?.resume()
        }
    }
    
    // MARK: - Trust verification

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
    
    // MARK: - Network setup
    
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
    
    private struct ConnectionEvents {
        static let available = "available"
        static let ready = "ready"
    }
    
    private func createListener() -> NWListener? {
        // Create the NWListener
        var listener: NWListener!
        do {
            listener = try NWListener(
                service: NWListener.Service(name: uuid, type: "_\(name)._tcp"),
                using: networkParameters
            )
        } catch {
            Log.error("Failed to create listener: \(error)")
            return nil
        }
        
        // Handle new connections.
        // NOTE: Connection lifecycle events are numbered and work in coordination
        // with the Browser's connection lifecycle
        listener.newConnectionHandler = { [weak self] connection in
            guard let self = self else { return }
            
            Log.info("New browser connection: \(connection)")
           
            // 1. Send the local peer's UUID to the remote peer.
            connection.send(content: self.uuid.data(using: .ascii), contentContext: .defaultMessage, isComplete: true, completion: .idempotent)
            // 2. Wait for the remote peer's UUID.
            connection.receive(minimumIncompleteLength: self.uuid.count, maximumLength: self.uuid.count) { [weak self] (data, _, _, _) in
                // Read the remote peer's UUID.
                guard let self = self,
                      let data = data,
                      let remoteUUIDString = String(data: data, encoding: .ascii),
                      let remoteUUID = UUID(uuidString: remoteUUIDString)?.uuidString else
                {
                    self?.cleanupConnection(connection)
                    return
                }
                
                // Don't connect to the local peer's service.
                guard remoteUUID != self.uuid else {
                    self.cleanupConnection(connection)
                    return
                }
                
                // Don't connect to a remote peer more than once.
                guard !self.connections.contains(where: { self.serviceNameFor($0.endpoint) == remoteUUID }) else {
                    Log.info("Skipping browser connection: \(remoteUUID)")
                    self.cleanupConnection(connection)
                    return
                }
                
                // 3. Send the message that the local peer's listener is available for connections by the remote peer.
                connection.send(content: ConnectionEvents.available.data(using: .ascii), contentContext: .defaultMessage, isComplete: true, completion: .idempotent)
                // 4. Wait for the message that the remote peer's browser is available for connections by the local peer.
                connection.receive(minimumIncompleteLength: ConnectionEvents.available.count, maximumLength: ConnectionEvents.available.count) { [weak self] (data, _, _, _) in
                    // Read the message.
                    guard let self = self, let data = data, let message = String(data: data, encoding: .ascii) else {
                        self?.cleanupConnection(connection)
                        return
                    }
                    
                    // Don't connect to the remote peer if it's not available for connections by the local peer.
                    guard message == ConnectionEvents.available else {
                        Log.info("Skipping browser connection: \(remoteUUID)")
                        self.cleanupConnection(connection)
                        return
                    }
                    
                    // Monitor connection state, connecting and disconnecting as the state changes.
                    connection.stateUpdateHandler = { [weak self] newState in
                        guard let self = self else { return }
                        
                        switch newState {
                        case .ready:
                            Log.info("Connection ready: \(connection)")
                            self.connections.append(connection)
                            self.setupMessageEndpointConnection(connection)
                            
                            // 5. Send the message that the local peer's is ready for a connection by the remote peer.
                            connection.send(content: ConnectionEvents.ready.data(using: .ascii), contentContext: .defaultMessage, isComplete: true, completion: .idempotent)
                        case .failed(let error):
                            Log.error("Connection failed with error: \(error)")
                            self.cleanupConnection(connection)
                        case .cancelled:
                            Log.info("Connection cancelled: \(connection)")
                            self.cleanupConnection(connection)
                        default:
                            break
                        }
                    }
                    connection.stateUpdateHandler?(connection.state)
                }
            }
            
            // Start the connection.
            connection.start(queue: self.networkQueue)
        }
        
        // Monitor the listener state.
        listener.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                Log.info("Listener is ready")
            case .failed(let error):
                Log.error("Listener stopped with error: \(error)")
            case .cancelled:
                Log.info("Listener stopped with state: cancelled")
            default:
                break
            }
        }
        
        return listener
    }

    private func createBrowser() -> NWBrowser {
        // Create the NWBrowser
        let browserDescriptor = NWBrowser.Descriptor.bonjour(type: "_\(name)._tcp", domain: nil)
        let browser = NWBrowser(for: browserDescriptor, using: networkParameters)
        
        // Handle discovered peers.
        // NOTE: Connection lifecycle events are numbered and work in coordination
        // with the Listener's connection lifecycle
        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            
            for change in changes {
                switch change {
                case .added(let result):
                    // Create a new connection for the remote peer's endpoint.
                    let connection = NWConnection(to: result.endpoint, using: self.networkParameters)
                    
                    Log.info("New listener connection: \(connection)")
                    
                    // 1. Send the local peer's UUID to the remote peer.
                    connection.send(content: self.uuid.data(using: .ascii), contentContext: .defaultMessage, isComplete: true, completion: .idempotent)
                    // 2. Wait for the remote peer's UUID.
                    connection.receive(minimumIncompleteLength: self.uuid.count, maximumLength: self.uuid.count) { [weak self] (data, _, _, _) in
                        // Read the remote peer's UUID.
                        guard let self = self, let data = data,
                              let remoteUUIDString = String(data: data, encoding: .ascii),
                              let remoteUUID = UUID(uuidString: remoteUUIDString)?.uuidString else
                        {
                            self?.cleanupConnection(connection)
                            return
                        }
                        
                        // Don't connect to the local peer's service.
                        guard remoteUUID != self.uuid else {
                            self.cleanupConnection(connection)
                            return
                        }
                        
                        // Don't connect to a remote peer more than once.
                        guard !self.connections.contains(where: { self.serviceNameFor($0.endpoint) == remoteUUID }) else {
                            Log.info("Skipping listener connection: \(remoteUUID)")
                            self.cleanupConnection(connection)
                            return
                        }
                        
                        // 3. Send the message that the local peer's browser is available for connections by the remote peer.
                        connection.send(content: ConnectionEvents.available.data(using: .ascii), contentContext: .defaultMessage, isComplete: true, completion: .idempotent)
                        // 4. Wait for the message that the remote peer's listener is available for connections by the local peer.
                        connection.receive(minimumIncompleteLength: ConnectionEvents.available.count, maximumLength: ConnectionEvents.available.count) { [weak self] (data, _, _, _) in
                            // Read the message.
                            guard let self = self, let data = data, let message = String(data: data, encoding: .ascii) else {
                                self?.cleanupConnection(connection)
                                return
                            }
                            
                            // Don't connect to the remote peer if it's not available for connections by the local peer.
                            guard message == ConnectionEvents.available else {
                                Log.info("Skipping listener connection: \(remoteUUID)")
                                self.cleanupConnection(connection)
                                return
                            }
                        
                            // 5. Wait for the message that the remote peer is ready for a connection by the local peer.
                            connection.receive(minimumIncompleteLength: ConnectionEvents.ready.count, maximumLength: ConnectionEvents.ready.count) { [weak self] (data, _, _, _) in
                                // Read the message.
                                guard let self = self, let data = data, let message = String(data: data, encoding: .ascii) else {
                                    self?.cleanupConnection(connection)
                                    return
                                }
                                
                                // Don't connect to the remote peer if it's not ready for connections by the local peer.
                                guard message == ConnectionEvents.ready else {
                                    Log.info("Skipping listener connection: \(remoteUUID)")
                                    self.cleanupConnection(connection)
                                    return
                                }
                                
                                // Monitor connection state, connecting and disconnecting as the state changes.
                                connection.stateUpdateHandler = { [weak self] newState in
                                    guard let self = self else { return }
                                    
                                    switch newState {
                                    case .ready:
                                        Log.info("Connection ready: \(connection)")
                                        self.connections.append(connection)
                                        self.setupReplicator(for: connection)
                                    case .failed(let error):
                                        Log.error("Connection failed with error: \(error)")
                                        self.cleanupConnection(connection)
                                    case .cancelled:
                                        Log.info("Connection cancelled: \(connection)")
                                        self.cleanupConnection(connection)
                                    default:
                                        break
                                    }
                                }
                                connection.stateUpdateHandler?(connection.state)
                            }
                        }
                    }
                    
                    // Start the connection.
                    connection.start(queue: self.networkQueue)
                case .removed(let result):
                    Log.info("Lost service: \(result.endpoint)")
                    if let connection = self.connections.first(where: { $0.endpoint == result.endpoint }) {
                        self.cleanupConnection(connection)
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
                Log.error("Browser stopped with error: \(error)")
            case .cancelled:
                Log.info("Browser stopped with state: cancelled")
            default:
                break
            }
        }
        
        return browser
    }

    // MARK: - Couchbase Lite Replication
    
    private func createEndpointReplicator() -> Replicator? {
        guard let endpoint = endpoint else { return nil }
        
        // Append the name of the app as the last path component of the endpoint URL.
        let url = endpoint.url.appending(path: name)
        
        // Set up the target endpoint.
        let target = URLEndpoint(url: url)
        var config = ReplicatorConfiguration(target: target)
        config.replicatorType = .pushAndPull
        config.continuous = true
        config.allowReplicatingInBackground = true
        
        // If the endpoint has a username and password then use then assign a basic
        // authenticator using the credentials.
        if let username = endpoint.username, let password = endpoint.password {
            config.authenticator = BasicAuthenticator(username: username, password: password)
        }

        // Set up the collection config.
        var collectionConfig = CollectionConfiguration()
        collectionConfig.conflictResolver = conflictResolver
        config.addCollections(collections, config: collectionConfig)

        // Create and return the replicator.
        let endpointReplicator = Replicator(config: config)
        return endpointReplicator
    }
    
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
        config.allowReplicatingInBackground = true
        
        var collectionConfig = CollectionConfiguration()
        collectionConfig.conflictResolver = conflictResolver
        config.addCollections(collections, config: collectionConfig)
        
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
                    Log.error("Send error: \(error)")
                    completion(true, CouchbaseLiteSwift.MessagingError(error: error, isRecoverable: false))
                } else {
                    completion(true, nil)
                }
            }))
        }
        
        private func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, _, error) in
                if let error = error {
                    Log.error("Receive error: \(error)")
                    self?.replicatorConnection?.close(
                        error: MessagingError(error: error, isRecoverable: false)
                    )
                    self?.connection.cancel()
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
    
    // MARK: - Cleanup
    
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
        static private let logger = OSLog(subsystem: "count-sync", category: "network")
        
        static func info(_ message: String) {
            log(message, type: .info)
        }
        
        static func error(_ message: String) {
            log(message, type: .error)
        }
        
        private static func log(_ message: String, type: OSLogType) {
            let isDebuggerAttached = isatty(STDERR_FILENO) != 0
            
            if isDebuggerAttached {
                print(message)
            } else {
                os_log("%{public}@", log: logger, type: type, message)
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
