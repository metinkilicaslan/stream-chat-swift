//
// Copyright © 2020 Stream.io Inc. All rights reserved.
//

import CoreData
import Foundation

@objc(MessageDTO)
class MessageDTO: NSManagedObject {
    static let entityName = "MessageDTO"
    
    @NSManaged var id: String
    @NSManaged var text: String
    @NSManaged var type: String
    @NSManaged var command: String?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var deletedAt: Date?
    @NSManaged var args: String?
    @NSManaged var parentId: String?
    @NSManaged var showReplyInChannel: Bool
    @NSManaged var replyCount: Int32
    @NSManaged var extraData: Data
    @NSManaged var isSilent: Bool
    @NSManaged var reactionScores: [String: Int]
    
    @NSManaged var user: UserDTO
    @NSManaged var mentionedUsers: Set<UserDTO>
    @NSManaged var channel: ChannelDTO
    
    @NSManaged fileprivate var additionalStateRaw: String?
    
    /// Returns a fetch request for messages from the channel with the provided `cid`.
    static func messagesFetchRequest(for cid: ChannelId) -> NSFetchRequest<MessageDTO> {
        let request = NSFetchRequest<MessageDTO>(entityName: MessageDTO.entityName)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MessageDTO.createdAt, ascending: false)]
        request.predicate = NSPredicate(format: "channel.cid == %@", cid.rawValue)
        return request
    }
    
    static func load(for cid: String, limit: Int, offset: Int = 0, context: NSManagedObjectContext) -> [MessageDTO] {
        let request = NSFetchRequest<MessageDTO>(entityName: entityName)
        request.predicate = NSPredicate(format: "channel.cid == %@", cid)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MessageDTO.createdAt, ascending: false)]
        request.fetchLimit = limit
        request.fetchOffset = offset
        return try! context.fetch(request)
    }
    
    static func load(id: String, context: NSManagedObjectContext) -> MessageDTO? {
        let request = NSFetchRequest<MessageDTO>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id)
        return try! context.fetch(request).first
    }
    
    static func loadOrCreate(id: String, context: NSManagedObjectContext) -> MessageDTO {
        if let existing = load(id: id, context: context) {
            return existing
        }
        
        let new = NSEntityDescription.insertNewObject(forEntityName: entityName, into: context) as! Self
        new.id = id
        return new
    }
}

extension MessageDTO {
    /// The additional state of the message. This is valid only locally and is not synchronized with the backend.
    var additionalState: AdditionalState? {
        get { additionalStateRaw.flatMap(AdditionalState.init) }
        set { additionalStateRaw = newValue?.rawValue }
    }
}

extension NSManagedObjectContext {
    func saveMessage<ExtraData: ExtraDataTypes>(payload: MessagePayload<ExtraData>, for cid: ChannelId) throws -> MessageDTO {
        let dto = MessageDTO.loadOrCreate(id: payload.id, context: self)
        
        dto.text = payload.text
        dto.createdAt = payload.createdAt
        dto.updatedAt = payload.updatedAt
        dto.deletedAt = payload.deletedAt
        dto.type = payload.type.rawValue
        dto.command = payload.command
        dto.args = payload.args
        dto.parentId = payload.parentId
        dto.showReplyInChannel = payload.showReplyInChannel
        dto.replyCount = Int32(payload.replyCount)
        dto.extraData = try JSONEncoder.default.encode(payload.extraData)
        dto.isSilent = payload.isSilent
        dto.reactionScores = payload.reactionScores
        dto.channel = ChannelDTO.loadOrCreate(cid: cid, context: self)
        
        let user = try saveUser(payload: payload.user)
        dto.user = user
        
        try payload.mentionedUsers.forEach { userPayload in
            let user = try saveUser(payload: userPayload)
            dto.mentionedUsers.insert(user)
        }
        
        return dto
    }
    
    func loadMessage<ExtraData: ExtraDataTypes>(id: MessageId) -> MessageModel<ExtraData>? {
        loadMessageDTO(id: id).map(MessageModel.init(fromDTO:))
    }
    
    func loadMessageDTO(id: MessageId) -> MessageDTO? {
        MessageDTO.load(id: id, context: self)
    }
    
    func createMessage(id: MessageId,
                       text: String,
                       createdAt: Date = Date(),
                       showReplyInChannel: Bool = false,
                       extraData: Data = Data([])) throws -> MessageDTO {
        guard loadMessageDTO(id: id) == nil else {
            throw ClientError.MessageAlreadyExist(id: id)
        }
        
        let dto = MessageDTO.loadOrCreate(id: id, context: self)
        dto.text = text
        dto.type = MessageType.regular.rawValue
        dto.createdAt = createdAt
        dto.updatedAt = createdAt
        dto.showReplyInChannel = showReplyInChannel
        dto.extraData = extraData
        dto.isSilent = false
        dto.replyCount = 0
        dto.reactionScores = [:]
        return dto
    }
}

extension MessageModel {
    init(fromDTO dto: MessageDTO) {
        id = dto.id
        text = dto.text
        type = MessageType(rawValue: dto.type) ?? .regular
        command = dto.command
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        deletedAt = dto.deletedAt
        args = dto.args
        parentId = dto.parentId
        showReplyInChannel = dto.showReplyInChannel
        replyCount = Int(dto.replyCount)
        extraData = try! JSONDecoder.default.decode(ExtraData.Message.self, from: dto.extraData)
        isSilent = dto.isSilent
        reactionScores = dto.reactionScores
        additionalState = dto.additionalState
        
        author = UserModel.create(fromDTO: dto.user)
        mentionedUsers = Set(dto.mentionedUsers.map(UserModel<ExtraData.User>.create(fromDTO:)))
    }
}

extension ClientError {
    class MessageAlreadyExist: ClientError {
        init(id: MessageId) {
            super.init("Message with the id:\(id) already exists.")
        }
    }
}
