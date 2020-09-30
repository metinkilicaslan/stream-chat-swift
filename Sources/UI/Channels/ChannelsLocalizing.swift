//
//  ChannelsLocalizing.swift
//  StreamChatClient
//
//  Created by Egemen Ayhan on 30.09.2020.
//  Copyright © 2020 Stream.io Inc. All rights reserved.
//

import Foundation

public protocol ChannelsLocalizing {

    // MARK: - Last Message Info
    var deletedMessageInfo: String { get }
    var noMessageInfo: String { get }

}

public extension ChannelsLocalizing {

    var deletedMessageInfo: String {
        return "Message was deleted"
    }
    var noMessageInfo: String {
        return "No messages"
    }

}

public struct ChannelsLocalizer: ChannelsLocalizing {
    public init() {}
}
