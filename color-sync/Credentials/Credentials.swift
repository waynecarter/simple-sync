//
//  Credentials.swift
//  color-sync
//
//  Created by Wayne Carter on 4/29/23.
//

import Foundation

class Credentials {
    static func async(_ async: @escaping (SecIdentity, SecCertificate) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            async(identity, ca)
        }
    }
    
    // NOTE: To simplify the demo this pulls the client identity from a file
    // embedded in the app. In a realworld use-case the identity would more
    // than likely be managed using Keychain Services.
    private static let identity: SecIdentity = {
        let url = Bundle.main.url(forResource: "client_identity", withExtension: "p12")!
        let data = try! Data(contentsOf: url)
        
        var result: CFArray?
        let options: [String: Any] = [kSecImportExportPassphrase as String: ""]
        // NOTE: This method cannot be called on the main thread. That is why
        // the get function is async.
        let status = SecPKCS12Import(data as CFData, options as NSDictionary, &result)
        let items = result as! [[String: Any]]
        let item = items.first!
        let identity = item[kSecImportItemIdentity as String] as! SecIdentity
        
        return identity
    }()
    
    private static let ca: SecCertificate = {
        let url = Bundle.main.url(forResource: "ca_cert", withExtension: "der")!
        let data = try! Data(contentsOf: url)
        let ca = SecCertificateCreateWithData(nil, data as CFData)!
        
        return ca
    }()
}
