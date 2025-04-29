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
             // Don't release mainWindow here if it wasn't successfully obtained
             return nil
        }
    } else {
        print("[getWindowFrame] Successfully got main window.")
    }

    // Ensure mainWindow is of the correct type before proceeding
    guard let windowElement = mainWindow as! AXUIElement? else {
         print("[getWindowFrame] Error: Main window reference obtained is not an AXUIElement.")
         // if mainWindow != nil { CFRelease(mainWindow) } // No need to release with ARC
         return nil
    }


    // Get window position
    var positionValue: CFTypeRef?
    print("[getWindowFrame] Trying to get kAXPositionAttribute...")
    let positionError = AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionValue)
    guard positionError == .success, let positionRef = positionValue, CFGetTypeID(positionRef) == AXValueGetTypeID() else {
        print("[getWindowFrame] Error: Could not get window position for \(bundleID). Error: \(positionError.rawValue)")
        // if positionValue != nil { CFRelease(positionValue) } // No need to release with ARC
        // if mainWindow != nil { CFRelease(mainWindow) } // No need to release with ARC
        return nil
    }

    var windowPosition: CGPoint = .zero
    AXValueGetValue(positionRef as! AXValue, .cgPoint, &windowPosition)
    print("[getWindowFrame] Successfully got window position: \(windowPosition)")
    // CFRelease(positionRef) // No need to release with ARC

    // Get window size
    var sizeValue: CFTypeRef?
    print("[getWindowFrame] Trying to get kAXSizeAttribute...")
    let sizeError = AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue)
     guard sizeError == .success, let sizeRef = sizeValue, CFGetTypeID(sizeRef) == AXValueGetTypeID() else {
        print("[getWindowFrame] Error: Could not get window size for \(bundleID). Error: \(sizeError.rawValue)")
        // if sizeValue != nil { CFRelease(sizeValue) } // No need to release with ARC
        // if mainWindow != nil { CFRelease(mainWindow) } // No need to release with ARC
        return nil
    }

    var windowSize: CGSize = .zero
    AXValueGetValue(sizeRef as! AXValue, .cgSize, &windowSize)
    print("[getWindowFrame] Successfully got window size: \(windowSize)")
    // CFRelease(sizeRef) // No need to release with ARC

    // Release the main window reference - ARC handles this
    // if mainWindow != nil { CFRelease(mainWindow) }

    let finalFrame = CGRect(origin: windowPosition, size: windowSize)
    print("[getWindowFrame] Successfully retrieved window frame: \(finalFrame)")
    return finalFrame
}

class OverlayManager: ObservableObject {
    // Use an optional to track our window
    private var windowRef: NSWindow?
    
    // Use a dispatch work item we can cancel if needed
    private var cleanupTask: DispatchWorkItem?
    
    // No Core Animation, just plain NSView drawing
    deinit {
        // Make sure we clean up when this object is deallocated
        cancelScheduledCleanup()
        closeWindow()
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
        
        // Clean up existing window and scheduled cleanups
        cleanupEverything()
        
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
                print("[performRelativeDraw] Successfully got window frame: \(windowFrame). Input relative coords ignored: (\(x), \(y))")
                
                // --- Calculate coordinates to center the annotation --- 
                // Use the provided width and height, but calculate x,y to center it in the windowFrame
                let centerAbsoluteX = windowFrame.origin.x + (windowFrame.width / 2)
                let centerAbsoluteY = windowFrame.origin.y + (windowFrame.height / 2)
                
                // Adjust origin based on the annotation's own width/height to center it
                let absoluteX = centerAbsoluteX - (width / 2)
                let absoluteY = centerAbsoluteY - (height / 2)
                print("[performRelativeDraw] Calculated centered absolute coordinates: (\(absoluteX), \(absoluteY)) for size (\(width), \(height))")
                // --- End centering calculation --- 
                
                guard let screen = NSScreen.main else {
                    print("[performRelativeDraw] Error: Cannot get main screen frame.")
                    completion(false)
                    return
                }
                let screenFrame = screen.frame
                let calculatedRect = CGRect(x: absoluteX, y: absoluteY, width: width, height: height)
                print("[performRelativeDraw] Main screen frame: \(screenFrame). Calculated target rect: \(calculatedRect)")
                
                if screenFrame.contains(calculatedRect.origin) { 
                    print("[performRelativeDraw] Calculated rectangle origin is on-screen. Drawing...")
                    self.justDrawRectangle(x: absoluteX, y: absoluteY, width: width, height: height)
                    completion(true)
                } else {
                    print("[performRelativeDraw] Error: Calculated rectangle origin (\(calculatedRect.origin)) is off-screen (Screen: \(screenFrame)).")
                    completion(false)
                }
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
    
    // Absolute minimal, safest drawing function
    private func justDrawRectangle(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        // Sanity check for main thread
        if !Thread.isMainThread {
             print("[justDrawRectangle] Warning: Not on main thread. Dispatching asynchronously.")
            DispatchQueue.main.async {
                self.justDrawRectangle(x: x, y: y, width: width, height: height)
            }
            return
        }
        print("[justDrawRectangle] Drawing rectangle at screen coords: (\(x), \(y)), Size: (\(width), \(height))")
        
        // First close any existing window
        closeWindow()
        
        // Create a new window only if we have a valid screen
        guard let screen = NSScreen.main else {
            print("[justDrawRectangle] Error: No main screen available")
            return
        }
        print("[justDrawRectangle] Using screen frame: \(screen.frame)")
        
        // Create a borderless window
        let newWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: true // Using defer: true can help with memory issues
        )
        
        // Set window properties
        newWindow.level = .screenSaver
        newWindow.backgroundColor = NSColor.clear
        newWindow.isOpaque = false
        newWindow.ignoresMouseEvents = true
        newWindow.hasShadow = false
        
        // Fix for macOS window behavior - make sure it stays visible
        newWindow.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // Use flipped coordinates to match screen coordinates
        // Screen origin is top-left. NSView origin is bottom-left by default.
        // Our calculation uses top-left origin (from AX API and screen), and RectangleView is flipped (isFlipped = true), so it also expects top-left.
        // Therefore, we pass the calculated absolute x,y directly without further flipping.
        let rectangleForView = CGRect(x: x, y: y, width: width, height: height)
        print("[justDrawRectangle] Creating RectangleView with frame: \(screen.frame) and rectangleFrame: \(rectangleForView) (using direct top-left coords Y=\(y))")
        let customView = RectangleView(frame: screen.frame, rectangleFrame: rectangleForView)
        
        // Set the content view
        newWindow.contentView = customView
        
        // Show the window
        newWindow.orderFrontRegardless()
        
        // Store the reference
        self.windowRef = newWindow
        
        // Schedule cleanup after 2 seconds
        scheduleCleanup(delay: 2.0)
        
        // Log success
        print("{\"status\":\"drawn\", \"ts\":\\(Int(Date().timeIntervalSince1970 * 1000))}") // Keep original JSON output
        print("[justDrawRectangle] Window created and scheduled for cleanup.")
    }
    
    // Schedule cleanup with the ability to cancel it
    private func scheduleCleanup(delay: TimeInterval) {
        // Cancel any existing cleanup
        cancelScheduledCleanup()
        
        // Create a new cleanup task
        let task = DispatchWorkItem { [weak self] in
            print("[scheduleCleanup] Cleanup task executing.")
            self?.closeWindow()
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
    
    // Close the window safely
    private func closeWindow() {
        // Make sure we're on the main thread
        if !Thread.isMainThread {
            print("[closeWindow] Warning: Not on main thread. Dispatching asynchronously.")
            DispatchQueue.main.async {
                self.closeWindow()
            }
            return
        }
        
        // Check if we have a window reference *before* nilling it
        if let windowToClose = windowRef {
             print("[closeWindow] Preparing to close window.")
             // Set reference to nil FIRST to prevent concurrent close attempts
             self.windowRef = nil

             // Optional: Explicitly remove the content view before closing, might help cleanup
             windowToClose.contentView = nil
             print("[closeWindow] Closing window.")
             // Now close the window instance we captured
             windowToClose.close()
        } else {
             // print("[closeWindow] No window reference to close.")
        }
    }
    
    // Clean up everything
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
        // Cancel any scheduled cleanup
        cancelScheduledCleanup()
        
        // Close the window
        closeWindow()
    }
    
    // Public cleanup method
    func clearOverlays() {
        print("[clearOverlays] Public clear method called.")
        cleanupEverything()
    }
}

// Custom NSView subclass that draws a rectangle with no Core Animation
class RectangleView: NSView {
    private var rectangleFrame: CGRect
    
    init(frame: CGRect, rectangleFrame: CGRect) {
        self.rectangleFrame = rectangleFrame
        super.init(frame: frame)
        print("[RectangleView init] Initialized with frame: \(frame), rectangle: \(rectangleFrame)")
        // Make the view layer-backed for better rendering
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented") // Make explicit that coder init is not supported
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        print("[RectangleView draw] Drawing rectangleFrame: \(rectangleFrame) within dirtyRect: \(dirtyRect)")
        
        // Get the current graphics context
        guard let context = NSGraphicsContext.current?.cgContext else { 
            print("[RectangleView draw] Error: Failed to get graphics context.")
            return 
        }
        
        // Set up the rectangle fill color (semi-transparent green per PRD)
        context.setFillColor(NSColor.green.withAlphaComponent(0.3).cgColor)
        
        // Set up the stroke color and width
        context.setStrokeColor(NSColor.green.cgColor)
        context.setLineWidth(4.0)
        
        // Use bezier path for rounded corners
        let path = NSBezierPath(roundedRect: rectangleFrame, xRadius: 4, yRadius: 4)
        
        // Create shadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 2, height: -2)
        shadow.set()
        
        // Draw with path
        NSColor.green.withAlphaComponent(0.3).setFill()
        NSColor.green.setStroke()
        path.fill()
        path.stroke()
        print("[RectangleView draw] Finished drawing.")
    }
    
    // Ensure we use flipped coordinates - THIS IS CRITICAL for NSView drawing
    override var isFlipped: Bool {
        // print("[RectangleView] isFlipped called, returning true.") // Can be noisy, uncomment if needed
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