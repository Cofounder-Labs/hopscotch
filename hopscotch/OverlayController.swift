//
//  OverlayController.swift
//  hopscotch
//
//  Created by Abhimanyu Yadav on 4/28/25.
//

import Foundation
import Cocoa

class OverlayController: ObservableObject {
    private let overlayManager = OverlayManager()
    private let clickMonitor = ClickMonitor()
    @Published var currentMode: AppMode = .observe
    
    init() {
        // Setup standard input reading
        setupStandardInputReader()
    }
    
    // Set the current mode
    func setMode(mode: AppMode) {
        if currentMode == mode {
            return // No change needed
        }
        
        currentMode = mode
        
        switch mode {
        case .observe:
            overlayManager.clearOverlays()
            clickMonitor.startMonitoring()
        case .act:
            clickMonitor.stopMonitoring()
            clickMonitor.clearMonitoredRegions()
        }
    }
    
    // Process a command from CLI
    func processCommand(_ command: String) {
        do {
            guard let data = command.data(using: .utf8) else {
                print("{\"error\":\"Invalid command format\"}")
                return
            }
            
            let jsonCommand = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            
            guard let jsonCommand = jsonCommand else {
                print("{\"error\":\"Invalid JSON command\"}")
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
                    print("{\"error\":\"Unknown command type: \(commandType)\"}")
                }
            } else {
                print("{\"error\":\"Missing command type\"}")
            }
        } catch {
            print("{\"error\":\"Failed to parse command: \(error.localizedDescription)\"}")
        }
    }
    
    // Handle Act command
    private func handleActCommand(_ command: [String: Any]) {
        // Ensure we're in Act mode
        setMode(mode: .act)
        
        // Extract parameters
        guard let params = command["params"] as? [String: Any],
              let x = params["x"] as? CGFloat,
              let y = params["y"] as? CGFloat,
              let width = params["width"] as? CGFloat,
              let height = params["height"] as? CGFloat,
              let targetBundleID = params["targetBundleID"] as? String else {
            print("{\"error\":\"Missing required parameters for act command\"}")
            return
        }
        
        // Draw the annotation
        DispatchQueue.main.async {
            self.overlayManager.drawAnnotation(
                x: x, y: y, width: width, height: height, 
                targetBundleID: targetBundleID
            ) { success in
                if !success {
                    print("{\"error\":\"Failed to draw annotation, target app not in focus\"}")
                }
            }
        }
    }
    
    // Handle Observe command
    private func handleObserveCommand(_ command: [String: Any]) {
        // Ensure we're in Observe mode
        setMode(mode: .observe)
        
        // Extract parameters
        guard let params = command["params"] as? [String: Any],
              let x = params["x"] as? CGFloat,
              let y = params["y"] as? CGFloat,
              let width = params["width"] as? CGFloat,
              let height = params["height"] as? CGFloat else {
            print("{\"error\":\"Missing required parameters for observe command\"}")
            return
        }
        
        // Generate a unique ID for this region
        let regionId = UUID().uuidString
        
        // Add the region to monitor
        let rect = NSRect(x: x, y: y, width: width, height: height)
        DispatchQueue.main.async {
            self.clickMonitor.addMonitoredRegion(id: regionId, rect: rect)
            print("{\"status\":\"observing\", \"rectId\":\"\(regionId)\"}")
        }
    }
    
    // Handle Mode command
    private func handleModeCommand(_ command: [String: Any]) {
        guard let params = command["params"] as? [String: Any],
              let modeString = params["mode"] as? String else {
            print("{\"error\":\"Missing mode parameter\"}")
            return
        }
        
        switch modeString.lowercased() {
        case "act":
            DispatchQueue.main.async {
                self.setMode(mode: .act)
                print("{\"status\":\"mode_changed\", \"mode\":\"act\"}")
            }
        case "observe":
            DispatchQueue.main.async {
                self.setMode(mode: .observe)
                print("{\"status\":\"mode_changed\", \"mode\":\"observe\"}")
            }
        default:
            print("{\"error\":\"Invalid mode value: \(modeString)\"}")
        }
    }
    
    // Setup reading from standard input
    private func setupStandardInputReader() {
        DispatchQueue.global(qos: .userInitiated).async {
            while let line = readLine() {
                self.processCommand(line)
            }
        }
    }
} 