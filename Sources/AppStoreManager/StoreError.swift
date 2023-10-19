//
//  StoreError.swift
//  ReedWriteCycle (iOS)
//
//  Created by Kevin Mullins on 11/30/22.
//

import Foundation
import StoreKit
import LogManager

/// Holds an instance of an error thrown by the App `Storemanager`.
public enum StoreError: Error {
    case failedVerification
}
