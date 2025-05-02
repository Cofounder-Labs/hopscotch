import SwiftUI

struct TestResultView: View {
    let image: NSImage?
    let prompt: String
    let resultText: String
    @State private var isLoading: Bool

    init(image: NSImage?, prompt: String, resultText: String) {
        self.image = image
        self.prompt = prompt
        self.resultText = resultText
        // Determine loading state based on whether resultText is initially empty
        self._isLoading = State(initialValue: resultText.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Image Section
            if let nsImage = image {
                HStack {
                    Spacer()
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 300, maxHeight: 300)
                        .cornerRadius(8)
                        .padding(.bottom)
                    Spacer()
                }
            } else {
                Text("Image not loaded")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Divider()

            // Chat Section
            VStack(alignment: .leading, spacing: 10) {
                // User Prompt
                HStack(alignment: .top) {
                    Text("You:")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Text(prompt)
                        .textSelection(.enabled)
                }

                // Assistant Response
                HStack(alignment: .top) {
                    Text("Assistant:")
                        .font(.headline)
                        .foregroundColor(.purple)
                    
                    // Conditional Content: Loading indicator or Result
                    if isLoading {
                         HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8) // Make spinner slightly smaller
                            Text("Waiting for response...")
                                .foregroundColor(.secondary)
                        }
                    } else if resultText.isEmpty {
                         Text("No response received.")
                             .foregroundColor(.orange)
                    } else {
                        Text(resultText)
                            .textSelection(.enabled)
                    }
                }
                 .frame(minHeight: 50, alignment: .top) // Ensure space for response/indicator
            }
            Spacer() // Pushes content to the top
        }
        .padding()
        .frame(minWidth: 400, idealWidth: 450, minHeight: 450, idealHeight: 550) // Adjust frame size
         .onChange(of: resultText) { newText in
             // Update isLoading state when resultText changes from empty to non-empty
             if isLoading && !newText.isEmpty {
                 isLoading = false
             }
         }
    }
}

// Previews updated to reflect changes
#Preview("Initial Loading") {
     TestResultView(image: NSImage(named: "TestConnection"), prompt: "What animal is this?", resultText: "")
}

#Preview("Response Received") {
    TestResultView(image: NSImage(named: "TestConnection"), prompt: "What animal is this?", resultText: "This appears to be a cat, specifically a domestic shorthair kitten.")
}

#Preview("Image Load Failed") {
    TestResultView(image: nil, prompt: "What animal is this?", resultText: "Error: Could not load image asset 'TestConnection'.")
}

#Preview("No Response") {
     TestResultView(image: NSImage(named: "TestConnection"), prompt: "What animal is this?", resultText: "")
     // Simulate loading completion with empty text (error state)
     .onAppear { /* TestResultView's init handles empty resultText as loading, need different state for true 'no response' */ }
} 