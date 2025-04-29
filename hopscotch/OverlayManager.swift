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
            targetApp.activate(options: .activateIgnoringOtherApps)
            
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
                                   strokeColor: NSColor = .green, fillColor: NSColor = .green.withAlphaComponent(0.3)) {
        // Sanity check for main thread
        if !Thread.isMainThread {
            print("[justDrawRectangle] Warning: Not on main thread. Dispatching asynchronously.")
            DispatchQueue.main.async {
                self.justDrawRectangle(screen: targetScreen, x: x, y: y, width: width, height: height, 
                                       id: id, persistent: persistent, strokeColor: strokeColor, fillColor: fillColor)
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
        print("[justDrawRectangle] Drawing \(mode) on screen: \(targetScreen.localizedName) at global coords: (\(x), \(y)), Size: (\(width), \(height))")
        
        // Calculate view coordinates (relative to screen)
        let viewX = x - targetScreen.frame.origin.x
        let viewY = y - targetScreen.frame.origin.y
        let rectangleForView = CGRect(x: viewX, y: viewY, width: width, height: height)
        
        // Create a new ViewController with a RectangleView
        let viewController = RectangleViewController(
            screenFrame: targetScreen.frame,
            rectangle: rectangleForView,
            strokeColor: strokeColor,
            fillColor: fillColor
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
            targetApp.activate(options: .activateIgnoringOtherApps)
            
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
}

// Custom ViewController to manage window lifecycle
class RectangleViewController: NSViewController {
    // Make window property accessible so parent can access it
    var window: NSWindow?
    
    init(screenFrame: CGRect, rectangle: CGRect, strokeColor: NSColor = .green, fillColor: NSColor = .green.withAlphaComponent(0.3)) {
        super.init(nibName: nil, bundle: nil)
        
        // Create a custom view
        let customView = RectangleView(
            frame: NSRect(origin: .zero, size: screenFrame.size),
            rectangleFrame: rectangle,
            strokeColor: strokeColor,
            fillColor: fillColor
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

    init(frame: CGRect, rectangleFrame: CGRect, strokeColor: NSColor = .green, fillColor: NSColor = .green.withAlphaComponent(0.3), lineWidth: CGFloat = 4.0) {
        self.rectangleFrame = rectangleFrame
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        super.init(frame: frame)
        print("[RectangleView init] Initialized with frame: \(frame), rectangle: \(rectangleFrame), stroke: \(strokeColor), fill: \(fillColor)")
        // Make the view layer-backed for better rendering
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor // Window is clear, view background too
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented") // Make explicit that coder init is not supported
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        print("[RectangleView draw] Drawing rectangleFrame: \(rectangleFrame) with stroke: \(strokeColor), fill: \(fillColor) within dirtyRect: \(dirtyRect)")

        // Get the current graphics context
        guard let context = NSGraphicsContext.current?.cgContext else { 
            print("[RectangleView draw] Error: Failed to get graphics context.")
            return 
        }

        // Set up the rectangle fill color
        context.setFillColor(fillColor.cgColor)

        // Set up the stroke color and width
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(lineWidth)

        // Use bezier path for rounded corners
        let path = NSBezierPath(roundedRect: rectangleFrame, xRadius: 4, yRadius: 4)

        // Create shadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 2, height: -2)
        shadow.set()

        // Draw with path
        fillColor.setFill()
        strokeColor.setStroke()
        path.fill()
        path.stroke()
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