//
// Copyright © 2020 Stream.io Inc. All rights reserved.
//

import CoreData
@testable import StreamChatClient
import XCTest

class ChatClient_Tests: StressTestCase {
    var userId: UserId!
    private var testEnv: TestEnvironment<DefaultExtraData>!
    
    // A helper providing ChatClientConfic with in-memory DB option
    var inMemoryStorageConfig: ChatClientConfig {
        var config = ChatClientConfig()
        config.isLocalStorageEnabled = false
        config.baseURL = BaseURL(urlString: .unique)!
        return config
    }
    
    override func setUp() {
        super.setUp()
        userId = .unique
        testEnv = .init()
    }
    
    override func tearDown() {
        testEnv.apiClient?.cleanUp()
        AssertAsync.canBeReleased(&testEnv)
        super.tearDown()
    }
    
    var workerBuilders: [WorkerBuilder] = [
        MessageSender<DefaultExtraData>.init,
        NewChannelQueryUpdater<DefaultExtraData>.init,
        ChannelWatchStateUpdater<DefaultExtraData>.init
    ]
    
    // MARK: - Database stack tests
    
    func test_clientDatabaseStackInitialization_whenLocalStorageEnabled_respectsConfigValues() {
        // Prepare a config with the local storage
        let storeFolderURL = URL.newTemporaryDirectoryURL()
        var config = ChatClientConfig()
        config.isLocalStorageEnabled = true
        config.shouldFlushLocalStorageOnStart = true
        config.localStorageFolderURL = storeFolderURL
        
        var usedDatabaseKind: DatabaseContainer.Kind?
        var shouldFlushDBOnStart: Bool?
        
        // Create env object with custom database builder
        var env = ChatClient.Environment()
        env.databaseContainerBuilder = { kind, shouldFlushOnStart in
            usedDatabaseKind = kind
            shouldFlushDBOnStart = shouldFlushOnStart
            return DatabaseContainerMock()
        }
        
        // Create a `Client` and assert that a DB file is created on the provided URL + APIKey path
        _ = ChatClient(config: config, workerBuilders: [Worker.init], environment: env)
        XCTAssertEqual(
            usedDatabaseKind,
            .onDisk(databaseFileURL: storeFolderURL.appendingPathComponent(config.apiKey.apiKeyString))
        )
        XCTAssertEqual(shouldFlushDBOnStart, config.shouldFlushLocalStorageOnStart)
    }
    
    func test_clientDatabaseStackInitialization_whenLocalStorageDisabled() {
        // Prepare a config with the in-memory storage
        var config = ChatClientConfig()
        config.isLocalStorageEnabled = false
        
        var usedDatabaseKind: DatabaseContainer.Kind?
        
        // Create env object with custom database builder
        var env = ChatClient.Environment()
        env.databaseContainerBuilder = { kind, _ in
            usedDatabaseKind = kind
            return DatabaseContainerMock()
        }
        
        // Create a `Client` and assert the correct DB kind is used
        _ = ChatClient(config: config, workerBuilders: [Worker.init], environment: env)
        
        XCTAssertEqual(usedDatabaseKind, .inMemory)
    }
    
    /// When the initialization of a local DB fails for some reason (i.e. incorrect URL),
    /// use a DB in the in-memory configuration
    func test_clientDatabaseStackInitialization_useInMemoryWhenOnDiskFails() {
        // Prepare a config with the local storage
        let storeFolderURL = URL.newTemporaryDirectoryURL()
        var config = ChatClientConfig()
        config.isLocalStorageEnabled = true
        config.localStorageFolderURL = storeFolderURL
        
        var usedDatabaseKinds: [DatabaseContainer.Kind] = []
        
        // Prepare a queue with errors the db builder should return. We want to return an error only the first time
        // when we expect the DB is created with the local DB option and we want it to fail.
        var errorsToReturn = Queue<Error>()
        errorsToReturn.push(TestError())

        // Create env object and store all `kinds it's called with.
        var env = ChatClient.Environment()
        env.databaseContainerBuilder = { kind, _ in
            usedDatabaseKinds.append(kind)
            // Return error for the first time
            if let error = errorsToReturn.pop() {
                throw error
            }
            // Return a new container the second time
            return DatabaseContainerMock()
        }
        
        // Create a chat client and assert `Client` tries to initialize the local DB, and when it fails, it falls back
        // to the in-memory option.
        _ = ChatClient(config: config, workerBuilders: [Worker.init], environment: env)
        
        XCTAssertEqual(
            usedDatabaseKinds,
            [.onDisk(databaseFileURL: storeFolderURL.appendingPathComponent(config.apiKey.apiKeyString)), .inMemory]
        )
    }
    
    // MARK: - WebSocketClient tests
    
    func test_webSocketClientIsInitialized() throws {
        // Use in-memory store
        // Create a new chat client
        let client = ChatClient(
            config: inMemoryStorageConfig,
            workerBuilders: workerBuilders,
            environment: testEnv.environment
        )
        
        // Assert the init parameters are correct
        let webSocket = testEnv.webSocketClient
        assertMandatoryHeaderFields(webSocket?.init_sessionConfiguration)
        XCTAssert(webSocket?.init_requestEncoder is TestRequestEncoder)
        XCTAssertNotNil(webSocket?.init_eventDecoder)
        
        // EventDataProcessorMiddleware must be always first
        XCTAssert(webSocket?.init_eventNotificationCenter.middlewares[0] is EventDataProcessorMiddleware<DefaultExtraData>)
        
        // Assert Client sets itself as delegate for the request encoder
        XCTAssert(webSocket?.init_requestEncoder.connectionDetailsProviderDelegate === client)
    }
    
    func test_webSocketClient_hasAllMandatoryMiddlewares() throws {
        // Use in-memory store
        // Create a new chat client, which in turn creates a webSocketClient
        _ = ChatClient(
            config: inMemoryStorageConfig,
            workerBuilders: workerBuilders,
            environment: testEnv.environment
        )
        
        // Assert that mandatory middlewares exists
        let middlewares = try XCTUnwrap(testEnv.webSocketClient?.init_eventNotificationCenter.middlewares)
        
        // Assert `EventDataProcessorMiddleware` exists
        XCTAssert(middlewares.contains(where: { $0 is EventDataProcessorMiddleware<DefaultExtraData> }))
        // Assert `TypingStartCleanupMiddleware` exists
        let typingStartCleanupMiddlewareIndex = middlewares.firstIndex { $0 is TypingStartCleanupMiddleware<DefaultExtraData> }
        XCTAssertNotNil(typingStartCleanupMiddlewareIndex)
        // Assert `ChannelReadUpdaterMiddleware` exists
        XCTAssert(middlewares.contains(where: { $0 is ChannelReadUpdaterMiddleware<DefaultExtraData> }))
        // Assert `ChannelMemberTypingStateUpdaterMiddleware` exists
        let typingStateUpdaterMiddlewareIndex = middlewares
            .firstIndex { $0 is ChannelMemberTypingStateUpdaterMiddleware<DefaultExtraData> }
        XCTAssertNotNil(typingStateUpdaterMiddlewareIndex)
        // Assert `ChannelMemberTypingStateUpdaterMiddleware` goes after `TypingStartCleanupMiddleware`
        XCTAssertTrue(typingStateUpdaterMiddlewareIndex! > typingStartCleanupMiddlewareIndex!)
    }
    
    func test_connectionStatus_isExposed() {
        // Create a new chat client
        let client = ChatClient(
            config: inMemoryStorageConfig,
            workerBuilders: workerBuilders,
            environment: testEnv.environment
        )

        // Simulate connection state change of WSClient
        let error = ClientError(with: TestError())
        testEnv.webSocketClient?.simulateConnectionStatus(.disconnected(error: error))
        
        // Assert the WSConnectionState is exposed as ChatClientConnectionStatus
        XCTAssertEqual(client.connectionStatus, .disconnected(error: error))
    }
    
    // MARK: - ConnectionDetailsProvider tests
    
    func test_clientProvidesConnectionId() throws {
        // Create a new chat client
        let client = ChatClient(
            config: inMemoryStorageConfig,
            workerBuilders: workerBuilders,
            environment: testEnv.environment
        )
        
        // Set a connection Id waiter and assert it's `nil`
        var providedConnectionId: ConnectionId?
        client.provideConnectionId {
            providedConnectionId = $0
        }
        XCTAssertNil(providedConnectionId)
        
        // Simulate WebSocketConnection change
        testEnv.webSocketClient?.connectionStateDelegate?
            .webSocketClient(testEnv.webSocketClient!, didUpdateConectionState: .connecting)
        
        AssertAsync.staysTrue(providedConnectionId == nil)
        
        // Simulate WebSocket connected and connection id is provided
        testEnv.webSocketClient?.connectionStateDelegate?
            .webSocketClient(testEnv.webSocketClient!, didUpdateConectionState: .connecting)
        let connectionId: ConnectionId = .unique
        testEnv.webSocketClient?.connectionStateDelegate?
            .webSocketClient(testEnv.webSocketClient!, didUpdateConectionState: .connected(connectionId: connectionId))
        
        AssertAsync.willBeEqual(providedConnectionId, connectionId)
        XCTAssertEqual(try await { client.provideConnectionId(completion: $0) }, connectionId)
        
        // Simulate WebSocketConnection disconnecting and assert connectionId is reset
        testEnv.webSocketClient?.connectionStateDelegate?
            .webSocketClient(testEnv.webSocketClient!, didUpdateConectionState: .connecting)
        
        providedConnectionId = nil
        client.provideConnectionId {
            providedConnectionId = $0
        }
        AssertAsync.staysTrue(providedConnectionId == nil)
    }
    
    func test_clientProvidesToken_fromTokenProvider() throws {
        let newUserId: UserId = .unique
        let newToken: Token = .unique
        
        var config = inMemoryStorageConfig
        config.tokenProvider = { apiKey, userId, completion in
            XCTAssertEqual(apiKey, config.apiKey)
            XCTAssertEqual(userId, newUserId)
            completion(newToken)
        }
        
        // Create a new chat client
        let client = ChatClient(
            config: config,
            workerBuilders: workerBuilders,
            environment: testEnv.environment
        )
        
        // Assert the token of anonymous user is `nil`
        XCTAssertNil(client.provideToken())
        
        // Set a new user without an explicit token
        client.currentUserController().setUser(userId: newUserId)
        
        AssertAsync.willBeEqual(client.provideToken(), newToken)
    }
    
    // MARK: - APIClient tests
    
    func test_apiClientIsInitialized() throws {
        // Create a new chat client
        _ = ChatClient(
            config: inMemoryStorageConfig,
            workerBuilders: workerBuilders,
            environment: testEnv.environment
        )
        
        assertMandatoryHeaderFields(testEnv.apiClient?.init_sessionConfiguration)
        XCTAssert(testEnv.apiClient?.init_requestDecoder is TestRequestDecoder)
        XCTAssert(testEnv.apiClient?.init_requestEncoder is TestRequestEncoder)
    }
    
    // MARK: - Background workers tests
    
    func test_productionClientIsInitalizedWithAllMandatoryBackgroundWorkers() {
        // Create a new Client with production configuration
        let config = ChatClientConfig(apiKey: .init(.unique))
        let client = _ChatClient<DefaultExtraData>(config: config)
        
        // Check all the mandatory background workers are initialized
        XCTAssert(client.backgroundWorkers.contains { $0 is MessageSender<DefaultExtraData> })
        XCTAssert(client.backgroundWorkers.contains { $0 is NewChannelQueryUpdater<DefaultExtraData> })
        XCTAssert(client.backgroundWorkers.contains { $0 is ChannelWatchStateUpdater<DefaultExtraData> })
        XCTAssert(client.backgroundWorkers.contains { $0 is MessageEditor<DefaultExtraData> })
        XCTAssert(client.backgroundWorkers.contains { $0 is MissingEventsPublisher<DefaultExtraData> })
    }
    
    func test_backgroundWorkersAreInitialized() {
        // Set up mocks for APIClient, WSClient and Database
        let config = ChatClientConfig(apiKey: .init(.unique))
        
        // Prepare a test worker
        class TestWorker: Worker {
            var init_database: DatabaseContainer?
            var init_webSocketClient: WebSocketClient?
            var init_apiClient: APIClient?
            
            override init(database: DatabaseContainer, webSocketClient: WebSocketClient, apiClient: APIClient) {
                init_database = database
                init_webSocketClient = webSocketClient
                init_apiClient = apiClient
                
                super.init(database: database, webSocketClient: webSocketClient, apiClient: apiClient)
            }
        }
        
        // Create a Client instance and check the TestWorker is initialized properly
        let client = _ChatClient(
            config: config,
            workerBuilders: [TestWorker.init],
            environment: testEnv.environment
        )
        
        let testWorker = client.backgroundWorkers.first as? TestWorker
        XCTAssert(testWorker?.init_database is DatabaseContainerMock)
        XCTAssert(testWorker?.init_webSocketClient is WebSocketClientMock)
        XCTAssert(testWorker?.init_apiClient is APIClientMock)
    }
    
    // MARK: - Setting a new current user tests
    
    func test_defaultUserIsAnonymous() {
        let client = ChatClient(config: inMemoryStorageConfig)
        
        // The current userId should be set, but the user is not loaded before the connection is established
        XCTAssertTrue(client.currentUserId.isAnonymousUser)
        XCTAssertNil(testEnv.databaseContainer?.viewContext.currentUser())
    }
    
    func test_settingUser_resetsBackgroundWorkers() {
        // TestWorker to be used for checking if workers are re-created
        class TestWorker: Worker {
            let id = UUID()
        }
        
        // Custom workerBuilders for ChatClient, including only TestWorker
        let workerBuilders: [WorkerBuilder] = [TestWorker.init]
        
        // Create ChatClient
        let client = _ChatClient(
            config: inMemoryStorageConfig,
            workerBuilders: workerBuilders,
            environment: testEnv.environment
        )
        
        let currentUserController = client.currentUserController()

        // Generate userIds for first user
        let oldUserId: UserId = .unique
        let oldUserToken: Token = .unique
        
        // Set a user
        currentUserController.setUser(userId: oldUserId, token: oldUserToken)

        // Save worker's UUID
        let oldWorkerUUID = (client.backgroundWorkers.first as! TestWorker).id
        
        // Set the same user again
        currentUserController.setUser(userId: oldUserId, token: oldUserToken)

        // .. to make sure worker's are not re-created for the same user
        XCTAssertEqual((client.backgroundWorkers.first as! TestWorker).id, oldWorkerUUID)
        
        // Generate userIds for second user
        let newUserId: UserId = .unique
        let newUserToken: Token = .unique
        
        // Set a user
        currentUserController.setUser(userId: newUserId, token: newUserToken)

        // Check if the worker is re-created
        XCTAssertNotEqual((client.backgroundWorkers.first as! TestWorker).id, oldWorkerUUID)
    }
}

/// A helper class which provides mock environment for Client.
private class TestEnvironment<ExtraData: ExtraDataTypes> {
    @Atomic var apiClient: APIClientMock?
    @Atomic var webSocketClient: WebSocketClientMock?
    @Atomic var databaseContainer: DatabaseContainerMock?
    
    @Atomic var requestEncoder: TestRequestEncoder?
    @Atomic var requestDecoder: TestRequestDecoder?
    
    @Atomic var eventDecoder: EventDecoder<ExtraData>?
    
    lazy var environment: _ChatClient<ExtraData>.Environment = { [unowned self] in
        .init(
            apiClientBuilder: {
                self.apiClient = APIClientMock(sessionConfiguration: $0, requestEncoder: $1, requestDecoder: $2)
                return self.apiClient!
            },
            webSocketClientBuilder: {
                self.webSocketClient = WebSocketClientMock(
                    connectEndpoint: $0,
                    sessionConfiguration: $1,
                    requestEncoder: $2,
                    eventDecoder: $3,
                    eventNotificationCenter: $4,
                    internetConnection: $5
                )
                return self.webSocketClient!
            },
            databaseContainerBuilder: {
                self.databaseContainer = try! DatabaseContainerMock(kind: $0, shouldFlushOnStart: $1)
                return self.databaseContainer!
            },
            requestEncoderBuilder: {
                if let encoder = self.requestEncoder {
                    return encoder
                }
                self.requestEncoder = TestRequestEncoder(baseURL: $0, apiKey: $1)
                return self.requestEncoder!
            },
            requestDecoderBuilder: {
                self.requestDecoder = TestRequestDecoder()
                return self.requestDecoder!
            },
            eventDecoderBuilder: {
                self.eventDecoder = EventDecoder<ExtraData>()
                return self.eventDecoder!
            }
        )
    }()
}

extension ChatClient_Tests {
    /// Asserts that URLSessionConfiguration contains all require header fields
    private func assertMandatoryHeaderFields(
        _ config: URLSessionConfiguration?,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let config = config else {
            XCTFail("Config is `nil`", file: file, line: line)
            return
        }
        
        let headers = config.httpAdditionalHeaders as? [String: String] ?? [:]
        XCTAssertEqual(
            headers["X-Stream-Client"],
            "stream-chat-swift-client-\(SystemEnvironment.version)"
                + "|\(SystemEnvironment.deviceModelName)"
                + "|\(SystemEnvironment.systemName)"
                + "|\(SystemEnvironment.name)"
        )
    }
}

private struct Queue<Element> {
    @Atomic private var storage = [Element]()
    mutating func push(_ element: Element) {
        storage.append(element)
    }
    
    mutating func pop() -> Element? {
        let first = storage.first
        storage = Array(storage.dropFirst())
        return first
    }
}

private extension ChatClientConfig {
    init() {
        self = .init(apiKey: APIKey(.unique))
    }
}

// MARK: - Mock

class WebSocketClientMock: WebSocketClient {
    let init_connectEndpoint: Endpoint<EmptyResponse>
    let init_sessionConfiguration: URLSessionConfiguration
    let init_requestEncoder: RequestEncoder
    let init_eventDecoder: AnyEventDecoder
    let init_eventNotificationCenter: EventNotificationCenter
    let init_internetConnection: InternetConnection
    let init_reconnectionStrategy: WebSocketClientReconnectionStrategy
    let init_environment: WebSocketClient.Environment
    
    @Atomic var connect_calledCounter = 0
    @Atomic var disconnect_calledCounter = 0
    
    override init(
        connectEndpoint: Endpoint<EmptyResponse>,
        sessionConfiguration: URLSessionConfiguration,
        requestEncoder: RequestEncoder,
        eventDecoder: AnyEventDecoder,
        eventNotificationCenter: EventNotificationCenter,
        internetConnection: InternetConnection,
        reconnectionStrategy: WebSocketClientReconnectionStrategy = DefaultReconnectionStrategy(),
        environment: WebSocketClient.Environment = .init()
    ) {
        init_connectEndpoint = connectEndpoint
        init_sessionConfiguration = sessionConfiguration
        init_requestEncoder = requestEncoder
        init_eventDecoder = eventDecoder
        init_eventNotificationCenter = eventNotificationCenter
        init_internetConnection = internetConnection
        init_reconnectionStrategy = reconnectionStrategy
        init_environment = environment
        
        super.init(
            connectEndpoint: connectEndpoint,
            sessionConfiguration: sessionConfiguration,
            requestEncoder: requestEncoder,
            eventDecoder: eventDecoder,
            eventNotificationCenter: eventNotificationCenter,
            internetConnection: internetConnection,
            reconnectionStrategy: reconnectionStrategy,
            environment: environment
        )
    }
    
    override func connect() {
        _connect_calledCounter { $0 += 1 }
    }
    
    override func disconnect(source: WebSocketConnectionState.DisconnectionSource = .userInitiated) {
        _disconnect_calledCounter { $0 += 1 }
    }
}

extension WebSocketClientMock {
    convenience init() {
        self.init(
            connectEndpoint: .init(path: "", method: .get, queryItems: nil, requiresConnectionId: false, body: nil),
            sessionConfiguration: .default,
            requestEncoder: DefaultRequestEncoder(baseURL: .unique(), apiKey: .init(.unique)),
            eventDecoder: EventDecoder<DefaultExtraData>(),
            eventNotificationCenter: .init(),
            internetConnection: InternetConnection()
        )
    }
}
