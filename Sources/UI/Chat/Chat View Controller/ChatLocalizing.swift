//
//  ChatLocalizing.swift
//  StreamChatClient
//
//  Created by Egemen Ayhan on 29.09.2020.
//  Copyright © 2020 Stream.io Inc. All rights reserved.
//

import Foundation
import StreamChatCore

public protocol ChatLocalizing {
    // MARK: - Message Actions
    var edit: String { get }
    var reply: String { get }
    var copy: String { get }
    var reactions: String { get }
    var mute: String { get }
    var unmute: String { get }
    var delete: String { get }
    var cancel: String { get }
    var deleteAlertTitle: String { get }
    var deletedMessageContent: String { get }
    // MARK: - Add File
    var addFileSheetTitle: String { get }
    var uploadMediaTitle: String { get }
    var uploadFromCameraTitle: String { get }
    var uploadFileTitle: String { get }
    // MARK: - PresenterItem
    var statusYesterdayTitle: String { get }
    var statusTodayTitle: String { get }
}

public extension ChatLocalizing {

    // MARK: - Message Actions
    var edit: String {
        return "Edit"
    }
    var reply: String {
        return "Reply"
    }
    var copy: String {
        return "Copy"
    }
    var reactions: String {
        return "Reactions"
    }
    var mute: String {
        return "Mute"
    }
    var unmute: String {
        return "Unmute"
    }
    var delete: String {
        return "Delete"
    }
    var cancel: String {
        return "Cancel"
    }
    var deleteAlertTitle: String {
        return "Delete message?"
    }
    var deletedMessageContent: String {
        return "Message was deleted"
    }

    // MARK: - Add File
    var addFileSheetTitle: String {
        return "Add a file"
    }
    var uploadMediaTitle: String {
        return "Upload a photo or video"
    }
    var uploadFromCameraTitle: String {
        return "Upload from camera"
    }
    var uploadFileTitle: String {
        return "Upload a file"
    }

    // MARK: - PresenterItem
    var statusYesterdayTitle: String {
        return "Yesterday"
    }
    var statusTodayTitle: String {
        return "Today"
    }

}

public struct ChatLocalizer: ChatLocalizing {

    public init() {
        PresenterItem.statusYesterdayTitle = statusYesterdayTitle
        PresenterItem.statusTodayTitle = statusTodayTitle
    }

}
