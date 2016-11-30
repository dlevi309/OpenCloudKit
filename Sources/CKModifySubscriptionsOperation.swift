//
//  CKModifySubscriptionsOperation.swift
//  OpenCloudKit
//
//  Created by Ben Johnson on 12/07/2016.
//
//

import Foundation

public class CKModifySubscriptionsOperation : CKDatabaseOperation {
    
    public init(subscriptionsToSave: [CKSubscription]?, subscriptionIDsToDelete: [String]?) {
        super.init()
        
        self.subscriptionsToSave = subscriptionsToSave
        self.subscriptionIDsToDelete = subscriptionIDsToDelete
    }
    
    public var subscriptionsToSave: [CKSubscription]?
    public var subscriptionIDsToDelete: [String]?
    
    /*  This block is called when the operation completes.
     The [NSOperation completionBlock] will also be called if both are set.
     If the error is CKErrorPartialFailure, the error's userInfo dictionary contains
     a dictionary of subscriptionIDs to errors keyed off of CKPartialErrorsByItemIDKey.
     */
    public var modifySubscriptionsCompletionBlock: (([CKSubscription]?, [String]?, Error?) -> Void)?
    
    func operationsDictionary() -> [[String: Any]] {
        var operations: [[String: Any]] = []
        
        if let subscriptionsToSave = subscriptionsToSave {
            
            for subscription in subscriptionsToSave {
                
                let operation: [String: Any] = [
                    "operationType": "create".bridge(),
                    "subscription": subscription.subscriptionDictionary.bridge() as Any
                ]
                
                operations.append(operation)
            }
        }
        
        if let subscriptionIDsToDelete = subscriptionIDsToDelete {
            for subscriptionID in subscriptionIDsToDelete {
                
                let operation: [String: Any] = [
                    "operationType": "create".bridge(),
                    "subscription": (["subscriptionID": subscriptionID.bridge()] as [String: Any]).bridge() as Any
                ]
                
                operations.append(operation)
            }
        }
        
        return operations
    }
    
    override func performCKOperation() {
        
        let url = "\(operationURL)/subscriptions/modify"
        
        let request: [String: Any] = ["operations": operationsDictionary().bridge() as Any]
        
        urlSessionTask = CKWebRequest(container: operationContainer).request(withURL: url, parameters: request) { (dictionary, networkError) in
            if let error = networkError {
                self.modifySubscriptionsCompletionBlock?(nil, nil, error)
                
            } else if let dictionary = dictionary {
                
                if let subscriptionsDictionary = dictionary["subscriptions"] as? [[String: Any]] {
                    // Parse JSON into CKRecords
                    var subscriptions: [CKSubscription] = []
                    var deletedSubscriptionIDs: [String] = []
                    
                    for subscriptionDictionary in subscriptionsDictionary {
                        
                        if let subscription = CKSubscription(dictionary: subscriptionDictionary) {
                            // Append Record
                            subscriptions.append(subscription)
                           
                        } else if let subscriptionID = subscriptionDictionary["subscriptionID"] as? String {
                            deletedSubscriptionIDs.append(subscriptionID)
                
                        } else if let subscriptionFetchError = CKSubscriptionFetchErrorDictionary(dictionary: subscriptionDictionary) {
                            
                            // Create Error
                            let error = NSError(domain: CKErrorDomain, code: CKErrorCode.PartialFailure.rawValue, userInfo: [NSLocalizedDescriptionKey: subscriptionFetchError.reason])
                           
                            self.modifySubscriptionsCompletionBlock?(nil, nil, error)

                        } else {
                            fatalError("Couldn't resolve record or record fetch error dictionary")
                        }
                    }
                    
                    self.modifySubscriptionsCompletionBlock?(subscriptions, deletedSubscriptionIDs, nil)
                }
            }
        }
        
        urlSessionTask?.resume()
        
    }
}
