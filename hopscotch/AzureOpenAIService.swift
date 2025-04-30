import Foundation
import Cocoa
import Vision
import Security

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
            // For Azure, deployment name is required and typically provided separately
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
        
        print("Initialized \(serviceType == .azureOpenAI ? "Azure OpenAI" : "OpenAI") service")
    }
    
    /// Validates if all required configuration is set
    var isConfigured: Bool {
        let baseConfigValid = !endpoint.isEmpty && !apiKey.isEmpty && !model.isEmpty
        
        // For Azure, we also need a deployment name
        if serviceType == .azureOpenAI {
            return baseConfigValid
        }
        
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
        
        // Construct API URL based on service type
        var apiUrl: String
        var headers: [String: String] = ["Content-Type": "application/json"]
        
        switch serviceType {
        case .openAI:
            apiUrl = "\(endpoint)/\(apiVersion)/chat/completions"
            headers["Authorization"] = "Bearer \(apiKey)"
        
        case .azureOpenAI:
            
            apiUrl = "\(endpoint)/openai/deployments/\(model)/chat/completions?api-version=\(apiVersion)"
            headers["api-key"] = apiKey
            
        }
        
        // Prepare request body - same for both services
        let requestBody: [String: Any] = [
            "model": serviceType == .openAI ? model : nil, // Only include model for OpenAI, not for Azure
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
        ].compactMapValues { $0 } // Remove nil values
        
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
            print("--- Sending API Request ---")
            print("Service Type: \(serviceType == .azureOpenAI ? "Azure OpenAI" : "OpenAI")")
            print("URL: \(request.url?.absoluteString ?? "Invalid URL")")
            print("Method: \(request.httpMethod ?? "N/A")")
            print("Headers: \(request.allHTTPHeaderFields ?? [:])")
            if request.httpBody != nil {
                print("Body: Set (contains image data)")
            } else {
                print("Body: Not set")
            }
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
                    // Parse the JSON response - same structure for both services
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
                            completion(.success("Failed to parse response: \(rawResponse)"))
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
