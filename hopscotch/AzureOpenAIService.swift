import Foundation
import Cocoa
import Vision
import Security
import SwiftOpenAI

/// A service that provides access to both OpenAI and Azure OpenAI APIs
class AzureOpenAIService {
    // Service Types
    enum ServiceType {
        case openAI
        case azureOpenAI
    }
    
    // Configuration
    private let endpoint: String
    private let apiKey: String
    private let apiVersion: String
    private let model: String
    private let serviceType: ServiceType
    
    // OpenAI Service (used only for OpenAI, not for Azure)
    private let openAIService: OpenAIService?
    
    // Hardcoded system prompt
    private let systemPrompt = "You are a helpful assistant. Analyze the screenshot and respond to the user's question. Be concise and informative."
    
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
        
        // Initialize OpenAI service only for OpenAI (not for Azure)
        if serviceType == .openAI {
            openAIService = OpenAIServiceFactory.service(
                apiKey: apiKey,
                overrideBaseURL: endpoint,
                overrideVersion: apiVersion
            )
        } else {
            openAIService = nil
        }
        
        print("Initialized \(serviceType == .azureOpenAI ? "Azure OpenAI" : "OpenAI") service")
        if serviceType == .azureOpenAI {
            print("Using direct HTTP calls for Azure OpenAI")
            print("URL: \(endpoint)/openai/deployments/\(model)/chat/completions?api-version=\(apiVersion)")
            print("API Key: \(apiKey.isEmpty ? "Not set" : "Set (masked)")")
        } else {
            print("Using SwiftOpenAI package for OpenAI API")
        }
    }
    
    /// Validates if all required configuration is set
    var isConfigured: Bool {
        let baseConfigValid = !endpoint.isEmpty && !apiKey.isEmpty && !model.isEmpty
        return baseConfigValid
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
        
        // Use appropriate implementation based on service type
        switch serviceType {
        case .openAI:
            // Use SwiftOpenAI implementation for OpenAI
            sendViaSwiftOpenAI(base64Image: base64Image, text: text, completion: completion)
            
        case .azureOpenAI:
            // Use direct HTTP implementation for Azure
            sendViaDirectHTTP(base64Image: base64Image, text: text, completion: completion)
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
        
        // Use appropriate implementation based on service type
        switch serviceType {
        case .openAI:
            // Use SwiftOpenAI implementation for OpenAI
            sendStreamedViaSwiftOpenAI(base64Image: base64Image, text: text, onContent: onContent, onComplete: onComplete)
            
        case .azureOpenAI:
            // For now, Azure streaming is not fully implemented via direct HTTP
            // Future work would be to implement proper SSE handling
            sendViaDirectHTTP(base64Image: base64Image, text: text) { result in
                switch result {
                case .success(let content):
                    // Simulate streaming with the full content
                    onContent(content)
                    onComplete(.success(()))
                case .failure(let error):
                    onComplete(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Implementation using SwiftOpenAI for standard OpenAI API
    private func sendViaSwiftOpenAI(
        base64Image: String,
        text: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let openAIService = openAIService else {
            completion(.failure(NSError(domain: "AzureOpenAIService", code: 6, userInfo: [NSLocalizedDescriptionKey: "OpenAI Service not initialized"])))
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
        
        // Create model parameter
        let modelParam: Model = .custom(model)
        
        // Create parameters
        let parameters = ChatCompletionParameters(
            messages: messages,
            model: modelParam,
            maxTokens: 4000
        )
        
        // Log request details for debugging
        print("--- Sending API Request via SwiftOpenAI ---")
        print("Model: \(model)")
        print("-------------------------")
        
        // Use Task to bridge between async/await and completion handler
        Task {
            do {
                let chatCompletion = try await openAIService.startChat(parameters: parameters)
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
    
    /// Implementation for streaming with SwiftOpenAI
    private func sendStreamedViaSwiftOpenAI(
        base64Image: String,
        text: String,
        onContent: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let openAIService = openAIService else {
            onComplete(.failure(NSError(domain: "AzureOpenAIService", code: 6, userInfo: [NSLocalizedDescriptionKey: "OpenAI Service not initialized"])))
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
        
        // Create model parameter
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
                let stream = try await openAIService.startStreamedChat(parameters: parameters)
                
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
    
    /// Implementation using direct HTTP for Azure OpenAI
    private func sendViaDirectHTTP(
        base64Image: String,
        text: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Construct API URL for Azure OpenAI
        let apiUrl = "\(endpoint)/openai/deployments/\(model)/chat/completions?api-version=\(apiVersion)"
        let headers = ["Content-Type": "application/json", "api-key": apiKey]
        
        // Prepare request body
        let requestBody: [String: Any] = [
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": text
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/png;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 4000
        ]
        
        do {
            let requestData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            
            // Create the request
            guard let url = URL(string: apiUrl) else {
                completion(.failure(NSError(domain: "AzureOpenAIService", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            // Add headers
            for (headerField, value) in headers {
                request.addValue(value, forHTTPHeaderField: headerField)
            }
            
            request.httpBody = requestData
            
            // Log request details for debugging
            print("--- Sending Direct HTTP Request to Azure OpenAI ---")
            print("URL: \(request.url?.absoluteString ?? "Invalid URL")")
            print("Method: \(request.httpMethod ?? "N/A")")
   
            print("-------------------------")

            // Send the request
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                // For debugging, log the response status code
                if let httpResponse = response as? HTTPURLResponse {
                    print("Response Status Code: \(httpResponse.statusCode)")
                }
                
                guard let data = data else {
                    completion(.failure(NSError(domain: "AzureOpenAIService", code: 3, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }
                
                do {
                    // Parse the JSON response
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        completion(.success(content))
                    } else {
                        // If the expected structure doesn't match, return the raw response for debugging
                        if let rawResponse = String(data: data, encoding: .utf8) {
                            print("Raw API Response: \(rawResponse)")
                            completion(.failure(NSError(domain: "AzureOpenAIService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response: \(rawResponse)"])))
                        } else {
                            completion(.failure(NSError(domain: "AzureOpenAIService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to parse response"])))
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }
            
            task.resume()
            
        } catch {
            completion(.failure(error))
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
