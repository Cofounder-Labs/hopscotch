import Foundation
import Cocoa
import Vision
import Security
import SwiftOpenAI

/// A service that provides access to both OpenAI and Azure OpenAI APIs using SwiftOpenAI package
class AzureOpenAIService {
    // Configuration
    private let endpoint: String
    private let apiKey: String
    private let apiVersion: String
    private let model: String
    private let serviceType: ServiceType
    
    // OpenAI Service
    private let service: OpenAIService
    
    // Hardcoded system prompt
    private let systemPrompt = "You are a helpful assistant. Analyze the screenshot and respond to the user's question. Be concise and informative."
    
    // Service Types
    enum ServiceType {
        case openAI
        case azureOpenAI
    }
    
    // Singleton instance for easy access
    static var shared = AzureOpenAIService()
    
    init() {
        // For development, you can set values here (REMOVE IN PRODUCTION)
        #if DEBUG
        // Determine if using Azure or OpenAI based on whether ENDPOINT is provided
        let hasAzureEndpoint = ProcessInfo.processInfo.environment["ENDPOINT"] != nil
        
        if hasAzureEndpoint {
            self.serviceType = .azureOpenAI
            self.endpoint = ProcessInfo.processInfo.environment["ENDPOINT"]!
            self.apiVersion = ProcessInfo.processInfo.environment["API_VERSION"] ?? "2023-05-15"
        } else {
            self.serviceType = .openAI
            self.endpoint = "https://api.openai.com"
            self.apiVersion = "v1"
        }
        
        // Read API key from environment variable for local development
        self.apiKey = ProcessInfo.processInfo.environment["API_KEY"] ?? ""
        self.model = ProcessInfo.processInfo.environment["MODEL"] ?? "gpt-4o"
        
        if apiKey.isEmpty {
            print("Warning: API_KEY environment variable not set for DEBUG build.")
        }
        #else
        // For production, use secure storage
        if getSecureConfigValue(forKey: "ENDPOINT") != nil {
            self.serviceType = .azureOpenAI
            self.endpoint = getSecureConfigValue(forKey: "ENDPOINT")!
            self.apiVersion = getSecureConfigValue(forKey: "API_VERSION") ?? "2023-05-15"
        } else {
            self.serviceType = .openAI
            self.endpoint = "https://api.openai.com"
            self.apiVersion = "v1"
        }
        
        self.apiKey = getSecureConfigValue(forKey: "API_KEY") ?? ""
        self.model = getSecureConfigValue(forKey: "MODEL") ?? "gpt-4o"
        #endif
        
        // Create the appropriate OpenAI service based on service type
        switch serviceType {
        case .openAI:
            // Use standard OpenAI service
            service = OpenAIServiceFactory.service(
                apiKey: apiKey, 
                overrideBaseURL: endpoint,
                overrideVersion: apiVersion
            )
            
        case .azureOpenAI:
            // For Azure, we don't need Authorization type - pass string directly
            service = OpenAIServiceFactory.service(
                apiKey: apiKey,
                overrideBaseURL: endpoint,
                overrideVersion: apiVersion
            )
        }
        
        print("Initialized \(serviceType == .azureOpenAI ? "Azure OpenAI" : "OpenAI") service")
    }
    
    /// Validates if all required configuration is set
    var isConfigured: Bool {
        return !endpoint.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }
    
    /// Securely retrieves a configuration value from the keychain
    private func getSecureConfigValue(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yourcompany.hopscotch.openai",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let retrievedData = dataTypeRef as? Data {
            return String(data: retrievedData, encoding: .utf8)
        }
        
        return nil
    }
    
    /// Store a configuration value securely in the keychain
    /// This should be called from a secure admin tool, not the end-user app
    func setSecureConfigValue(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yourcompany.hopscotch.openai",
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // First try to delete any existing key
        SecItemDelete(query as CFDictionary)
        
        // Then add the new key
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Takes a screenshot, combines it with text and sends to OpenAI or Azure OpenAI
    func sendScreenshotAndText(
        screenshot: NSImage, 
        text: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Convert image to base64
        guard let base64Image = convertImageToBase64(screenshot) else {
            completion(.failure(NSError(domain: "AzureOpenAIService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to base64"])))
            return
        }
        
        // Create base64 image URL
        let imageUrl = URL(string: "data:image/png;base64,\(base64Image)")!
        
        // Create message content objects
        let userMessageContents: [ChatCompletionParameters.Message.ContentType.MessageContent] = [
            .text(text),
            .imageUrl(ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(url: imageUrl))
        ]
        
        // Create message array
        let messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text(systemPrompt)),
            .init(role: .user, content: .contentArray(userMessageContents))
        ]
        
        // Create model parameter (custom for both - safer approach)
        let modelParam: Model = .custom(model)
        
        // Create parameters
        let parameters = ChatCompletionParameters(
            messages: messages,
            model: modelParam,
            maxTokens: 4000
        )
        
        // Log request details for debugging
        print("--- Sending API Request ---")
        print("Service Type: \(serviceType == .azureOpenAI ? "Azure OpenAI" : "OpenAI")")
        print("Model: \(model)")
        print("-------------------------")
        
        // Use Task to bridge between async/await and completion handler
        Task {
            do {
                let chatCompletion = try await service.startChat(parameters: parameters)
                if let choices = chatCompletion.choices, 
                   let firstChoice = choices.first,
                   let message = firstChoice.message,
                   let content = message.content {
                    completion(.success(content))
                } else {
                    completion(.failure(NSError(domain: "AzureOpenAIService", code: 4, userInfo: [NSLocalizedDescriptionKey: "No content in response"])))
                }
            } catch let apiError as APIError {
                switch apiError {
                case .responseUnsuccessful(let description, let statusCode):
                    print("API Error: \(description), Status Code: \(statusCode)")
                    completion(.failure(NSError(domain: "AzureOpenAIService", code: 500 + statusCode, userInfo: [NSLocalizedDescriptionKey: description])))
                default:
                    completion(.failure(apiError))
                }
            } catch {
                print("Unexpected error: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    /// For streaming responses - useful for real-time typing effect
    func sendScreenshotAndTextStreamed(
        screenshot: NSImage, 
        text: String,
        onContent: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        // Convert image to base64
        guard let base64Image = convertImageToBase64(screenshot) else {
            onComplete(.failure(NSError(domain: "AzureOpenAIService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to base64"])))
            return
        }
        
        // Create base64 image URL
        let imageUrl = URL(string: "data:image/png;base64,\(base64Image)")!
        
        // Create message content objects
        let userMessageContents: [ChatCompletionParameters.Message.ContentType.MessageContent] = [
            .text(text),
            .imageUrl(ChatCompletionParameters.Message.ContentType.MessageContent.ImageDetail(url: imageUrl))
        ]
        
        // Create message array
        let messages: [ChatCompletionParameters.Message] = [
            .init(role: .system, content: .text(systemPrompt)),
            .init(role: .user, content: .contentArray(userMessageContents))
        ]
        
        // Create model parameter (custom for both - safer approach)
        let modelParam: Model = .custom(model)
        
        // Create parameters for streaming
        let parameters = ChatCompletionParameters(
            messages: messages,
            model: modelParam,
            maxTokens: 4000
        )
        
        // Use Task to bridge between async/await and completion handler
        Task {
            do {
                let stream = try await service.startStreamedChat(parameters: parameters)
                
                // Process each chunk as it arrives
                for try await chunk in stream {
                    if let choices = chunk.choices, 
                       let firstChoice = choices.first,
                       let delta = firstChoice.delta,
                       let content = delta.content {
                        onContent(content)
                    }
                }
                
                onComplete(.success(()))
            } catch let apiError as APIError {
                switch apiError {
                case .responseUnsuccessful(let description, let statusCode):
                    print("Streaming API Error: \(description), Status Code: \(statusCode)")
                    onComplete(.failure(NSError(domain: "AzureOpenAIService", code: 500 + statusCode, userInfo: [NSLocalizedDescriptionKey: description])))
                default:
                    onComplete(.failure(apiError))
                }
            } catch {
                print("Unexpected streaming error: \(error.localizedDescription)")
                onComplete(.failure(error))
            }
        }
    }
    
    /// Convert an NSImage to base64 string
    private func convertImageToBase64(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation else { return nil }
        
        let bitmap = NSBitmapImageRep(data: tiffData)
        guard let pngData = bitmap?.representation(using: .png, properties: [:]) else { return nil }
        
        return pngData.base64EncodedString()
    }
} 
