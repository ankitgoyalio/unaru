//
//  KiteLogin+Identity.swift
//  unaru
//
//  Created by Ankit Goyal on 05/11/2026.

import Foundation
import KiteConnect
import Shared

extension KiteLogin {
    /// Restricts avatar requests to public HTTPS addresses without credentials or query data.
    static func identity(_ profile: KiteUserProfile) -> AccountProfile {
        let url = profile.avatarURL.flatMap(URL.init(string:))
        let safe = url.flatMap { url -> URL? in
            guard url.scheme == "https", url.host != nil, url.user == nil, url.password == nil,
                  url.query == nil, url.fragment == nil else { return nil }
            return url
        }
        return AccountProfile(
            name: profile.userName, userID: profile.userID, avatarURL: safe,
            email: profile.email, broker: profile.broker, accountType: profile.userType,
            exchanges: profile.exchanges.map(\.rawValue), products: profile.products.map(\.rawValue),
            orderTypes: profile.orderTypes.map(\.rawValue),
        )
    }
}
