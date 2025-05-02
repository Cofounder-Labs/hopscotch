import Foundation
import Cocoa

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

    // Note: Secure configuration methods (get/set) are kept specific to the
    // AzureOpenAIService implementation for now, as they might not be
    // universally applicable to all potential AIService implementations.
} 