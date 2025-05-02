import Foundation
import Cocoa
import Vision
import Security
import CoreGraphics // Added for CGRect

/// A service that provides access to both OpenAI and Azure OpenAI APIs
/// Configuration Keys:
/// - For OpenAI: API_KEY, MODEL (ENDPOINT must NOT be set)
/// - For Azure OpenAI: ENDPOINT, API_KEY, MODEL (API_VERSION optional, defaults in code)
class AzureOpenAIService: AIServiceProtocol {
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
    
    // Hardcoded system prompt for simple text/image queries
    private let simpleSystemPrompt = "You are a helpful assistant. Analyze the screenshot and respond to the user's question. Be concise and informative."
    
    // New system prompt for complex action-oriented queries
    private let actionSystemPrompt = """
    You are an expert macOS assistant. Your goal is to help the user perform actions within applications based on their query and the provided context (screenshot, active app name, bounding box of interest, open apps, chat history).

    Analyze the user's query, the screenshot, the active application name ('appName'), the list of open applications ('openApps'), the bounding box of the active element ('boundingBox'), and the recent 'chatHistory'.

    Determine if the user's query pertains to the *active* application shown in the screenshot.

    **If the query IS about the active application:**
    Respond with a JSON object containing:
    - "responseType": "success"
    - "annotationCoordinates": { "x": Double, "y": Double, "width": Double, "height": Double } - Coordinates relative to the screenshot (top-left origin) indicating the UI element to interact with. Calculate these based on the screenshot content and the user query's goal.
    - "annotationText": String - Very short text for the annotation overlay (e.g., "Click here", "Right-click", "Type here").
    - "plan": String - A concise, numbered step-by-step plan for the user (e.g., "1. Right-click the highlighted button. 2. Select 'Mark as Unread' from the menu.").

    **If the query is NOT about the active application but seems to be about another open application:**
    Respond with a JSON object containing:
    - "responseType": "retry"
    - "suggestedApp": String - The name of the application (from the 'openApps' list if possible) that the query likely refers to.

    **Important:**
    - Base your coordinate calculations on the visual content of the screenshot.
    - Ensure the JSON response strictly follows one of the two formats described above.
    - Be precise and concise in your 'annotationText' and 'plan'.
    - If unsure, prioritize the 'retry' response with the most likely app.
    """
    
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
        if let azureEndpoint = getSecureConfigValue(forKey: "ENDPOINT"), !azureEndpoint.isEmpty {
            self.serviceType = .azureOpenAI
            self.endpoint = azureEndpoint
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
        print("Using direct HTTP calls for \(serviceType == .azureOpenAI ? "Azure OpenAI" : "OpenAI")")

        if serviceType == .azureOpenAI {
            print("URL Structure: \(endpoint)/openai/deployments/\(model)/chat/completions?api-version=\(apiVersion)")
        } else {
             print("URL Structure: \(endpoint)/\(apiVersion)/chat/completions")
        }
         print("Model: \(model)")
         
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
        
        // Use the unified HTTP implementation directly
        sendViaHTTP(base64Image: base64Image, text: text, completion: completion)
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
        
        // TODO: Implement proper HTTP streaming (SSE) for both OpenAI and Azure
        // For now, using the non-streaming HTTP call and delivering the full content at once.
        print("Note: Streaming is not yet implemented via direct HTTP. Sending full response.")
        sendViaHTTP(base64Image: base64Image, text: text) { result in
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
    
    // MARK: - Private Methods
    
    /// Implementation using direct HTTP for both Azure OpenAI and standard OpenAI
    private func sendViaHTTP(
        base64Image: String,
        text: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Construct API URL and headers based on service type
        let apiUrl: String
        let headers: [String: String]

        switch serviceType {
        case .openAI:
            apiUrl = "\(endpoint)/\(apiVersion)/chat/completions"
            headers = [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(apiKey)"
            ]
        case .azureOpenAI:
            apiUrl = "\(endpoint)/openai/deployments/\(model)/chat/completions?api-version=\(apiVersion)"
            headers = [
                "Content-Type": "application/json",
                "api-key": apiKey
            ]
        }

        // Prepare request body (common structure for both)
        let requestBody: [String: Any] = [
            "messages": [
                [
                    "role": "system",
                    "content": simpleSystemPrompt
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
            "max_tokens": 4000,
            "model": model // Include model for standard OpenAI API
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
            print("--- Sending Direct HTTP Request (sendViaHTTP) ---")
            print("Service Type: \(serviceType)")
            print("URL: \(request.url?.absoluteString ?? "Invalid URL")")
            print("Method: \(request.httpMethod ?? "N/A")")
            
            // Print body only if small/necessary, avoid logging sensitive data like image
            // print("Body: \(String(data: requestData, encoding: .utf8) ?? "Could not decode body")") 
            print("--------------------------------------------------")

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
    
    // MARK: - New Method Implementation
    
    func getAIAction(
        appName: String,
        userQuery: String,
        screenshot: NSImage,
        chatHistory: [String],
        boundingBox: CGRect,
        openApps: [String],
        completion: @escaping (Result<AIActionResponse, Error>) -> Void
    ) {
        // Convert image to base64
        guard let base64Image = convertImageToBase64(screenshot) else {
            completion(.failure(NSError(domain: "AzureOpenAIService", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to convert screenshot to base64"])))
            return
        }
        
        // Call the dedicated HTTP helper for this complex query
        sendActionRequestViaHTTP(
            appName: appName,
            userQuery: userQuery,
            base64Image: base64Image,
            chatHistory: chatHistory,
            boundingBox: boundingBox,
            openApps: openApps,
            completion: completion
        )
    }
    
    /// Sends the complex action request via HTTP and parses the structured response.
    private func sendActionRequestViaHTTP(
        appName: String,
        userQuery: String,
        base64Image: String,
        chatHistory: [String],
        boundingBox: CGRect,
        openApps: [String],
        completion: @escaping (Result<AIActionResponse, Error>) -> Void
    ) {
        // Construct API URL and headers (same logic as sendViaHTTP)
        let apiUrl: String
        let headers: [String: String]

        switch serviceType {
        case .openAI:
            apiUrl = "\(endpoint)/\(apiVersion)/chat/completions"
            headers = [
                "Content-Type": "application/json",
                "Authorization": "Bearer \(apiKey)"
            ]
        case .azureOpenAI:
            apiUrl = "\(endpoint)/openai/deployments/\(model)/chat/completions?api-version=\(apiVersion)"
            headers = [
                "Content-Type": "application/json",
                "api-key": apiKey
            ]
        }

        // Prepare request body
        // Combine all context into a structured text prompt for the user role,
        // supplementing the detailed instructions in the system prompt.
        let contextText = """
        User Query: "\(userQuery)"
        Active Application: \(appName)
        Active Element Bounding Box (x,y,width,height): (\(boundingBox.origin.x), \(boundingBox.origin.y), \(boundingBox.size.width), \(boundingBox.size.height))
        Open Applications: \(openApps.joined(separator: ", "))
        Chat History:
        \(chatHistory.joined(separator: "\n"))
        """
        
        let requestBody: [String: Any] = [
            "messages": [
                [
                    "role": "system",
                    "content": actionSystemPrompt // Use the new system prompt
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": contextText
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
            "max_tokens": 1000, // Adjust as needed, might need fewer tokens for structured JSON
            "model": model,
             // Enforce JSON output if the model/API supports it (check API docs)
             // Example for OpenAI API (might vary for Azure):
             "response_format": [ "type": "json_object" ]
        ]

        do {
            let requestData = try JSONSerialization.data(withJSONObject: requestBody, options: [.prettyPrinted]) // Pretty print for debug
            
            guard let url = URL(string: apiUrl) else {
                completion(.failure(NSError(domain: "AzureOpenAIService", code: 11, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL for action request"])))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            headers.forEach { request.addValue($1, forHTTPHeaderField: $0) }
            request.httpBody = requestData
            
            // Log request details for debugging
            print("--- Sending Action Request HTTP (sendActionRequestViaHTTP) ---")
            print("Service Type: \(serviceType)")
            print("URL: \(request.url?.absoluteString ?? "Invalid URL")")
            print("Method: \(request.httpMethod ?? "N/A")")
          
            // Log the body JSON structure (excluding image potentially)
            if let bodyString = String(data: requestData, encoding: .utf8) {
                 // Basic redaction attempt for base64 image data - use standard string escaping
                 let regexPattern = "\"url\": \"data:image/png;base64,[^\\\"\\}]*\"" // Correctly escaped regex
                 let replacement = "\"url\": \"data:image/png;base64,<REDACTED>\""
                 let redactedBody = bodyString.replacingOccurrences(of: regexPattern, with: replacement, options: .regularExpression)
                 print("Request Body (JSON):\n\(redactedBody)")
             } else {
                 print("Could not decode request body")
             }
            print("-----------------------------------------------------------")

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                     completion(.failure(NSError(domain: "AzureOpenAIService", code: 12, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])))
                    return
                 }

                 print("Action Request Response Status Code: \(httpResponse.statusCode)")

                guard let data = data else {
                    completion(.failure(NSError(domain: "AzureOpenAIService", code: 13, userInfo: [NSLocalizedDescriptionKey: "No data received for action request"])))
                    return
                }
                 
                 // Log raw response for debugging
                 if let rawResponse = String(data: data, encoding: .utf8) {
                      print("Raw Action API Response: \(rawResponse)")
                 } else {
                     print("Could not decode raw action API response")
                 }

                do {
                    // Attempt to parse the primary response structure (choices -> message -> content)
                     guard let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                           let choices = jsonResponse["choices"] as? [[String: Any]],
                           let firstChoice = choices.first,
                           let message = firstChoice["message"] as? [String: Any],
                           let contentString = message["content"] as? String else {
                         completion(.failure(NSError(domain: "AzureOpenAIService", code: 14, userInfo: [NSLocalizedDescriptionKey: "Failed to parse primary response structure"])))
                         return
                     }

                     // Now parse the JSON *within* the content string
                     guard let contentData = contentString.data(using: .utf8) else {
                         completion(.failure(NSError(domain: "AzureOpenAIService", code: 15, userInfo: [NSLocalizedDescriptionKey: "Failed to convert content string to data"])))
                         return
                     }

                     guard let contentJson = try JSONSerialization.jsonObject(with: contentData, options: []) as? [String: Any] else {
                         completion(.failure(NSError(domain: "AzureOpenAIService", code: 16, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON content string"])))
                         return
                     }

                    // Check the responseType
                    guard let responseType = contentJson["responseType"] as? String else {
                         completion(.failure(NSError(domain: "AzureOpenAIService", code: 17, userInfo: [NSLocalizedDescriptionKey: "Missing 'responseType' in AI JSON response"])))
                        return
                    }

                    if responseType == "success" {
                        // Parse AISuccessAction
                         guard let coordsDict = contentJson["annotationCoordinates"] as? [String: Double],
                               let x = coordsDict["x"], let y = coordsDict["y"],
                               let width = coordsDict["width"], let height = coordsDict["height"],
                               let annotationText = contentJson["annotationText"] as? String,
                               let plan = contentJson["plan"] as? String else {
                              completion(.failure(NSError(domain: "AzureOpenAIService", code: 18, userInfo: [NSLocalizedDescriptionKey: "Failed to parse 'success' response fields"])))
                             return
                         }
                         let coordinates = CGRect(x: x, y: y, width: width, height: height)
                         let successAction = AISuccessAction(annotationCoordinates: coordinates, annotationText: annotationText, plan: plan)
                         completion(.success(.success(successAction)))

                    } else if responseType == "retry" {
                        // Parse AIRetryAction
                         guard let suggestedApp = contentJson["suggestedApp"] as? String else {
                              completion(.failure(NSError(domain: "AzureOpenAIService", code: 19, userInfo: [NSLocalizedDescriptionKey: "Failed to parse 'retry' response fields"])))
                             return
                         }
                         let retryAction = AIRetryAction(suggestedApp: suggestedApp)
                         completion(.success(.retry(retryAction)))
                    } else {
                         completion(.failure(NSError(domain: "AzureOpenAIService", code: 20, userInfo: [NSLocalizedDescriptionKey: "Unknown 'responseType' in AI JSON response: \(responseType)"])))
                    }

                } catch {
                     // Catch JSON parsing errors (both primary and content string)
                    completion(.failure(NSError(domain: "AzureOpenAIService", code: 21, userInfo: [NSLocalizedDescriptionKey: "JSON Parsing Error: \(error.localizedDescription)"])))
                }
            }
            task.resume()
            
        } catch {
            // Catch request body serialization errors
            completion(.failure(error))
        }
    }
} 
