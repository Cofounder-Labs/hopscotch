//
//  OverlayManager.swift
//  hopscotch
//
//  Created by Abhimanyu Yadav on 4/28/25.
//

import Foundation
import Cocoa
import SwiftUI

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
        // Make sure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.drawAnnotation(x: x, y: y, width: width, height: height, targetBundleID: targetBundleID,
                                  activateTargetApp: activateTargetApp, bypassFocusCheck: bypassFocusCheck, completion: completion)
            }
            return
        }
        
        // Clean up existing window and scheduled cleanups
        cleanupEverything()
        
        // Find the target application
        let targetApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == targetBundleID })
        
        // Check if we need to validate the target application
        if !bypassFocusCheck && !activateTargetApp {
            // Validate that the target app is frontmost
            guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
                  frontmostApp.bundleIdentifier == targetBundleID else {
                completion(false)
                return
            }
        }
        
        // Try activating app if requested
        if activateTargetApp, let targetApp = targetApp {
            // Find and activate the app
            targetApp.activate(options: .activateIgnoringOtherApps)
            
            // Wait a bit before drawing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.justDrawRectangle(x: x, y: y, width: width, height: height)
                completion(true)
            }
            return
        }
        
        // Just draw directly if not activating app or if bypassing focus check
        if bypassFocusCheck || targetApp != nil {
            justDrawRectangle(x: x, y: y, width: width, height: height)
            completion(true)
        } else {
            completion(false)
        }
    }
    
    // Absolute minimal, safest drawing function
    private func justDrawRectangle(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        // Sanity check for main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.justDrawRectangle(x: x, y: y, width: width, height: height)
            }
            return
        }
        
        // First close any existing window
        closeWindow()
        
        // Create a new window only if we have a valid screen
        guard let screen = NSScreen.main else {
            print("No main screen available")
            return
        }
        
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
        let customView = RectangleView(frame: screen.frame, rectangleFrame: CGRect(x: x, y: screen.frame.height - y - height, width: width, height: height))
        
        // Set the content view
        newWindow.contentView = customView
        
        // Show the window
        newWindow.orderFrontRegardless()
        
        // Store the reference
        self.windowRef = newWindow
        
        // Schedule cleanup after 2 seconds
        scheduleCleanup(delay: 2.0)
        
        // Log success
        print("{\"status\":\"drawn\", \"ts\":\(Int(Date().timeIntervalSince1970 * 1000))}")
    }
    
    // Schedule cleanup with the ability to cancel it
    private func scheduleCleanup(delay: TimeInterval) {
        // Cancel any existing cleanup
        cancelScheduledCleanup()
        
        // Create a new cleanup task
        let task = DispatchWorkItem { [weak self] in
            self?.closeWindow()
        }
        
        // Store the task so we can cancel it if needed
        self.cleanupTask = task
        
        // Schedule the task
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
    }
    
    // Cancel scheduled cleanup 
    private func cancelScheduledCleanup() {
        cleanupTask?.cancel()
        cleanupTask = nil
    }
    
    // Close the window safely
    private func closeWindow() {
        // Make sure we're on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.closeWindow()
            }
            return
        }
        
        // Close and release the window
        if let window = windowRef {
            window.close()
            windowRef = nil
        }
    }
    
    // Clean up everything
    private func cleanupEverything() {
        // Make sure we're on the main thread
        if !Thread.isMainThread {
            DispatchQueue.main.async {
                self.cleanupEverything()
            }
            return
        }
        
        // Cancel any scheduled cleanup
        cancelScheduledCleanup()
        
        // Close the window
        closeWindow()
    }
    
    // Public cleanup method
    func clearOverlays() {
        cleanupEverything()
    }
}

// Custom NSView subclass that draws a rectangle with no Core Animation
class RectangleView: NSView {
    private var rectangleFrame: CGRect
    
    init(frame: CGRect, rectangleFrame: CGRect) {
        self.rectangleFrame = rectangleFrame
        super.init(frame: frame)
        
        // Make the view layer-backed for better rendering
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        self.rectangleFrame = .zero
        super.init(coder: coder)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Get the current graphics context
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
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
    }
    
    // Ensure we use flipped coordinates
    override var isFlipped: Bool {
        return true
    }
}

// Simple overlay view that draws a rectangle
struct OverlayView: View {
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