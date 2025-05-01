import SwiftUI

struct ChatInterface: View {
    @ObservedObject var overlayController: OverlayController
    @State private var inputText: String = ""
    @State private var showAttachmentOptions: Bool = false
    @State private var lastScreenshot: NSImage? = nil // Keep for potential future use
    
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
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 14))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                }
                .layoutPriority(1) // Allow text field to expand
            }
            
            // --- Bottom Row: Attach Button ---
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
                
                Spacer() // Pushes attach button to the left
            }
        }
        .padding(.horizontal, 16) // Inner horizontal padding
        .padding(.vertical, 10)   // Inner vertical padding
        .padding(.top, 10) // Add padding specifically at the top for window controls
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        )
        .frame(width: 450, height: 95) // Adjusted height slightly for top padding
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
                    self.inputText = "" // Optionally clear text
                     // TODO: Add visual indicator for attached screenshot
                }
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

// Helper for VisualEffectView
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}


#Preview {
    ChatInterface(overlayController: OverlayController())
        .frame(width: 450, height: 95) // Match frame in preview
} 