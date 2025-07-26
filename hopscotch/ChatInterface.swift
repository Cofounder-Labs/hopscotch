import SwiftUI
import AppKit
// Import the main app module if TestResultData is defined there
// import hopscotchApp // Adjust if necessary

struct ChatInterface: View {
    @ObservedObject var overlayController: OverlayController
    @State private var inputText: String = ""
    @State private var lastScreenshot: NSImage? = nil // Keep for potential future use
    
    // State for running applications
    @State private var availableApps: [NSRunningApplication] = []
    @State private var selectedAppIndex: Int = 0
    @State private var selectedBundleID: String? = nil // Store the selected app's bundle ID
    
    // Access the environment object and openWindow action
    @EnvironmentObject var testResultData: TestResultData
    @Environment(\.openWindow) var openWindow
    
    // State for loading indicator during LLM test
    @State private var isTestingLlm = false
    @State private var isTestingAnnotation = false // State for annotation test loading
    @State private var isSendingMessage = false // State for sending message with screenshot
    
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
                    
                    TextField("", text: $inputText, onCommit: sendWithNewScreenshot) // Changed to call sendWithNewScreenshot
                        .textFieldStyle(PlainTextFieldStyle()) // Ensures transparent background
                        .font(.system(size: 14))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                }
                .layoutPriority(1) // Allow text field to expand
            }
            
            // --- Bottom Row: Attach & Test Buttons ---
            HStack(spacing: 16) { 
                // --- Replace Attach Button with App Picker ---
                if availableApps.isEmpty {
                     Text("Loading apps...")
                         .foregroundColor(.secondary)
                         .font(.system(size: 14))
                         .frame(minWidth: 150) // Maintain some width
                 } else {
                     Picker("Select App", selection: $selectedAppIndex) {
                         ForEach(0..<availableApps.count, id: \.self) { index in
                             HStack {
                                 if let originalIcon = availableApps[index].icon {
                                     // Resize the NSImage before creating the SwiftUI Image
                                     let resizedIcon = resizeNSImage(originalIcon, to: CGSize(width: 20, height: 20))
                                     Image(nsImage: resizedIcon)
                                         // No frame or aspect ratio needed here as the source image is already sized
                                         .padding(.trailing, 4)
                                 }
                                 Text(availableApps[index].localizedName ?? "Unknown App")
                             }
                             .tag(index)
                         }
                     }
                     .labelsHidden()
                     .frame(minWidth: 150, maxWidth: 200) // Adjust width as needed
                     .onChange(of: selectedAppIndex) { newValue in
                         if availableApps.indices.contains(newValue) {
                             let selectedApp = availableApps[newValue]
                             selectedBundleID = selectedApp.bundleIdentifier
                             // Don't automatically take screenshot here anymore
                             // We will take it when the user performs an action like "Test Annotation"
                         } else {
                             selectedBundleID = nil
                             lastScreenshot = nil // Clear screenshot if selection is invalid
                         }
                     }
                 }
                // --- End App Picker ---
                
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
                
                // LLM Annotation Test Button
                Button(action: testLlmAnnotation) {
                    HStack(spacing: 4) {
                        Image(systemName: "paintbrush.pointed.fill") // Example icon
                            .font(.system(size: 16, weight: .medium))
                        Text("Test Anno") // Shortened text
                            .font(.system(size: 14))
                    }
                    .foregroundColor(isTestingAnnotation ? .secondary : .primary.opacity(0.7)) // Dim if loading
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isTestingAnnotation)
                
                // Added Arrow Button (sends text + new screenshot)
                Button(action: sendWithNewScreenshot) { // Changed action
                     Image(systemName: "arrow.up.circle.fill")
                         .font(.system(size: 18, weight: .medium)) // Slightly larger
                         .foregroundColor(isSendingMessage ? .secondary : .primary.opacity(0.8)) // Dim if loading
                }
                .buttonStyle(PlainButtonStyle())
                // Disable if sending, or if no app is selected, or if text is empty (optional, decided to allow empty text)
                .disabled(isSendingMessage || selectedBundleID == nil)

                Spacer() // Pushes buttons to the left
            }
            .overlay( // Show progress indicator over the test button when loading
                 Group {
                     if isTestingLlm {
                         ProgressView()
                             .scaleEffect(0.6) // Make spinner smaller
                             .frame(width: 16, height: 16)
                             .offset(x: 50) // Adjust position relative to the button area
                     } else if isTestingAnnotation {
                         ProgressView()
                             .scaleEffect(0.6)
                             .frame(width: 16, height: 16)
                             .offset(x: 150) // Adjust position relative to the annotation test button area (needs tweaking)
                     } else if isSendingMessage { // Indicator for arrow button
                         ProgressView()
                             .scaleEffect(0.6)
                             .frame(width: 16, height: 16)
                             .offset(x: 210) // Approximate position near the arrow button (adjust as needed)
                     }
                 }
             )
        }
        .padding(.horizontal, 16) // Inner horizontal padding
        .padding(.vertical, 10)   // Inner vertical padding
        .padding(.top, 10) // Add padding specifically at the top for window controls
        // No explicit background modifier needed here; inherits window background
        .frame(width: 450, height: 95) // Keep the frame size
        // Load apps when the view appears
        .onAppear(perform: loadRunningApps)
    }
    
    // Renamed and modified to take screenshot of the currently selected app
    private func takeScreenshotForSelectedApp() {
        guard let bundleID = selectedBundleID else {
            print("No app selected for screenshot.")
            // Optionally clear the last screenshot if no app is selected
            // DispatchQueue.main.async { self.lastScreenshot = nil }
            return
        }
        
        print("Taking screenshot for app: \(bundleID)")
        // Use the overlayController's method that takes a bundle ID
        overlayController.takeScreenshotOfSelectedApp(bundleID: bundleID) { image in
            DispatchQueue.main.async {
                self.lastScreenshot = image
                if image != nil {
                    // Update placeholder or give visual cue that screenshot is attached
                    // Consider a less intrusive way than overwriting input text maybe?
                    // Or add a small icon next to the text field?
                    self.inputText = "Screenshot of \(availableApps[selectedAppIndex].localizedName ?? "selected app") attached." 
                    print("Screenshot attached for \(bundleID)")
                     // TODO: Add better visual indicator for attached screenshot
                } else {
                    print("Failed to get screenshot for \(bundleID ?? "<nil bundleID>")")
                    // Clear potentially existing text if screenshot fails
                    if inputText.contains("Screenshot of") && inputText.contains("attached.") {
                         self.inputText = ""
                    }
                }
            }
        }
    }
    
    // Function to load running applications
    private func loadRunningApps() {
        // Filter for regular apps with bundle IDs
        availableApps = NSWorkspace.shared.runningApplications.filter { 
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.localizedName != nil && !$0.localizedName!.isEmpty
        }
        
        // Sort alphabetically by localized name
        availableApps.sort { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

        // --- Start Default Selection Logic --- 
        // Set initial selection and bundle ID if apps are available
        if !availableApps.isEmpty {
            // Prioritize Xcode if running
            if let xcodeIndex = availableApps.firstIndex(where: { $0.bundleIdentifier == "com.apple.dt.Xcode" }) {
                selectedAppIndex = xcodeIndex
            // Then try Finder
            } else if let finderIndex = availableApps.firstIndex(where: { $0.bundleIdentifier == "com.apple.finder" }) {
                selectedAppIndex = finderIndex
            } else {
                selectedAppIndex = 0 // Default to the first app if Finder isn't running/found
            }
            
            if availableApps.indices.contains(selectedAppIndex) {
                selectedBundleID = availableApps[selectedAppIndex].bundleIdentifier
                // Optionally take an initial screenshot? Might be too eager.
                // takeScreenshotForSelectedApp()
            } else {
                // This case should ideally not happen if availableApps is not empty,
                // but set to nil just in case.
                selectedBundleID = nil
            }
        } else {
            selectedBundleID = nil // No apps available
        }
        // --- End Default Selection Logic ---
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

    private func testLlmAnnotation() {
        // Hardcode target to Xcode
        let targetBundleID = "com.apple.dt.Xcode"
        let targetAppName = "Xcode"
        let query = "Which button should I click to hide or show the navigator?"
 
        isTestingAnnotation = true
 
        // Access the wrapped value of the EnvironmentObject
        let dataObject = testResultData
        dataObject.prompt = query
        dataObject.image = nil // Clear previous image/text
        dataObject.text = ""  // Set text to empty to indicate loading
        openWindow(id: "llmTestResultWindow") // Open the window now
 
        overlayController.performLlmAnnotationTest(
            targetBundleID: targetBundleID, // Use hardcoded Xcode bundle ID
            appName: targetAppName, // Use hardcoded Xcode name
            initialQuery: query, // Pass the dynamic query
            testResultData: dataObject, // Pass the actual object
            openWindow: { _ in /* Window already opened */ } // Pass a dummy closure or handle differently if needed
        ) { 
            // Completion handler from OverlayController signals the end of the async operation
            isTestingAnnotation = false
        }
    }

    // New function to take screenshot and send
    private func sendWithNewScreenshot() {
        guard let bundleID = selectedBundleID, let appName = availableApps.first(where: { $0.bundleIdentifier == bundleID })?.localizedName else {
            print("No app selected or app name not found.")
            // Optionally show an alert to the user
            return
        }

        let currentText = inputText // Capture text before potential clearing
        isSendingMessage = true

        print("Taking screenshot for \(appName) (\(bundleID)) and sending with text: \"\(currentText)\"")

        overlayController.takeScreenshotOfSelectedApp(bundleID: bundleID) { image in
            guard let screenshot = image else {
                print("Failed to get screenshot for \(appName)")
                DispatchQueue.main.async {
                    isSendingMessage = false
                    // Optionally show an error message in the UI
                }
                return
            }

            // Screenshot successful, now call LLM using the action-oriented approach
            print("Screenshot captured for \(appName). Sending to LLM for action analysis...")

            let aiService: AIServiceProtocol = AzureOpenAIService.shared
            
            // Check if AI Service is configured
            guard aiService.isConfigured else {
                DispatchQueue.main.async {
                    isSendingMessage = false
                    testResultData.prompt = currentText
                    testResultData.image = screenshot
                    testResultData.text = "Error: AI Service not configured."
                    openWindow(id: "llmTestResultWindow")
                }
                return
            }

            DispatchQueue.main.async {
                 // Prepare data object and open window for loading state
                 testResultData.prompt = currentText
                 testResultData.image = screenshot
                 testResultData.text = "" // Indicate loading
                 openWindow(id: "llmTestResultWindow")

                 // Use the action-oriented LLM call like the working test flow
                 let chatHistory: [String] = []
                 let boundingBox: CGRect = .zero
                 let openApps = NSWorkspace.shared.runningApplications.compactMap { $0.localizedName }
                 
                 aiService.getAIAction(
                     appName: appName,
                     userQuery: currentText,
                     screenshot: screenshot,
                     chatHistory: chatHistory,
                     boundingBox: boundingBox,
                     openApps: openApps
                 ) { result in
                     DispatchQueue.main.async {
                         isSendingMessage = false // Call finished
                         switch result {
                         case .success(let actionResponse):
                             switch actionResponse {
                             case .success(let action):
                                 print("AI Action received: Plan: \(action.plan), Text: \(action.annotationText), Coords: \(action.annotationCoordinates)")
                                 // Update results window with the plan
                                 testResultData.text = "Plan:\n\(action.plan)"
                                 
                                 // Draw annotation on the target app window like the test flow
                                 overlayController.drawAnnotationFromCoordinates(
                                     relativeRect: action.annotationCoordinates,
                                     annotationText: action.annotationText,
                                     targetBundleID: bundleID
                                 ) { success in
                                     if success {
                                         print("Annotation drawn successfully on \(appName).")
                                     } else {
                                         print("Failed to draw annotation on \(appName).")
                                     }
                                 }
                                 
                             case .retry(let retryInfo):
                                 let msg = "AI suggested retrying with app: \(retryInfo.suggestedApp)"
                                 print(msg)
                                 testResultData.text = msg
                             }
                             
                         case .failure(let error):
                             let errorMessage = "AI Action failed: \(error.localizedDescription)"
                             print(errorMessage)
                             testResultData.text = "Error: \(errorMessage)"
                         }
                         // Clear input text after successful send or failure
                         self.inputText = ""
                     }
                 }
            }
        }
    }
}

// Helper function to resize NSImage
private func resizeNSImage(_ image: NSImage, to size: CGSize) -> NSImage {
    let newImage = NSImage(size: size)
    newImage.lockFocus()
    defer { newImage.unlockFocus() } // Ensure unlockFocus is called even if drawing fails
    image.draw(in: NSRect(origin: .zero, size: size),
               from: NSRect(origin: .zero, size: image.size),
               operation: .sourceOver, // Use .sourceOver for potentially transparent icons
               fraction: 1.0)
    return newImage
}

#Preview {
    // Provide environment object for preview
    // Ensure TestResultData is properly scoped or qualified for the preview
    ChatInterface(overlayController: OverlayController())
        // Use the class directly as defined in hopscotchApp.swift
        .environmentObject(TestResultData()) 
        .frame(width: 450, height: 95) // Match frame in preview
} 