//
//  OverlayController.swift
//  hopscotch
//
//  Created by Abhimanyu Yadav on 4/28/25.
//

import Foundation
import Cocoa

// Define the OverlayMode enum for the PreferencesView
enum OverlayMode {
    case none
    case drawing
    case regionSelect
}

class OverlayController: ObservableObject {
    private let overlayManager = OverlayManager()
    private let clickMonitor = ClickMonitor()
    @Published var currentMode: AppMode = .observe
    // Add OverlayMode property for use in PreferencesView
    @Published var overlayMode: OverlayMode = .none
    @Published var lastResponse: String = ""
    @Published var commandLogs: [CommandLog] = []
    // Add logs property for PreferencesView
    @Published var logs: [String] = []
    private var stdinReader: Thread?
    
    init() {
        // Setup standard input reading only if this is appropriate (e.g., CLI context)
        setupStandardInputReader()
    }
    
    deinit {
        // Stop the stdin reader thread if it's running
        cleanupForTermination()
    }
    
    // Clean up resources for termination or deallocation
    func cleanupForTermination() {
        // Stop stdin reader
        stdinReader?.cancel()
        stdinReader = nil
        
        // Clear overlay windows
        overlayManager.clearOverlays()
        
        // Stop click monitoring
        if currentMode == .observe {
            clickMonitor.stopMonitoring()
        }
    }
    
    // Set the current mode
    func setMode(mode: AppMode) {
        // Ensure we're on the main thread for UI updates
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.setMode(mode: mode)
            }
            return
        }
        
        if currentMode == mode {
            return // No change needed
        }
        
        currentMode = mode
        
        switch mode {
        case .observe:
            overlayManager.clearOverlays()
            clickMonitor.startMonitoring()
            addLog(type: .info, message: "Switched to Observe mode")
        case .act:
            clickMonitor.stopMonitoring()
            clickMonitor.clearMonitoredRegions()
            addLog(type: .info, message: "Switched to Act mode")
        }
    }
    
    // Process a command from CLI or UI
    func processCommand(_ command: String) {
        addLog(type: .command, message: "Processing command: \(command)")
        
        do {
            guard let data = command.data(using: .utf8) else {
                handleResponse(response: "{\"error\":\"Invalid command format\"}")
                return
            }
            
            let jsonCommand = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            
            guard let jsonCommand = jsonCommand else {
                handleResponse(response: "{\"error\":\"Invalid JSON command\"}")
                return
            }
            
            // Check command type
            if let commandType = jsonCommand["command"] as? String {
                switch commandType {
                case "act":
                    handleActCommand(jsonCommand)
                case "observe":
                    handleObserveCommand(jsonCommand)
                case "mode":
                    handleModeCommand(jsonCommand)
                default:
                    handleResponse(response: "{\"error\":\"Unknown command type: \(commandType)\"}")
                }
            } else {
                handleResponse(response: "{\"error\":\"Missing command type\"}")
            }
        } catch {
            handleResponse(response: "{\"error\":\"Failed to parse command: \(error.localizedDescription)\"}")
        }
    }
    
    // Handle Act command
    private func handleActCommand(_ command: [String: Any]) {
        // Extract parameters
        guard let params = command["params"] as? [String: Any],
              let x = params["x"] as? CGFloat,
              let y = params["y"] as? CGFloat,
              let width = params["width"] as? CGFloat,
              let height = params["height"] as? CGFloat,
              let targetBundleID = params["targetBundleID"] as? String else {
            handleResponse(response: "{\"error\":\"Missing required parameters for act command\"}")
            return
        }
        
        // Extract optional parameters
        let activateApp = params["activateApp"] as? Bool ?? false
        let bypassFocusCheck = params["bypassFocusCheck"] as? Bool ?? false
        
        addLog(type: .info, message: "Drawing annotation at (\(x), \(y), \(width), \(height)) for app: \(targetBundleID) [activate: \(activateApp), bypass: \(bypassFocusCheck)]")
        
        // Ensure we're in Act mode
        setMode(mode: .act)
        
        // Draw the annotation with the new options
        DispatchQueue.main.async {
            self.overlayManager.drawAnnotation(
                x: x, y: y, width: width, height: height, 
                targetBundleID: targetBundleID,
                activateTargetApp: activateApp,
                bypassFocusCheck: bypassFocusCheck
            ) { success in
                if !success {
                    self.handleResponse(response: "{\"error\":\"Failed to draw annotation, target app not in focus\"}")
                    self.addLog(type: .error, message: "Failed to draw annotation - target app not in focus")
                } else {
                    self.handleResponse(response: "{\"status\":\"drawn\", \"ts\":\(Int(Date().timeIntervalSince1970 * 1000))}")
                }
            }
        }
    }
    
    // Handle Observe command
    private func handleObserveCommand(_ command: [String: Any]) {
        // Extract parameters
        guard let params = command["params"] as? [String: Any],
              let x = params["x"] as? CGFloat,
              let y = params["y"] as? CGFloat,
              let width = params["width"] as? CGFloat,
              let height = params["height"] as? CGFloat else {
            handleResponse(response: "{\"error\":\"Missing required parameters for observe command\"}")
            return
        }
        
        // Ensure we're in Observe mode
        // Note: setMode clears previous overlays, including potentially other observed regions.
        // If multiple simultaneous observed regions are needed, this clearing needs refinement.
        setMode(mode: .observe) 
        
        // Generate a unique ID for this region
        let regionId = UUID().uuidString
        let rect = NSRect(x: x, y: y, width: width, height: height)
        
        addLog(type: .info, message: "Monitoring region at (\(x), \(y), \(width), \(height)) with ID: \(regionId)")
        
        // Add the region to monitor internally
        DispatchQueue.main.async {
            self.clickMonitor.addMonitoredRegion(id: regionId, rect: rect)
            self.handleResponse(response: "{\"status\":\"observing\", \"rectId\":\"\(regionId)\"}")

            // Now, also draw the persistent bounding box
            print("[OverlayController] Drawing persistent box for observe region ID: \(regionId)")
            // Find the screen for the rect
            if let targetScreen = findScreen(for: rect) {
                print("[OverlayController] Found screen \(targetScreen.localizedName) for observe rect \(rect)")
                self.overlayManager.justDrawRectangle(
                    screen: targetScreen, 
                    x: x, y: y, width: width, height: height, 
                    id: regionId, 
                    persistent: true, 
                    strokeColor: .systemBlue, // Use blue for observed regions
                    fillColor: .systemBlue.withAlphaComponent(0.15) // Lighter blue fill
                )
            } else {
                // Should not happen due to findScreen fallbacks, but log if it does
                print("[OverlayController] Error: Could not find screen for observe rect \(rect). Bounding box not drawn.")
                self.addLog(type: .error, message: "Failed to find screen for observed region \(regionId). Bounding box not drawn.")
            }
        }
    }
    
    // Handle Mode command
    private func handleModeCommand(_ command: [String: Any]) {
        guard let params = command["params"] as? [String: Any],
              let modeString = params["mode"] as? String else {
            handleResponse(response: "{\"error\":\"Missing mode parameter\"}")
            return
        }
        
        switch modeString.lowercased() {
        case "act":
            DispatchQueue.main.async {
                self.setMode(mode: .act)
                self.handleResponse(response: "{\"status\":\"mode_changed\", \"mode\":\"act\"}")
            }
        case "observe":
            DispatchQueue.main.async {
                self.setMode(mode: .observe)
                self.handleResponse(response: "{\"status\":\"mode_changed\", \"mode\":\"observe\"}")
            }
        default:
            handleResponse(response: "{\"error\":\"Invalid mode value: \(modeString)\"}")
        }
    }
    
    // Handle command response
    private func handleResponse(response: String) {
        DispatchQueue.main.async {
            self.lastResponse = response
            print(response) // Output to stdout for CLI capture
            self.addLog(type: .response, message: response)
        }
    }
    
    // Add log entry
    private func addLog(type: LogType, message: String) {
        let log = CommandLog(timestamp: Date(), type: type, message: message)
        DispatchQueue.main.async {
            self.commandLogs.append(log)
            // Keep only the last 100 logs
            if self.commandLogs.count > 100 {
                self.commandLogs.removeFirst(self.commandLogs.count - 100)
            }
        }
    }
    
    // Setup reading from standard input
    private func setupStandardInputReader() {
        // Check if we're running in a context where stdin is available
        // For GUI apps, this may not be the case
        let stdinHandle = FileHandle.standardInput
        
        // Create a thread for reading from stdin to avoid blocking the main thread
        stdinReader = Thread {
            // Set up a run loop source for the stdin file handle
            let runLoop = RunLoop.current
            var shouldKeepRunning = true
            
            while shouldKeepRunning && !Thread.current.isCancelled {
                autoreleasepool {
                    // Try to read a line from stdin
                    if let line = readLine(strippingNewline: true) {
                        DispatchQueue.main.async {
                            self.processCommand(line)
                        }
                    } else {
                        // If readLine returns nil, stdin has been closed
                        shouldKeepRunning = false
                    }
                }
                
                // Give the run loop a chance to process other sources
                runLoop.run(until: Date(timeIntervalSinceNow: 0.1))
            }
        }
        
        stdinReader?.name = "StdinReaderThread"
        stdinReader?.start()
    }
    
    // Add methods needed by PreferencesView
    func activateMode(_ mode: OverlayMode) {
        overlayMode = mode
        // Map overlay mode to app mode if needed
        switch mode {
        case .drawing, .regionSelect:
            setMode(mode: .act)
        case .none:
            // Keep current app mode
            break
        }
    }
    
    func cancelCurrentMode() {
        overlayMode = .none
    }
    
    func clearLogs() {
        logs.removeAll()
        commandLogs.removeAll()
    }
    
    // Starts observing a region relative to a target application window
    func startObservingRegion(targetBundleID: String, width: CGFloat, height: CGFloat, 
                              bypassFocusCheck: Bool, activateTargetApp: Bool) {
        
        // Ensure we're in Observe mode before starting
        // This also clears any previous overlays, including old observed regions.
        setMode(mode: .observe)

        overlayManager.observeAnnotation(
            targetBundleID: targetBundleID, 
            width: width, height: height, 
            bypassFocusCheck: bypassFocusCheck, 
            activateTargetApp: activateTargetApp
        ) { [weak self] success, regionId, observedRect, onScreen in
            guard let self = self else { return }
            
            DispatchQueue.main.async { // Ensure UI/monitoring updates are on main thread
                if success, let id = regionId, let rect = observedRect, let screen = onScreen {
                    print("[OverlayController] Observe annotation succeeded. ID: \(id), Rect (global): \(rect), Screen: \(screen.localizedName)")
                    // Register the exact rectangle that was drawn with ClickMonitor
                    self.clickMonitor.addMonitoredRegion(id: id, rect: rect)
                    self.addLog(type: .info, message: "Started observing region ID \(id) at \(rect) on screen \(screen.localizedName).")
                    // Send success response
                    self.handleResponse(response: "{\"status\":\"observing\", \"rectId\":\"\(id)\"}")
                } else {
                    print("[OverlayController] Observe annotation failed.")
                    self.addLog(type: .error, message: "Failed to start observing region for target \(targetBundleID).")
                    // Send error response
                    self.handleResponse(response: "{\"error\":\"Failed to draw/observe annotation for target \(targetBundleID)\"}")
                }
            }
        }
    }
}

// Log types
enum LogType {
    case command
    case response
    case info
    case error
}

// Command log structure
struct CommandLog: Identifiable {
    let id = UUID()
    let timestamp: Date
    let type: LogType
    let message: String
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
} 