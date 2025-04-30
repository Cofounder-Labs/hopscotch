import Foundation
import Cocoa
import Vision
import Security

class AzureOpenAIService {
    // Configuration
    private let azureEndpoint: String
    private let apiKey: String
    private let apiVersion: String
    private let model: String
    
    // Hardcoded system prompt
    private let systemPrompt = "You are a helpful assistant. Analyze the screenshot and respond to the user's question. Be concise and informative."
    
    // Singleton instance for easy access
    static var shared = AzureOpenAIService()
    
    init() {
        // For development, you can set values here (REMOVE IN PRODUCTION)
        #if DEBUG
        self.azureEndpoint = ProcessInfo.processInfo.environment["AZURE_ENDPOINT"] ?? "https://api.openai.com"
        // Read API key from environment variable for local development
        self.apiKey = ProcessInfo.processInfo.environment["AZURE_API_KEY"] ?? ""
        self.apiVersion = "v1"  // For OpenAI API
        self.model = ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-4o"
        if apiKey.isEmpty {
            print("Warning: OPENAI_API_KEY environment variable not set for DEBUG build.")
        }
        #else
        // For production, use secure storage
        self.azureEndpoint = getSecureConfigValue(forKey: "OPENAI_ENDPOINT") ?? ""
        self.apiKey = getSecureConfigValue(forKey: "OPENAI_API_KEY") ?? ""
        self.apiVersion = "v1"  // This doesn't need to be secret
        self.model = getSecureConfigValue(forKey: "OPENAI_MODEL") ?? "gpt-4o"
        #endif
    }
    
    /// Validates if all required configuration is set
    var isConfigured: Bool {
        return !azureEndpoint.isEmpty && !apiKey.isEmpty && !model.isEmpty
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
    
    /// Takes a screenshot, combines it with text and sends to OpenAI
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
        
        // Construct API URL - direct OpenAI API
        let apiUrl = "\(azureEndpoint)/\(apiVersion)/chat/completions"
        
        // Prepare request body
        let requestBody: [String: Any] = [
            "model": model,
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
            var request = URLRequest(url: URL(string: apiUrl)!)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            // Different header key for OpenAI API
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = requestData
            
            // Send the request
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
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
                        // If the expected structure doesn't match, return the raw response
                        if let rawResponse = String(data: data, encoding: .utf8) {
                            completion(.success(rawResponse))
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
