//
//  PreferencesView.swift
//  hopscotch
//
//  Created by Abhimanyu Yadav on 4/28/25.
//

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var overlayController: OverlayController
    
    // Track mode changes separately to avoid direct binding issues
    @State private var selectedMode: OverlayMode
    @State private var selectedTab = 0
    
    // Separate state for log display
    @State private var logs: [String] = []
    
    // Coordinate inputs for drawing mode
    @State private var targetX: String = "0"
    @State private var targetY: String = "0"
    @State private var targetWidth: String = "200"
    @State private var targetHeight: String = "100"
    @State private var targetBundleID: String = ""
    @State private var availableApps: [NSRunningApplication] = []
    @State private var selectedAppIndex: Int = 0
    
    // Add state for new controls
    @State private var activateApp: Bool = true
    @State private var bypassFocusCheck: Bool = true
    
    // Timer for checking mode changes
    @State private var modeUpdateTimer: Timer? = nil
    
    // Add state for user input
    @State private var userInputText: String = ""
    
    // Add state for screenshot
    @State private var screenshotImage: NSImage? = nil
    @State private var isScreenshotLoading: Bool = false
    
    // AI Analysis
    @State private var aiAnalysisResult: String = ""
    @State private var isAnalyzing: Bool = false
    
    init(overlayController: OverlayController) {
        self.overlayController = overlayController
        self._selectedMode = State(initialValue: overlayController.overlayMode)
        self._logs = State(initialValue: overlayController.logs)
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            controlsView
                .tabItem {
                    Label("Controls", systemImage: "slider.horizontal.3")
                }
                .tag(0)
            
            logsView
                .tabItem {
                    Label("Logs", systemImage: "text.append")
                }
                .tag(1)
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            setupModeUpdateTimer()
            loadRunningApps()
        }
        .onDisappear {
            invalidateTimer()
        }
    }
    
    private func loadRunningApps() {
        availableApps = NSWorkspace.shared.runningApplications.filter { 
            $0.activationPolicy == .regular && $0.bundleIdentifier != nil
        }
        
        if let currentApp = availableApps.first {
            targetBundleID = currentApp.bundleIdentifier ?? ""
        }
    }
    
    private func setupModeUpdateTimer() {
        // Invalidate existing timer first to prevent multiple timers
        invalidateTimer()
        
        // Setup timer to periodically check for mode changes
        modeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.selectedMode = self.overlayController.overlayMode
            self.logs = self.overlayController.logs
        }
        
        // Make sure timer runs even when UI is being updated
        RunLoop.current.add(modeUpdateTimer!, forMode: .common)
    }
    
    private func invalidateTimer() {
        modeUpdateTimer?.invalidate()
        modeUpdateTimer = nil
    }
    
    private var controlsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Current Mode: \(selectedMode.displayName)")
                    .font(.headline)
                    .padding(.bottom, 10)
                
                Group {
                    Text("Active Overlay Controls")
                        .font(.headline)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("To cancel any active mode, press the Escape key.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            overlayController.cancelCurrentMode()
                            selectedMode = .none
                        }) {
                            Text("Cancel Active Mode")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedMode == .none)
                        .padding(.vertical, 8)
                    }
                    
                    Divider()
                }
                
                Group {
                    Text("Available Actions")
                        .font(.headline)
                    
                    Divider()
                    
                    // Target app selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Application:")
                            .font(.subheadline)
                        
                        if availableApps.isEmpty {
                            Text("No applications available")
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Select App", selection: $selectedAppIndex) {
                                ForEach(0..<availableApps.count, id: \.self) { index in
                                    Text(availableApps[index].localizedName ?? "Unknown App")
                                        .tag(index)
                                }
                            }
                            .onChange(of: selectedAppIndex) { newValue in
                                if availableApps.indices.contains(newValue) {
                                    targetBundleID = availableApps[newValue].bundleIdentifier ?? ""
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                        
                        Text("Bundle ID: \(targetBundleID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 12)
                    
                    // Coordinates input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Coordinates:")
                            .font(.subheadline)
                        
                        HStack {
                            VStack {
                                Text("X:")
                                TextField("X", text: $targetX)
                                    .frame(width: 60)
                            }
                            
                            VStack {
                                Text("Y:")
                                TextField("Y", text: $targetY)
                                    .frame(width: 60)
                            }
                            
                            VStack {
                                Text("Width:")
                                TextField("Width", text: $targetWidth)
                                    .frame(width: 60)
                            }
                            
                            VStack {
                                Text("Height:")
                                TextField("Height", text: $targetHeight)
                                    .frame(width: 60)
                            }
                        }
                    }
                    .padding(.bottom, 12)
                    
                    // Add Toggles for activateApp and bypassFocusCheck
                    VStack(alignment: .leading) {
                         Toggle("Activate Target App First", isOn: $activateApp)
                            .help("If enabled, the target application will be brought to the front before drawing. If disabled, the annotation will be drawn relative to the target window only if it is already frontmost (unless 'Bypass Focus Check' is also enabled).")
                        
                         Toggle("Bypass Focus Check", isOn: $bypassFocusCheck)
                            .help("If enabled, the annotation will be drawn even if the target application is not the frontmost window. Requires 'Activate Target App First' to be disabled to attempt window-relative drawing on a non-focused app.")
                    }
                    .padding(.bottom, 12)
                    
                    // Draw annotation button - visible and properly styled
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Draw annotations on the screen to highlight areas.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Button(action: {
                            drawAnnotation()
                        }) {
                            Text("Draw Annotation")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(targetBundleID.isEmpty)
                        .padding(.vertical, 8)
                    }
                    .padding(.bottom, 12)
                    
                    // Monitor region button - visible and properly styled
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select a region of the screen to monitor for changes.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Button(action: {
                            // Activate Observe Mode using the coordinates
                            activateObserveMode()
                        }) {
                            Text("Monitor Region")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        // .disabled(selectedMode == .regionSelect) // Let user define multiple regions if needed
                        .padding(.vertical, 8)
                    }
                    .padding(.bottom, 12)

                    // --- Screenshot Area ---
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Screenshot the selected app's main window:")
                            .font(.headline)
                        Button(action: {
                            takeScreenshot()
                        }) {
                            Text("Take Screenshot")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(targetBundleID.isEmpty || isScreenshotLoading)
                        .padding(.vertical, 8)
                        if isScreenshotLoading {
                            ProgressView("Capturing screenshot...")
                                .padding(.top, 4)
                        } else if let screenshot = screenshotImage {
                            Image(nsImage: screenshot)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 400, maxHeight: 240)
                                .border(Color.gray.opacity(0.3), width: 1)
                                .cornerRadius(4)
                                .padding(.top, 4)
                        } else {
                            Text("No screenshot taken yet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.bottom, 12)
                    Divider()
                    // --- End Screenshot Area ---

                    // User Text Input Area
                    VStack(alignment: .leading, spacing: 8) {
                        Text("User Input:")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        Text("Enter text to send along with the screenshot to Azure OpenAI for analysis.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)
                        
                        TextEditor(text: $userInputText)
                            .font(.body)
                            .frame(height: 120)
                            .border(Color.gray.opacity(0.3), width: 1)
                            .cornerRadius(4)
                        
                        // Button to analyze with AI
                        Button(action: {
                            analyzeWithAI()
                        }) {
                            Text("Analyze with Azure OpenAI")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .disabled(screenshotImage == nil || userInputText.isEmpty || isAnalyzing)
                        .padding(.vertical, 8)
                        
                        if isAnalyzing {
                            ProgressView("Analyzing...")
                                .padding(.top, 4)
                        } else if !aiAnalysisResult.isEmpty {
                            Text("AI Analysis Result:")
                                .font(.headline)
                                .padding(.top, 8)
                            
                            ScrollView {
                                Text(aiAnalysisResult)
                                    .font(.body)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .frame(height: 200)
                        }
                    }
                    .padding(.bottom, 12)

                    Spacer()
                }
            }
            .padding()
        }
    }
    
    private func drawAnnotation() {
        guard !targetBundleID.isEmpty else {
            return
        }
        
        // Safely convert string inputs to CGFloat
        guard let x = Double(targetX),
              let y = Double(targetY),
              let width = Double(targetWidth),
              let height = Double(targetHeight) else {
            // Handle invalid input
            return
        }
        
        // Create a command similar to what would come from CLI
        let commandDict: [String: Any] = [
            "command": "act",
            "params": [
                "x": x,
                "y": y,
                "width": width,
                "height": height,
                "targetBundleID": targetBundleID,
                "activateApp": activateApp,
                "bypassFocusCheck": bypassFocusCheck
            ]
        ]
        
        // Convert to JSON string
        if let jsonData = try? JSONSerialization.data(withJSONObject: commandDict),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            // Process the command
            DispatchQueue.main.async { [self] in
                overlayController.processCommand(jsonString)
                
                // Remove the redundant mode activation that was clearing the annotation
                // The handleActCommand already sets the mode correctly
                // DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
                //     overlayController.activateMode(.drawing)
                //     selectedMode = .drawing
                // }
            }
        }
    }
    
    private func activateObserveMode() {
        // Only need width and height for centered observation
        guard let width = Double(targetWidth),
              let height = Double(targetHeight) else {
            print("[PreferencesView] Error: Invalid width/height input for observe mode.")
            return
        }
        
        // Ensure a target app is selected
        guard !targetBundleID.isEmpty else {
            print("[PreferencesView] Error: No target application selected.")
            // Maybe show an alert
            return
        }
        
        print("[PreferencesView] Activating observe mode for target: \(targetBundleID) with size (\(width), \(height)). ActivateApp: \(activateApp), BypassFocus: \(bypassFocusCheck)")
        
        // Call the controller method
        DispatchQueue.main.async { [self] in
            overlayController.startObservingRegion(
                targetBundleID: targetBundleID, 
                width: width, 
                height: height,
                bypassFocusCheck: bypassFocusCheck, // Use state variable 
                activateTargetApp: activateApp // Use state variable
            )
        }
    }
    
    private func takeScreenshot() {
        guard !targetBundleID.isEmpty else { return }
        isScreenshotLoading = true
        screenshotImage = nil
        overlayController.takeScreenshotOfSelectedApp(bundleID: targetBundleID) { image in
            DispatchQueue.main.async {
                self.screenshotImage = image
                self.isScreenshotLoading = false
            }
        }
    }
    
    private func analyzeWithAI() {
        guard let screenshot = screenshotImage, !userInputText.isEmpty else { return }
        isAnalyzing = true
        aiAnalysisResult = ""
        
        // Send to Azure OpenAI
        AzureOpenAIService.shared.sendScreenshotAndText(
            screenshot: screenshot,
            text: userInputText
        ) { result in
            DispatchQueue.main.async {
                self.isAnalyzing = false
                
                switch result {
                case .success(let response):
                    self.aiAnalysisResult = response
                    self.overlayController.addLog(type: .info, message: "Successfully received AI analysis")
                case .failure(let error):
                    self.aiAnalysisResult = "Error: \(error.localizedDescription)"
                    self.overlayController.addLog(type: .error, message: "Failed to analyze with AI: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private var logsView: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Command Logs")
                    .font(.headline)
                
                Spacer()
                
                Button("Clear Logs") {
                    overlayController.clearLogs()
                    logs = []
                }
                .buttonStyle(.borderedProminent)
                .disabled(logs.isEmpty)
            }
            .padding(.bottom, 8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(logs, id: \.self) { log in
                        Text(log)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.textBackgroundColor))
            .cornerRadius(6)
        }
        .padding()
    }
}

// Simple extension to get display names for modes
extension OverlayMode {
    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .drawing:
            return "Drawing"
        case .regionSelect:
            return "Region Selection"
        }
    }
}

// Extensions to help with string to CGFloat conversion
extension CGFloat {
    init?(_ string: String) {
        if let number = Double(string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.init(number)
        } else {
            return nil
        }
    }
}

#Preview {
    PreferencesView(overlayController: OverlayController())
} 