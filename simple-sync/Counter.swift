//
//  Counter.swift
//  simple-sync
//
//  Created by Wayne Carter on 6/10/23.
//

import Foundation
import CouchbaseLiteSwift

// MARK: - Counter

class Counter {
    private let document: Document
    private let key: String

    init(document: Document, key: String) {
        self.document = document
        self.key = key
    }
    
    var value: Int {
        // Get the counter and return the merged value.
        let counter = document[key].dictionary
        return counter?["value"].int ?? 0
    }
}

// MutableCounter manages the counter value of a document field using the
// sturcture specified in the CRDTConflictResolver comments.
class MutableCounter: Counter {
    private let document: MutableDocument
    private let key: String
    private let actor: String

    init(document: MutableDocument, key: String, actor: String) {
        self.document = document
        self.key = key
        self.actor = actor
        
        super.init(document: document, key: key)
    }
    
    func increment(by amount: UInt) {
        // Get the counter.
        let counter = document[key].dictionary ?? {
            let counter = MutableDictionaryObject(data: ["type": "pn-counter"])
            document[key].dictionary = counter
            return counter
        }()
        
        // Get the positive counter.
        let p = counter["p"].dictionary ?? {
            let p = MutableDictionaryObject()
            counter["p"].dictionary = p
            return p
        }()
        
        // Increment the value for the actor.
        p[actor].int = p[actor].int + Int(amount)
        
        // Set the new merged value.
        counter["value"].int = mergedValue(
            p: p,
            n: counter["n"].dictionary
        )
    }

    func decrement(by amount: UInt) {
        // Get the counter.
        let counter = document[key].dictionary ?? {
            let counter = MutableDictionaryObject(data: ["type": "pn-counter"])
            document[key].dictionary = counter
            return counter
        }()
        
        // Get the negative counter.
        let n = counter["n"].dictionary ?? {
            let n = MutableDictionaryObject()
            counter["n"].dictionary = n
            return n
        }()
        
        // Decrement the value for the actor.
        n[actor].int = n[actor].int + Int(amount)
        
        // Set the new merged value.
        counter["value"].int = mergedValue(
            p: counter["p"].dictionary,
            n: n
        )
    }
    
    private func mergedValue(p: DictionaryObject?, n: DictionaryObject?) -> Int {
        // Sum the positive counter values.
        let pCounterValue = p?.toDictionary().values.reduce(0, { partialResult, value in
            if let value = value as? Int {
                return partialResult + value
            } else {
                return partialResult
            }
        }) ?? 0
        
        // Sum the negative counter values.
        let nCounterValue = n?.toDictionary().values.reduce(0, { partialResult, value in
            if let value = value as? Int {
                return partialResult + value
            } else {
                return partialResult
            }
        }) ?? 0
        
        // Return the difference between positive and negative counter values.
        return pCounterValue - nCounterValue
    }
}

// MARK: - Couchbase Lite Extensions

extension CouchbaseLiteSwift.Document {
    func counter(forKey key: String) -> Counter? {
        return Counter(document: self, key: key)
    }
}

extension CouchbaseLiteSwift.MutableDocument {
    func counter(forKey key: String, actor: String) -> MutableCounter {
        return MutableCounter(document: self, key: key, actor: actor)
    }
}

extension CouchbaseLiteSwift.ConflictResolver {
    public static var crdt: CouchbaseLiteSwift.ConflictResolverProtocol = CRDTConflictResolver.shared
}

extension CouchbaseLiteSwift.Database {
    var uuid: String {
        if let uuid = UserDefaults.standard.string(forKey: "\(name).uuid") {
            return uuid
        } else {
            let uuid = UUID().uuidString
            UserDefaults.standard.set(uuid, forKey: "\(name).uuid")
            return uuid
        }
    }
}

// MARK: - CRDT Conflict Resolver

// `CRDTConflictResolver` is a conflict resolver that resolves conflicts for documents that
// contain top-level fields of type "pn-counter" using the Conflict-free Replicated Data
// Type (CRDT) structure and logic. For all other fields, it uses the default conflict
// resolver provided by Couchbase Lite.
//
// The "pn-counter" field values have the following structure:
// "count": {
//    "type": "pn-counter",
//    "value": 35,
//    "p": {
//        "actor1": 10,
//        "actor2": 15,
//        "actor3": 20
//     },
//     "n": {
//        "actor1": 2,
//        "actor2": 3,
//        "actor3": 5
//     }
// }
//
// In this structure, "actor1", "actor2", and "actor3" are the identifiers for different
// actors that have incremented or decremented the counter. The "p" object represents the
// increments made by each actor, and the "n" object represents the decrements. The "value"
// field represents the merged value of the counter, which is the sum of all values in "p"
// minus the sum of all values in "n".
class CRDTConflictResolver: ConflictResolverProtocol {
    static let shared: CRDTConflictResolver = CRDTConflictResolver()
    
    func resolve(conflict: Conflict) -> Document? {
        // Use the default conflict resolver for initial resolution
        let defaultResolver = ConflictResolver.default
        guard let resolvedDoc = defaultResolver.resolve(conflict: conflict)?.toMutable() else {
            return nil
        }
        
        // If either the localDocument or remoteDocument are null, return the default resolved doc.
        guard let localDocument = conflict.localDocument, let remoteDocument = conflict.remoteDocument else {
            return resolvedDoc
        }
        
        // Iterate over all keys in the local and remote documents.
        let localAndRemoteKeys = Set(localDocument.keys).union(remoteDocument.keys)
        for key in localAndRemoteKeys {
            // Check if either the local or remote document has a "pn-counter" type field for the current key.
            if localDocument[key].dictionary?["type"].string == "pn-counter" || remoteDocument[key].dictionary?["type"].string == "pn-counter" {
                // Initialize counters for the positive (p) and negative (n) values.
                var pCounterValue = 0
                var nCounterValue = 0

                // Iterate over the "p" and "n" keys.
                for counterKey in ["p", "n"] {
                    // Get the "p" or "n" dictionary from the local and remote documents, or create a new one if it doesn't exist.
                    let localCounter = localDocument[key].dictionary?[counterKey].dictionary ?? MutableDictionaryObject()
                    let remoteCounter = remoteDocument[key].dictionary?[counterKey].dictionary ?? MutableDictionaryObject()
                    // Initialize a new dictionary to hold the merged counter values.
                    let mergedCounter = MutableDictionaryObject()

                    // Iterate over all actors in the local and remote counters.
                    for actor in Set(localCounter.keys).union(remoteCounter.keys) {
                        // Get the local and remote values for the current actor, or 0 if they don't exist.
                        let localValue = localCounter[actor].int
                        let remoteValue = remoteCounter[actor].int
                        // The merged value is the maximum of the local and remote values.
                        let maxValue = max(localValue, remoteValue)
                        mergedCounter[actor].int = maxValue

                        // Add the merged value to the appropriate counter.
                        if counterKey == "p" {
                            pCounterValue += maxValue
                        } else if counterKey == "n" {
                            nCounterValue += maxValue
                        }
                    }

                    // If the merged counter has any entries, set it in the resolved document.
                    // Otherwise, remove the "p" or "n" key from the resolved document.
                    if mergedCounter.count > 0 {
                        resolvedDoc[key].dictionary?[counterKey].dictionary = mergedCounter
                    } else {
                        resolvedDoc[key].dictionary?.removeValue(forKey: counterKey)
                    }
                }

                // Set the "value" field in the resolved document to the difference between the "p" and "n" counters.
                resolvedDoc[key].dictionary?["value"].int = pCounterValue - nCounterValue
            }
        }

        return resolvedDoc
    }
}
