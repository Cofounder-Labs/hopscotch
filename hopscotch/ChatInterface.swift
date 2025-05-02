import SwiftUI

struct ChatInterface: View {
    @ObservedObject var overlayController: OverlayController
    @State private var inputText: String = ""
    @State private var showAttachmentOptions: Bool = false
    @State private var lastScreenshot: NSImage? = nil // Keep for potential future use
    
    // Access the environment object and openWindow action
    @EnvironmentObject var testResultData: TestResultData
    @Environment(\.openWindow) var openWindow
    
    // State for loading indicator during LLM test
    @State private var isTestingLlm = false
    
    // Simplified initializer
    init(overlayController: OverlayController) {
        self._overlayController = ObservedObject(wrappedValue: overlayController)
    }
    
    var body: some View {
        VStack(spacing: 8) { // Main container for text area and button row
            // --- Top Row: Text Input ---
            HStack(alignment: .center, spacing: 10) {
                // Text field area
                ZStack(alignment: .leading) {
                    if inputText.isEmpty {
                        Text("What can i help you do?")
                            .foregroundColor(Color.primary.opacity(0.4))
                            .padding(.leading, 8)
                    }
                    
                    TextField("", text: $inputText, onCommit: sendMessage) // Trigger send on Enter
                        .textFieldStyle(PlainTextFieldStyle()) // Ensures transparent background
                        .font(.system(size: 14))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                }
                .layoutPriority(1) // Allow text field to expand
            }
            
            // --- Bottom Row: Attach & Test Buttons ---
            HStack(spacing: 16) { 
                // Plus button & "Attach" Text
                Button(action: {
                    self.showAttachmentOptions.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                        Text("Attach")
                            .font(.system(size: 14))
                    }
                    .foregroundColor(.primary.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
                .popover(isPresented: $showAttachmentOptions) {
                    AttachmentOptionsView(onScreenshot: takeScreenshot)
                }
                
                // LLM Test Button
                Button(action: testLlmConnection) {
                    HStack(spacing: 4) {
                        Image(systemName: "network.badge.shield.half.filled") // Example icon
                            .font(.system(size: 16, weight: .medium))
                        Text("Test LLM")
                            .font(.system(size: 14))
                    }
                     .foregroundColor(isTestingLlm ? .secondary : .primary.opacity(0.7)) // Dim if loading
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isTestingLlm)
                
                Spacer() // Pushes buttons to the left
            }
            .overlay( // Show progress indicator over the test button when loading
                 Group {
                     if isTestingLlm {
                         ProgressView()
                             .scaleEffect(0.6) // Make spinner smaller
                             .frame(width: 16, height: 16)
                             .offset(x: 50) // Adjust position relative to the button area
                     }
                 }
             )
        }
        .padding(.horizontal, 16) // Inner horizontal padding
        .padding(.vertical, 10)   // Inner vertical padding
        .padding(.top, 10) // Add padding specifically at the top for window controls
        // No explicit background modifier needed here; inherits window background
        .frame(width: 450, height: 95) // Keep the frame size
    }
    
    private func sendMessage() {
        guard !inputText.isEmpty || lastScreenshot != nil else { return }
        
        print("Sending message: \(inputText)")
        if let screenshot = lastScreenshot {
            print("With screenshot.")
            AzureOpenAIService.shared.sendScreenshotAndText(screenshot: screenshot, text: inputText) { result in
                // Handle API result (e.g., show status, clear screenshot)
                print("API Result: \(result)")
                DispatchQueue.main.async {
                    self.lastScreenshot = nil // Clear screenshot after sending
                }
            }
        } else {
            // Handle text-only message if needed (though focus is on screenshot analysis)
            print("Sending text only: \(inputText)")
            // Maybe call a different API endpoint or show a message
        }
        
        // Clear input text after sending/committing
        DispatchQueue.main.async {
             self.inputText = ""
        }
    }
    
    private func takeScreenshot() {
        overlayController.takeScreenshotOfActiveApp { image in
            DispatchQueue.main.async {
                self.lastScreenshot = image
                self.showAttachmentOptions = false
                if image != nil {
                    // Update placeholder or give visual cue that screenshot is attached
                    self.inputText = "Screenshot attached" // Example placeholder
                     // TODO: Add better visual indicator for attached screenshot
                }
            }
        }
    }
    
    private func testLlmConnection() {
        isTestingLlm = true
        let prompt = "What animal is this?"
        guard let image = NSImage(named: "TestConnection") else {
             print("Error: Could not load TestConnection image asset.")
             // Update data object and open window with error
             testResultData.image = nil
             testResultData.text = "Error: Could not load image asset 'TestConnection'."
             openWindow(id: "llmTestResultWindow")
             isTestingLlm = false
             return
        }

        // Update data object for loading state and open the window
        testResultData.image = image
        testResultData.text = "" // Empty string indicates loading in TestResultView
        openWindow(id: "llmTestResultWindow")

        AzureOpenAIService.shared.sendScreenshotAndText(screenshot: image, text: prompt) { result in
             DispatchQueue.main.async {
                 isTestingLlm = false
                 switch result {
                 case .success(let response):
                     print("LLM Test Success: \(response)")
                     // Update the data object with the successful response
                     testResultData.text = response
                 case .failure(let error):
                     print("LLM Test Error: \(error.localizedDescription)")
                     let errorMessage = "LLM Test Failed: \(error.localizedDescription)"
                     // Update the data object with the error message
                     testResultData.text = errorMessage
                 }
                 // The window is already open, and TestResultView will react to the change in testResultData
             }
        }
    }
}

// MARK: - Supporting Views

struct AttachmentOptionsView: View {
    var onScreenshot: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: onScreenshot) {
                HStack {
                    Image(systemName: "camera")
                    Text("Take Screenshot")
                }
                .frame(width: 150, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.vertical, 5)
        }
        .padding()
    }
}

#Preview {
    // Provide environment object for preview
    ChatInterface(overlayController: OverlayController())
        .environmentObject(TestResultData()) // Add dummy data object
        .frame(width: 450, height: 95) // Match frame in preview
} 