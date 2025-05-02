import Foundation
import Cocoa
import CoreGraphics // Add for CGRect

/// Structure for a successful action response from the AI.
struct AISuccessAction {
    let annotationCoordinates: CGRect // Coordinates for drawing UI elements
    let annotationText: String       // Text for the annotation (e.g., "Click here")
    let plan: String                 // Concise step-by-step plan
}

/// Structure for when the AI suggests retrying with a different application context.
struct AIRetryAction {
    let suggestedApp: String         // The name of the app the AI thinks the query is about
}

/// Enum to represent the possible structured responses from the AI for an action query.
enum AIActionResponse {
    case success(AISuccessAction)
    case retry(AIRetryAction)
    // Errors will be handled by the Result type's failure case
}

/// Defines the interface for an AI service capable of processing images and text.
protocol AIServiceProtocol {
    /// Indicates if the service is configured with necessary credentials and endpoints.
    var isConfigured: Bool { get }

    /// Sends a screenshot image and accompanying text to the AI service for processing.
    /// - Parameters:
    ///   - screenshot: The screenshot image to be analyzed.
    ///   - text: The user's text input or question related to the image.
    ///   - completion: A closure called with the result, containing either the AI's response string or an error.
    func sendScreenshotAndText(
        screenshot: NSImage,
        text: String,
        completion: @escaping (Result<String, Error>) -> Void
    )

    /// Sends a screenshot and text for processing, receiving the response as a stream of text chunks.
    /// - Parameters:
    ///   - screenshot: The screenshot image.
    ///   - text: The user's text input.
    ///   - onContent: A closure called repeatedly with chunks of the AI's response text.
    ///   - onComplete: A closure called once the streaming response is fully received, indicating success or failure.
    func sendScreenshotAndTextStreamed(
        screenshot: NSImage,
        text: String,
        onContent: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    )

    /// Sends comprehensive context (app details, query, image, history, UI info) to the AI
    /// to get a specific action recommendation or a suggestion to retry with a different app.
    /// - Parameters:
    ///   - appName: The name of the currently active application.
    ///   - userQuery: The user's specific question or command.
    ///   - screenshot: The screenshot image of the current application state.
    ///   - chatHistory: An array of recent conversation turns (e.g., ["user: query1", "assistant: response1"]).
    ///   - boundingBox: The bounding box of the primary UI element or region of interest.
    ///   - openApps: A list of names of currently open applications.
    ///   - completion: A closure called with the result, containing either an `AIActionResponse` or an error.
    func getAIAction(
        appName: String,
        userQuery: String,
        screenshot: NSImage,
        chatHistory: [String],
        boundingBox: CGRect,
        openApps: [String],
        completion: @escaping (Result<AIActionResponse, Error>) -> Void
    )

    // Note: Secure configuration methods (get/set) are kept specific to the
    // AzureOpenAIService implementation for now, as they might not be
    // universally applicable to all potential AIService implementations.
} 