import SwiftUI
import AppKit

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
                                 if let icon = availableApps[index].icon {
                                     Image(nsImage: icon)
                                         .resizable()
                                         .scaledToFit()
                                         .frame(width: 16, height: 16)
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
                             // Automatically take screenshot when app is selected
                             takeScreenshotForSelectedApp()
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
        // Load apps when the view appears
        .onAppear(perform: loadRunningApps)
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
                    print("Failed to get screenshot for \(bundleID)")
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

        // Set initial selection and bundle ID if apps are available
        if !availableApps.isEmpty {
             // Try to find Finder or the first app
             if let finderIndex = availableApps.firstIndex(where: { $0.bundleIdentifier == "com.apple.finder" }) {
                 selectedAppIndex = finderIndex
             } else {
                 selectedAppIndex = 0 // Default to the first app if Finder isn't running/found
             }
             
             if availableApps.indices.contains(selectedAppIndex) {
                 selectedBundleID = availableApps[selectedAppIndex].bundleIdentifier
                 // Optionally take an initial screenshot? Might be too eager.
                 // takeScreenshotForSelectedApp()
             }
         } else {
             selectedBundleID = nil // No apps available
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

#Preview {
    // Provide environment object for preview
    ChatInterface(overlayController: OverlayController())
        .environmentObject(TestResultData()) // Add dummy data object
        .frame(width: 450, height: 95) // Match frame in preview
} 