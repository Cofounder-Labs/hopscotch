//
//  OverlayManager.swift
//  hopscotch
//
//  Created by Abhimanyu Yadav on 4/28/25.
//

import Foundation
import Cocoa
import SwiftUI
import ApplicationServices
import ScreenCaptureKit
import AVFoundation

// Helper function to check Accessibility Permissions
func checkAccessibilityPermissions() -> Bool {
    print("[Accessibility Check] Checking permissions...")
    // Check if this process is trusted
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
    let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
    print("[Accessibility Check] Permissions granted: \(accessibilityEnabled)")
    return accessibilityEnabled
}

// Helper function to get the main window frame of an application
func getWindowFrame(for bundleID: String) -> CGRect? {
    print("[getWindowFrame] Attempting to get window frame for bundle ID: \(bundleID)")
    guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
        print("[getWindowFrame] Error: App with bundle ID \(bundleID) not running.")
        return nil
    }
    print("[getWindowFrame] Found running app: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")

    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    var mainWindow: CFTypeRef?

    // Get the main window
    print("[getWindowFrame] Trying to get kAXMainWindowAttribute...")
    let error = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow)
    if error != .success || mainWindow == nil {
        print("[getWindowFrame] Failed to get main window (Error: \(error.rawValue)). Trying kAXFocusedWindowAttribute...")
        // Try focused window as a fallback
        var focusedWindow: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        if focusedError == .success && focusedWindow != nil {
            print("[getWindowFrame] Successfully got focused window.")
            mainWindow = focusedWindow
        } else {
             print("[getWindowFrame] Error: Could not get main or focused window for \(bundleID). Main Error: \(error.rawValue), Focused Error: \(focusedError.rawValue)")
             return nil
        }
    } else {
        print("[getWindowFrame] Successfully got main window.")
    }

    guard let windowElement = mainWindow as! AXUIElement? else {
         print("[getWindowFrame] Error: Main window reference obtained is not an AXUIElement.")
         return nil
    }

    var positionValue: CFTypeRef?
    print("[getWindowFrame] Trying to get kAXPositionAttribute...")
    let positionError = AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionValue)
    guard positionError == .success, let positionRef = positionValue, CFGetTypeID(positionRef) == AXValueGetTypeID() else {
        print("[getWindowFrame] Error: Could not get window position for \(bundleID). Error: \(positionError.rawValue)")
        return nil
    }
    var windowPosition: CGPoint = .zero
    AXValueGetValue(positionRef as! AXValue, .cgPoint, &windowPosition)
    print("[getWindowFrame] Successfully got window position (global): \(windowPosition)")

    var sizeValue: CFTypeRef?
    print("[getWindowFrame] Trying to get kAXSizeAttribute...")
    let sizeError = AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue)
     guard sizeError == .success, let sizeRef = sizeValue, CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
        print("[getWindowFrame] Error: Could not get window size for \(bundleID). Error: \(sizeError.rawValue)")
        return nil
    }
    var windowSize: CGSize = .zero
    AXValueGetValue(sizeRef as! AXValue, .cgSize, &windowSize)
    print("[getWindowFrame] Successfully got window size: \(windowSize)")

    let finalFrame = CGRect(origin: windowPosition, size: windowSize)
    print("[getWindowFrame] Successfully retrieved window frame (global): \(finalFrame)")
    return finalFrame
}

// Helper to find screen containing the majority of a rect
func findScreen(for rect: CGRect) -> NSScreen? {
    var bestScreen: NSScreen? = nil
    var maxIntersectionArea: CGFloat = 0.0

    print("[findScreen] Finding screen for rect (global): \(rect)")
    for screen in NSScreen.screens {
        let screenFrame = screen.frame // screen.frame is in global coordinates
        let intersection = rect.intersection(screenFrame)
        
        if !intersection.isNull {
            let area = intersection.width * intersection.height
            print("[findScreen]   Checking screen \(screen.localizedName) (Frame: \(screenFrame)). Intersection area: \(area)")
            if area > maxIntersectionArea {
                maxIntersectionArea = area
                bestScreen = screen
            }
        }
    }
    
    if let foundScreen = bestScreen {
         print("[findScreen] Best match found: \(foundScreen.localizedName) with area \(maxIntersectionArea)")
    } else {
         // Fallback: Check if center point is on any screen
         let center = CGPoint(x: rect.midX, y: rect.midY)
         print("[findScreen] No intersection found, checking center point \(center)")
         bestScreen = NSScreen.screens.first { $0.frame.contains(center) }
         if let foundScreen = bestScreen {
             print("[findScreen] Fallback found screen containing center: \(foundScreen.localizedName)")
         } else {
              // Extreme Fallback: Use main screen
              print("[findScreen] Warning: Could not find screen for rect. Falling back to main screen.")
              bestScreen = NSScreen.main
         }
    }
   
    return bestScreen
}

class OverlayManager: ObservableObject {
    // Use a view controller to manage window lifetime 
    private var temporaryViewController: NSViewController?
    private var persistentViewControllers: [String: NSViewController] = [:]
    
    // Use a dispatch work item we can cancel if needed (only for temporary window)
    private var cleanupTask: DispatchWorkItem?
    
    // Keep strong references for ScreenCaptureKit screenshot
    private var screenshotFrameReceiver: AnyObject?
    private var screenshotStream: SCStream?
    
    deinit {
        cancelScheduledCleanup()
        closeTemporaryWindow()
    }
    
    // Basic annotation drawing with safer defaults
    func drawAnnotation(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, targetBundleID: String, completion: @escaping (Bool) -> Void) {
        // Just pass through with safe defaults
        drawAnnotation(x: x, y: y, width: width, height: height, targetBundleID: targetBundleID, 
                      activateTargetApp: false, bypassFocusCheck: true, completion: completion)
    }
    
    // Enhanced drawing function with safety checks
    func drawAnnotation(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, targetBundleID: String, 
                      activateTargetApp: Bool, bypassFocusCheck: Bool, completion: @escaping (Bool) -> Void) {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            print("[drawAnnotation] Warning: Not on main thread. Dispatching asynchronously.")
            DispatchQueue.main.async {
                self.drawAnnotation(x: x, y: y, width: width, height: height, targetBundleID: targetBundleID,
                                  activateTargetApp: activateTargetApp, bypassFocusCheck: bypassFocusCheck, completion: completion)
            }
            return
        }
        print("[drawAnnotation] Starting annotation draw. Target: \(targetBundleID), Activate: \(activateTargetApp), Bypass Focus: \(bypassFocusCheck), Rel Pos: (\(x), \(y)), Size: (\(width), \(height))")
        
        // --- Always check Accessibility Permissions --- 
        print("[drawAnnotation] Checking Accessibility Permissions.")
        if !checkAccessibilityPermissions() {
            print("[drawAnnotation] Error: Accessibility permissions denied or prompt required.")
            print("Please grant permissions in System Settings > Privacy & Security > Accessibility.")
             completion(false)
             return
         } else {
            print("[drawAnnotation] Accessibility permissions granted.")
         }

        // --- Define the core drawing logic --- 
        let performRelativeDraw = { [weak self] in
            guard let self = self else { 
                print("[performRelativeDraw] Error: Self is nil.")
                completion(false)
                return
            }
            
            print("[performRelativeDraw] Attempting to get window frame for \(targetBundleID).")
            if let windowFrame = getWindowFrame(for: targetBundleID) {
                // --- Determine Target Screen --- 
                print("[performRelativeDraw] Finding screen for window frame: \(windowFrame)")
                guard let targetScreen = findScreen(for: windowFrame) else {
                    // findScreen should always return at least the main screen as fallback
                    print("[performRelativeDraw] Error: findScreen unexpectedly returned nil. This should not happen.") 
                    completion(false)
                    return
                }
                print("[performRelativeDraw] Target screen identified: \(targetScreen.localizedName), Frame (global): \(targetScreen.frame)")
                // --- End Determine Target Screen ---

                print("[performRelativeDraw] Successfully got window frame (global): \(windowFrame). Input relative coords ignored: (\(x), \(y))")
                
                // Calculate coordinates to center the annotation (using global coordinates)
                let centerAbsoluteX = windowFrame.origin.x + (windowFrame.width / 2)
                let centerAbsoluteY = windowFrame.origin.y + (windowFrame.height / 2)
                let absoluteX = centerAbsoluteX - (width / 2)
                let absoluteY = centerAbsoluteY - (height / 2)
                print("[performRelativeDraw] Calculated centered absolute coordinates (global): (\(absoluteX), \(absoluteY)) for size (\(width), \(height))")
                
                // Check bounds against the TARGET screen's global frame
                let screenFrame = targetScreen.frame 
                let calculatedRect = CGRect(x: absoluteX, y: absoluteY, width: width, height: height)
                print("[performRelativeDraw] Target screen frame (global): \(screenFrame). Calculated target rect (global): \(calculatedRect)")
                
                // Check if the calculated rect intersects the target screen at all
                if !calculatedRect.intersects(screenFrame) {
                     print("[performRelativeDraw] Error: Calculated rectangle does not intersect target screen frame. Not drawing.")
                     completion(false)
                     return
                }

                print("[performRelativeDraw] Calculated rectangle intersects target screen. Drawing...")
                // Pass targetScreen and global coordinates to justDrawRectangle
                self.justDrawRectangle(screen: targetScreen, x: absoluteX, y: absoluteY, width: width, height: height)
                completion(true)
                
            } else {
                print("[performRelativeDraw] Error: Failed to get window frame for \(targetBundleID). Cannot draw annotation.")
                completion(false)
            }
        }

        // --- Execute based on activateTargetApp --- 
        if activateTargetApp {
            print("[drawAnnotation] Activate flag is true. Finding and activating target app \(targetBundleID).")
            guard let targetApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == targetBundleID }) else {
                 print("[drawAnnotation] Error: Target app \(targetBundleID) not found for activation.")
                 completion(false)
                 return
            }
            targetApp.activate(options: [])
            
            // Wait a bit for activation and window focus, then attempt relative draw
            print("[drawAnnotation] Scheduling relative draw after 0.5s delay for activation.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("[drawAnnotation] Activation delay complete. Performing relative draw.")
                performRelativeDraw()
            }
        } else {
             print("[drawAnnotation] Activate flag is false. Proceeding with checks and relative draw.")
             // Validate that the target app is frontmost if not bypassing focus check
             if !bypassFocusCheck {
                 print("[drawAnnotation] Checking if target app \(targetBundleID) is frontmost (bypassFocusCheck is false).")
                 guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
                       frontmostApp.bundleIdentifier == targetBundleID else {
                     print("[drawAnnotation] Error: Target app \(targetBundleID) is not frontmost. Not drawing.")
                     completion(false)
                     return
                 }
                 print("[drawAnnotation] Target app \(targetBundleID) is frontmost.")
             } else {
                 print("[drawAnnotation] Skipping frontmost app check because bypassFocusCheck is true.")
             }

             // Perform relative draw immediately
             print("[drawAnnotation] Performing relative draw immediately.")
             performRelativeDraw()
        }
    }
    
    // Absolute minimal, safest drawing function - now uses view controllers
    internal func justDrawRectangle(screen targetScreen: NSScreen, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, 
                                   id: String? = nil, persistent: Bool = false, 
                                   strokeColor: NSColor = .green, fillColor: NSColor = .green.withAlphaComponent(0.3),
                                   annotationText: String? = nil) {
        // Sanity check for main thread
        if !Thread.isMainThread {
            print("[justDrawRectangle] Warning: Not on main thread. Dispatching asynchronously.")
            DispatchQueue.main.async {
                self.justDrawRectangle(screen: targetScreen, x: x, y: y, width: width, height: height, 
                                       id: id, persistent: persistent, strokeColor: strokeColor, fillColor: fillColor,
                                       annotationText: annotationText)
            }
            return
        }
        
        // First, close any existing temporary window if drawing a new temporary
        if !persistent {
            print("[justDrawRectangle] Drawing temporary window - explicitly closing any existing temporary window")
            // Cancel any pending cleanup task
            cancelScheduledCleanup()
            // Close existing temporary window immediately
            closeTemporaryWindow()
        } else if let regionId = id, persistentViewControllers[regionId] != nil {
            // If drawing persistent and ID already exists, remove the old one first
            print("[justDrawRectangle] Persistent window with ID \(regionId) already exists. Closing old one.")
            closePersistentWindow(id: regionId)
        }
        
        let mode = persistent ? "persistent (id: \(id ?? "nil"))" : "temporary"
        let textLog = annotationText != nil ? " with text: '\(annotationText!)'" : ""
        print("[justDrawRectangle] Drawing \(mode) on screen: \(targetScreen.localizedName) at global coords: (\(x), \(y)), Size: (\(width), \(height))\(textLog)")
        
        // Calculate view coordinates (relative to screen)
        let viewX = x - targetScreen.frame.origin.x
        let viewY = y - targetScreen.frame.origin.y
        let rectangleForView = CGRect(x: viewX, y: viewY, width: width, height: height)
        
        // Create a new ViewController with a RectangleView, passing text
        let viewController = RectangleViewController(
            screenFrame: targetScreen.frame,
            rectangle: rectangleForView,
            strokeColor: strokeColor,
            fillColor: fillColor,
            annotationText: annotationText
        )
        
        // Store the controller in the appropriate collection
        if persistent, let regionId = id {
            print("[justDrawRectangle] Storing persistent view controller for ID: \(regionId)")
            persistentViewControllers[regionId] = viewController
        } else {
            // Make absolutely sure any previous controller is gone
            if temporaryViewController != nil {
                print("[justDrawRectangle] Ensuring previous temporary controller is explicitly released")
                temporaryViewController = nil
            }
            
            // Store new temporary view controller
            print("[justDrawRectangle] Storing temporary view controller.")
            temporaryViewController = viewController
            
            // Schedule cleanup for temporary windows
            scheduleCleanup(delay: 5.0)
        }
        
        // Log success
        print("{\"status\":\"drawn\", \"ts\":" + String(Int(Date().timeIntervalSince1970 * 1000)) + "}")
        print("[justDrawRectangle] Window created. Mode: \(mode).")
    }
    
    // Draws a PERSISTENT centered annotation relative to target app and returns details
    func observeAnnotation(targetBundleID: String, width: CGFloat, height: CGFloat, 
                           bypassFocusCheck: Bool, activateTargetApp: Bool, 
                           completion: @escaping (_ success: Bool, _ regionId: String?, _ observedRect: CGRect?, _ onScreen: NSScreen?) -> Void) {
                           
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            print("[observeAnnotation] Warning: Not on main thread. Dispatching asynchronously.")
            DispatchQueue.main.async {
                self.observeAnnotation(targetBundleID: targetBundleID, width: width, height: height, 
                                     bypassFocusCheck: bypassFocusCheck, activateTargetApp: activateTargetApp, 
                                     completion: completion)
            }
            return
        }
        print("[observeAnnotation] Starting observe annotation. Target: \(targetBundleID), Activate: \(activateTargetApp), Bypass Focus: \(bypassFocusCheck), Size: (\(width), \(height))")
        
        // Generate ID upfront for this observation region
        let regionId = UUID().uuidString

        // --- Always check Accessibility Permissions --- 
        print("[observeAnnotation] Checking Accessibility Permissions.")
        if !checkAccessibilityPermissions() {
            print("[observeAnnotation] Error: Accessibility permissions denied or prompt required.")
            print("Please grant permissions in System Settings > Privacy & Security > Accessibility.")
             completion(false, nil, nil, nil)
             return
         } else {
            print("[observeAnnotation] Accessibility permissions granted.")
         }

        // --- Define the core drawing logic (modified from drawAnnotation) --- 
        let performRelativeObserveDraw = { [weak self] in
            guard let self = self else { 
                print("[performRelativeObserveDraw] Error: Self is nil.")
                completion(false, nil, nil, nil)
                return
            }
            
            print("[performRelativeObserveDraw] Attempting to get window frame for \(targetBundleID).")
            if let windowFrame = getWindowFrame(for: targetBundleID) {
                print("[performRelativeObserveDraw] Finding screen for window frame: \(windowFrame)")
                guard let targetScreen = findScreen(for: windowFrame) else {
                    print("[performRelativeObserveDraw] Error: findScreen unexpectedly returned nil.") 
                    completion(false, nil, nil, nil)
                    return
                }
                print("[performRelativeObserveDraw] Target screen identified: \(targetScreen.localizedName), Frame (global): \(targetScreen.frame)")

                print("[performRelativeObserveDraw] Successfully got window frame (global): \(windowFrame).")
                
                // Calculate centered absolute coordinates (global)
                let centerAbsoluteX = windowFrame.origin.x + (windowFrame.width / 2)
                let centerAbsoluteY = windowFrame.origin.y + (windowFrame.height / 2)
                let absoluteX = centerAbsoluteX - (width / 2)
                let absoluteY = centerAbsoluteY - (height / 2)
                let calculatedRect = CGRect(x: absoluteX, y: absoluteY, width: width, height: height)
                print("[performRelativeObserveDraw] Calculated centered absolute rect (global): \(calculatedRect)")
                
                // Check bounds against the TARGET screen's global frame
                let screenFrame = targetScreen.frame 
                print("[performRelativeObserveDraw] Target screen frame (global): \(screenFrame). Calculated target rect (global): \(calculatedRect)")
                
                if !calculatedRect.intersects(screenFrame) {
                     print("[performRelativeObserveDraw] Error: Calculated rectangle does not intersect target screen frame. Not drawing.")
                     completion(false, nil, nil, nil)
                     return
                }

                print("[performRelativeObserveDraw] Calculated rectangle intersects target screen. Drawing persistent blue box...")
                // Draw persistent blue box using the calculated details
                self.justDrawRectangle(
                    screen: targetScreen, x: absoluteX, y: absoluteY, width: width, height: height, 
                    id: regionId, 
                    persistent: true, 
                    strokeColor: .systemBlue, 
                    fillColor: .systemBlue.withAlphaComponent(0.15)
                )
                // Report success via completion handler
                completion(true, regionId, calculatedRect, targetScreen)
                
            } else {
                print("[performRelativeObserveDraw] Error: Failed to get window frame for \(targetBundleID). Cannot draw/observe annotation.")
                completion(false, nil, nil, nil)
            }
        }

        // --- Execute based on activateTargetApp --- 
        if activateTargetApp {
            print("[observeAnnotation] Activate flag is true. Finding and activating target app \(targetBundleID).")
            guard let targetApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == targetBundleID }) else {
                 print("[observeAnnotation] Error: Target app \(targetBundleID) not found for activation.")
                 completion(false, nil, nil, nil)
                 return
            }
            targetApp.activate(options: [])
            
            print("[observeAnnotation] Scheduling relative observe draw after 0.5s delay for activation.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("[observeAnnotation] Activation delay complete. Performing relative observe draw.")
                performRelativeObserveDraw()
            }
        } else {
             print("[observeAnnotation] Activate flag is false. Proceeding with checks and relative observe draw.")
             if !bypassFocusCheck {
                 print("[observeAnnotation] Checking if target app \(targetBundleID) is frontmost (bypassFocusCheck is false).")
                 guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
                       frontmostApp.bundleIdentifier == targetBundleID else {
                     print("[observeAnnotation] Error: Target app \(targetBundleID) is not frontmost. Not drawing/observing.")
                     completion(false, nil, nil, nil)
                     return
                 }
                 print("[observeAnnotation] Target app \(targetBundleID) is frontmost.")
             } else {
                 print("[observeAnnotation] Skipping frontmost app check because bypassFocusCheck is true.")
             }

             print("[observeAnnotation] Performing relative observe draw immediately.")
             performRelativeObserveDraw()
        }
    }
    
    // Schedule cleanup with the ability to cancel it
    private func scheduleCleanup(delay: TimeInterval) {
        // Cancel any existing cleanup
        cancelScheduledCleanup()
        
        // Create a new cleanup task
        let task = DispatchWorkItem { [weak self] in
            print("[scheduleCleanup] Cleanup task executing.")
            self?.closeTemporaryWindow()
        }
        
        // Store the task so we can cancel it if needed
        self.cleanupTask = task
        
        // Schedule the task
        print("[scheduleCleanup] Scheduling window close in \(delay) seconds.")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
    
    // Cancel scheduled cleanup 
    private func cancelScheduledCleanup() {
        if cleanupTask != nil {
            print("[cancelScheduledCleanup] Cancelling previous cleanup task.")
            cleanupTask?.cancel()
            cleanupTask = nil
        }
    }
    
    // Close the temporary window safely
    private func closeTemporaryWindow() {
        // Make sure we're on the main thread
        if !Thread.isMainThread {
            print("[closeTemporaryWindow] Warning: Not on main thread. Dispatching asynchronously.")
            DispatchQueue.main.async {
                self.closeTemporaryWindow()
            }
            return
        }

        if temporaryViewController != nil {
            print("[closeTemporaryWindow] Releasing temporary view controller.")
            
            // Get reference to the controller we're about to release
            if let controller = temporaryViewController {
                // Remove the window from screen
                if let window = (controller as? RectangleViewController)?.window {
                    print("[closeTemporaryWindow] Explicitly removing window from screen")
                    window.orderOut(nil)
                }
            }
            
            // First set to nil to break any references
            temporaryViewController = nil
            
            // Force a garbage collection to help with cleanup
            autoreleasepool {
                print("[closeTemporaryWindow] Running autorelease pool to clean up resources")
            }
            
            // Signal ready state
            DispatchQueue.main.async {
                print("{\"status\":\"ready\", \"ts\":" + String(Int(Date().timeIntervalSince1970 * 1000)) + "}")
            }
        } else {
            // Still signal ready even if no window to close
            print("{\"status\":\"ready\", \"ts\":" + String(Int(Date().timeIntervalSince1970 * 1000)) + "}")
        }
    }
    
    // Close a specific persistent window
    private func closePersistentWindow(id: String) {
        if !Thread.isMainThread {
            print("[closePersistentWindow] Warning: Not on main thread. Dispatching asynchronously.")
            DispatchQueue.main.async {
                self.closePersistentWindow(id: id)
            }
            return
        }
        
        print("[closePersistentWindow] Attempting to close persistent window with ID: \(id)")
        if persistentViewControllers.removeValue(forKey: id) != nil {
            print("[closePersistentWindow] Released persistent view controller for ID: \(id)")
        } else {
            print("[closePersistentWindow] No persistent window found with ID: \(id)")
        }
    }

    // Clean up everything (temporary window, persistent windows, timer)
    private func cleanupEverything() {
        // Make sure we're on the main thread
        if !Thread.isMainThread {
             print("[cleanupEverything] Warning: Not on main thread. Dispatching asynchronously.")
            DispatchQueue.main.async {
                self.cleanupEverything()
            }
            return
        }
         print("[cleanupEverything] Cleaning up overlays and timers.")
         
        // Cancel any scheduled cleanup for temporary window
        cancelScheduledCleanup()
        
        // Close the temporary window
        temporaryViewController = nil
        
        // Close all persistent windows
        let persistentIds = Array(persistentViewControllers.keys)
        print("[cleanupEverything] Closing \(persistentIds.count) persistent windows.")
        persistentViewControllers.removeAll()
        
        // Signal that cleanup is complete
        print("{\"status\":\"ready\", \"ts\":" + String(Int(Date().timeIntervalSince1970 * 1000)) + "}")
    }
    
    // Public cleanup method
    func clearOverlays() {
        print("[clearOverlays] Public clear method called.")
        cleanupEverything()
    }

    /// Takes a screenshot of the main window of the app with the given bundle ID using ScreenCaptureKit (async).
    /// Calls the completion handler with an NSImage of the window, or nil if not possible.
    func screenshotOfAppWindow(bundleID: String, completion: @escaping (NSImage?) -> Void) {
        // Check if screen recording permission is granted
        if !CGPreflightScreenCaptureAccess() {
            print("[ScreenCaptureKit] Screen recording permission not granted")
            // Request permission
            CGRequestScreenCaptureAccess()
            completion(nil)
            return
        }
        
        // Clear any existing screenshot objects
        screenshotFrameReceiver = nil
        screenshotStream = nil
        
        // Create our output handler class
        class FrameReceiver: NSObject, SCStreamOutput {
            let completion: (NSImage?) -> Void
            var didReceiveFrame = false
            weak var manager: OverlayManager?
            
            init(completion: @escaping (NSImage?) -> Void, manager: OverlayManager) {
                self.completion = completion
                self.manager = manager
                super.init()
            }
            
            func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
                // Only process video frames
                guard outputType == .screen else { return }
                
                print("[ScreenCaptureKit] Received sample buffer of type: \(outputType)")
                
                // Only handle the first frame
                guard !didReceiveFrame else { return }
                didReceiveFrame = true
                
                // Process the frame
                if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let ciImage = CIImage(cvImageBuffer: imageBuffer)
                    let rep = NSCIImageRep(ciImage: ciImage)
                    let nsImage = NSImage(size: rep.size)
                    nsImage.addRepresentation(rep)
                    
                    // Call completion on main thread
                    DispatchQueue.main.async {
                        self.completion(nsImage)
                    }
                    
                    print("[ScreenCaptureKit] Successfully captured image")
                } else {
                    print("[ScreenCaptureKit] Failed to get image buffer from sample buffer")
                    DispatchQueue.main.async {
                        self.completion(nil)
                    }
                }
                
                // Stop the capture and clean up
                DispatchQueue.main.async {
                    print("[ScreenCaptureKit] Stopping stream capture")
                    stream.stopCapture { error in
                        if let error = error {
                            print("[ScreenCaptureKit] Error stopping capture: \(error)")
                        }
                        
                        // Release strong references
                        self.manager?.screenshotFrameReceiver = nil
                        self.manager?.screenshotStream = nil
                    }
                }
            }
        }
        
        // Start the async task to capture screenshot
        Task {
            do {
                print("[ScreenCaptureKit] Starting screenshot capture for \(bundleID)")
                
                // 1. Get available content
                print("[ScreenCaptureKit] Fetching available content")
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                
                // Print all windows for debugging
                print("[ScreenCaptureKit] Available windows:")
                for window in content.windows {
                    print("  - \(window.title ?? "Untitled") (Bundle: \(window.owningApplication?.bundleIdentifier ?? "None"))")
                }
                
                // 2. Find our target window
                guard let window = content.windows.first(where: { $0.owningApplication?.bundleIdentifier == bundleID }) else {
                    print("[ScreenCaptureKit] No window found for bundle ID \(bundleID)")
                    DispatchQueue.main.async {
                        completion(nil)
                    }
                    return
                }
                
                print("[ScreenCaptureKit] Found window: \(window.title ?? "Untitled") with frame: \(window.frame)")
                
                // 3. Create stream configuration
                let config = SCStreamConfiguration()
                config.width = Int(window.frame.width)
                config.height = Int(window.frame.height)
                config.showsCursor = false
                config.pixelFormat = kCVPixelFormatType_32BGRA
                
                // 4. Create content filter
                let filter = SCContentFilter(desktopIndependentWindow: window)
                
                // 5. Create frame receiver and keep strong reference
                let receiver = FrameReceiver(completion: completion, manager: self)
                self.screenshotFrameReceiver = receiver
                
                // 6. Create stream (without delegate)
                print("[ScreenCaptureKit] Creating capture stream")
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                self.screenshotStream = stream
                
                // 7. Add our receiver as a stream output
                print("[ScreenCaptureKit] Adding stream output")
                try stream.addStreamOutput(receiver, type: .screen, sampleHandlerQueue: .main)
                
                // 8. Start capture
                print("[ScreenCaptureKit] Starting capture")
                try await stream.startCapture()
                
                // The frame will be delivered to the receiver.stream() method
                
            } catch {
                print("[ScreenCaptureKit] Error: \(error)")
                DispatchQueue.main.async {
                    completion(nil)
                    self.screenshotFrameReceiver = nil
                    self.screenshotStream = nil
                }
            }
        }
    }

    @available(*, unavailable, message: "Use the async screenshotOfAppWindow(bundleID:completion:) version instead.")
    func screenshotOfAppWindow(bundleID: String) -> NSImage? {
        fatalError("Use the async screenshotOfAppWindow(bundleID:completion:) version instead.")
    }

    // Draws an annotation at a specific rectangle relative to the target app window.
    func drawAnnotationAtRect(relativeRect: CGRect, annotationText: String?, targetBundleID: String, 
                             activateTargetApp: Bool, bypassFocusCheck: Bool, completion: @escaping (Bool) -> Void) {
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            print("[drawAnnotationAtRect] Warning: Not on main thread. Dispatching asynchronously.")
            DispatchQueue.main.async {
                self.drawAnnotationAtRect(relativeRect: relativeRect, annotationText: annotationText, targetBundleID: targetBundleID,
                                          activateTargetApp: activateTargetApp, bypassFocusCheck: bypassFocusCheck, completion: completion)
            }
            return
        }
        print("[drawAnnotationAtRect] Starting annotation draw. Target: \(targetBundleID), Activate: \(activateTargetApp), Bypass Focus: \(bypassFocusCheck), Rel Rect: \(relativeRect), Text: \(annotationText ?? "None")")

        // --- Always check Accessibility Permissions --- 
        print("[drawAnnotationAtRect] Checking Accessibility Permissions.")
        if !checkAccessibilityPermissions() {
            print("[drawAnnotationAtRect] Error: Accessibility permissions denied or prompt required.")
            print("Please grant permissions in System Settings > Privacy & Security > Accessibility.")
             completion(false)
             return
         } else {
            print("[drawAnnotationAtRect] Accessibility permissions granted.")
         }

        // --- Define the core drawing logic --- 
        let performRelativeDraw = { [weak self] in
            guard let self = self else { 
                print("[performRelativeDraw - AtRect] Error: Self is nil.")
                completion(false)
                return
            }
            
            print("[performRelativeDraw - AtRect] Attempting to get window frame for \(targetBundleID).")
            if let windowFrame = getWindowFrame(for: targetBundleID) {
                // --- Determine Target Screen --- 
                print("[performRelativeDraw - AtRect] Finding screen for window frame: \(windowFrame)")
                guard let targetScreen = findScreen(for: windowFrame) else {
                    print("[performRelativeDraw - AtRect] Error: findScreen unexpectedly returned nil.") 
                    completion(false)
                    return
                }
                print("[performRelativeDraw - AtRect] Target screen identified: \(targetScreen.localizedName), Frame (global): \(targetScreen.frame)")

                print("[performRelativeDraw - AtRect] Successfully got window frame (global): \(windowFrame).")
                
                // Calculate absolute global coordinates from relative rect
                let absoluteX = windowFrame.origin.x + relativeRect.origin.x
                let absoluteY = windowFrame.origin.y + relativeRect.origin.y
                let absoluteRect = CGRect(x: absoluteX, y: absoluteY, width: relativeRect.width, height: relativeRect.height)
                print("[performRelativeDraw - AtRect] Calculated absolute coordinates (global): \(absoluteRect)")
                
                // Check bounds against the TARGET screen's global frame
                let screenFrame = targetScreen.frame 
                print("[performRelativeDraw - AtRect] Target screen frame (global): \(screenFrame). Calculated target rect (global): \(absoluteRect)")
                
                // Check if the calculated rect intersects the target screen at all
                if !absoluteRect.intersects(screenFrame) {
                     print("[performRelativeDraw - AtRect] Error: Calculated rectangle does not intersect target screen frame. Not drawing.")
                     completion(false)
                     return
                }

                print("[performRelativeDraw - AtRect] Calculated rectangle intersects target screen. Drawing...")
                // Draw a temporary rectangle with text
                self.justDrawRectangle(
                    screen: targetScreen, x: absoluteX, y: absoluteY, 
                    width: relativeRect.width, height: relativeRect.height,
                    annotationText: annotationText
                )
                completion(true)
                
            } else {
                print("[performRelativeDraw - AtRect] Error: Failed to get window frame for \(targetBundleID). Cannot draw annotation.")
                completion(false)
            }
        }

        // --- Execute based on activateTargetApp --- 
        if activateTargetApp {
            print("[drawAnnotationAtRect] Activate flag is true. Finding and activating target app \(targetBundleID).")
            guard let targetApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == targetBundleID }) else {
                 print("[drawAnnotationAtRect] Error: Target app \(targetBundleID) not found for activation.")
                 completion(false)
                 return
            }
            targetApp.activate(options: [])
            
            // Wait a bit for activation and window focus, then attempt relative draw
            print("[drawAnnotationAtRect] Scheduling relative draw after 0.5s delay for activation.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                print("[drawAnnotationAtRect] Activation delay complete. Performing relative draw.")
                performRelativeDraw()
            }
        } else {
             print("[drawAnnotationAtRect] Activate flag is false. Proceeding with checks and relative draw.")
             // Validate that the target app is frontmost if not bypassing focus check
             if !bypassFocusCheck {
                 print("[drawAnnotationAtRect] Checking if target app \(targetBundleID) is frontmost (bypassFocusCheck is false).")
                 guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
                       frontmostApp.bundleIdentifier == targetBundleID else {
                     print("[drawAnnotationAtRect] Error: Target app \(targetBundleID) is not frontmost. Not drawing.")
                     completion(false)
                     return
                 }
                 print("[drawAnnotationAtRect] Target app \(targetBundleID) is frontmost.")
             } else {
                 print("[drawAnnotationAtRect] Skipping frontmost app check because bypassFocusCheck is true.")
             }

             // Perform relative draw immediately
             print("[drawAnnotationAtRect] Performing relative draw immediately.")
             performRelativeDraw()
        }
    }
}

// Custom ViewController to manage window lifecycle
class RectangleViewController: NSViewController {
    // Make window property accessible so parent can access it
    var window: NSWindow?
    
    init(screenFrame: CGRect, rectangle: CGRect, strokeColor: NSColor = .green, fillColor: NSColor = .green.withAlphaComponent(0.3), annotationText: String? = nil) {
        super.init(nibName: nil, bundle: nil)
        
        // Create a custom view, passing text
        let customView = RectangleView(
            frame: NSRect(origin: .zero, size: screenFrame.size),
            rectangleFrame: rectangle,
            strokeColor: strokeColor,
            fillColor: fillColor,
            annotationText: annotationText
        )
        
        // Set the view
        self.view = customView
        
        // Create a borderless window
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        // Set window properties
        window.level = .screenSaver
        window.backgroundColor = NSColor.clear
        window.isOpaque = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        
        // Set the content view controller
        window.contentViewController = self
        
        // Show the window
        window.orderFrontRegardless()
        
        // Store the window reference
        self.window = window
        
        print("[RectangleViewController] Created with window on screen: \(screenFrame)")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        print("[RectangleViewController] Deinitializing and closing window")
        // Explicitly remove window from screen
        window?.orderOut(nil)
        // Set content view controller to nil to break reference cycle
        window?.contentViewController = nil
        // Close the window when the view controller is deallocated
        window?.close()
        window = nil
    }
}

// Simplified Rectangle view with no references to its window
class RectangleView: NSView {
    private var rectangleFrame: CGRect
    private var strokeColor: NSColor
    private var fillColor: NSColor
    private var lineWidth: CGFloat
    private var annotationText: String?
    private var textColor: NSColor = .white

    init(frame: CGRect, rectangleFrame: CGRect, strokeColor: NSColor = .green, fillColor: NSColor = .green.withAlphaComponent(0.3), lineWidth: CGFloat = 4.0, annotationText: String? = nil) {
        self.rectangleFrame = rectangleFrame
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.annotationText = annotationText
        super.init(frame: frame)
        let textLog = annotationText != nil ? " with text: '\(annotationText!)'" : ""
        print("[RectangleView init] Initialized with frame: \(frame), rectangle: \(rectangleFrame), stroke: \(strokeColor), fill: \(fillColor)\(textLog)")
        // Make the view layer-backed for better rendering
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor // Window is clear, view background too
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented") // Make explicit that coder init is not supported
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let textLog = annotationText != nil ? " with text: '\(annotationText!)'" : ""
        print("[RectangleView draw] Drawing rectangleFrame: \(rectangleFrame) with stroke: \(strokeColor), fill: \(fillColor)\(textLog) within dirtyRect: \(dirtyRect)")

        // Get the current graphics context
        guard let context = NSGraphicsContext.current?.cgContext else { 
            print("[RectangleView draw] Error: Failed to get graphics context.")
            return 
        }

        // Create shadow FIRST, so both rect and text get it
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 2, height: -2)
        shadow.set()

        // Draw Rectangle
        context.saveGState()
        context.setFillColor(fillColor.cgColor)
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(lineWidth)
        let path = NSBezierPath(roundedRect: rectangleFrame, xRadius: 4, yRadius: 4)
        path.fill()
        path.stroke()
        context.restoreGState()

        // Draw Annotation Text if available
        if let text = annotationText, !text.isEmpty {
            context.saveGState()

            // Text attributes
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: textColor,
                .paragraphStyle: paragraphStyle,
                // Add a stroke/outline to the text for better visibility
                .strokeColor: NSColor.black.withAlphaComponent(0.7), 
                .strokeWidth: -2.0
            ]

            // Calculate text position: Centered below the rectangle
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: rectangleFrame.midX - textSize.width / 2,
                // Position below the rectangle with some padding
                y: rectangleFrame.maxY + 5, 
                width: textSize.width,
                height: textSize.height
            )
            
            // Apply shadow specifically for text (needed after state restore)
            shadow.set() 

            // Draw the text
            print("[RectangleView draw] Drawing text '\(text)' at rect: \(textRect)")
            (text as NSString).draw(in: textRect, withAttributes: attributes)
            
            context.restoreGState()
        }
        
        print("[RectangleView draw] Finished drawing.")
    }

    // Ensure we use flipped coordinates - THIS IS CRITICAL for NSView drawing
    override var isFlipped: Bool {
        return true // Use top-left origin coordinate system internally for drawing
    }
}

// Simple overlay view that draws a rectangle - // NOTE: This struct seems unused by OverlayManager
struct OverlayView: View { // Consider removing if not used
    let rect: CGRect
    
    var body: some View {
        ZStack {
            Color.clear
            
            // Red rectangle at specified position
            Rectangle()
                .stroke(Color.red, lineWidth: 5)
                .background(Color.red.opacity(0.3))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .edgesIgnoringSafeArea(.all)
    }
} 