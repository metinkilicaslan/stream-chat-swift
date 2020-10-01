//
//  ChannelsLocalizing.swift
//  StreamChat
//
//  Created by Egemen Ayhan on 30.09.2020.
//  Copyright © 2020 Stream.io Inc. All rights reserved.
//

import Foundation
import StreamChatCore

public protocol ChannelsLocalizing {

    // MARK: - Last Message Info
    var deletedMessageInfo: String { get }
    var noMessageInfo: String { get }

    // MARK: - PresenterItem
    var statusYesterdayTitle: String { get }
    var statusTodayTitle: String { get }

}

public extension ChannelsLocalizing {

    // MARK: - Last Message Info
    var deletedMessageInfo: String {
        return "Message was deleted"
    }
    var noMessageInfo: String {
        return "No messages"
    }

    // MARK: - PresenterItem
    var statusYesterdayTitle: String {
        return "Yesterday"
    }
    var statusTodayTitle: String {
        return "Today"
    }

}

public struct ChannelsLocalizer: ChannelsLocalizing {

    public init() {
        PresenterItem.statusYesterdayTitle = statusYesterdayTitle
        PresenterItem.statusTodayTitle = statusTodayTitle
    }

}
