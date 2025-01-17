//
//  VerificationClientSecret.swift
//  StripeIdentity
//
//  Created by Mel Ludowise on 3/3/21.
//  Copyright © 2021 Stripe, Inc. All rights reserved.
//

import Foundation

struct VerificationClientSecret {

    let verificationSessionId: String
    let urlToken: String
}

extension VerificationClientSecret {
    private static let expectedComponentsCount = 4

    /**
     Initialize from string.
     - returns: nil if the client secret is invalid
     */
    init?(string: String) {
        // NOTE(mludowise): Setting `maxSplits` to `expectedComponentsCount`
        // means that if there are too many underscores, the components will be
        // equal to `expectedComponentsCount + 1`.
        // This means strings like "vi__123_secret_456" will fail validation.
        let components = string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "_",
                   maxSplits: VerificationClientSecret.expectedComponentsCount,
                   omittingEmptySubsequences: false)

        // Matching regex /^((vi|vs)_[0-9a-zA-Z]+)_secret_([0-9a-zA-Z]+)$/
        guard components.count == VerificationClientSecret.expectedComponentsCount &&
                (components[0] == "vi" || components[0] == "vs") &&
                !components[1].isEmpty &&
                (components[1].rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil) &&
                components[2] == "secret" &&
                !components[3].isEmpty &&
                (components[3].rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil) else {
            return nil
        }

        verificationSessionId = "\(components[0])_\(components[1])"
        urlToken = String(components[3])
    }

    // TODO(mludowise|IDPROD-2542): Recomposing the original string value is a
    // temporary workaround until we're no longer reliant on structured client
    // secrets
    var stringValue: String {
        return verificationSessionId + "_secret_" + urlToken
    }
}
