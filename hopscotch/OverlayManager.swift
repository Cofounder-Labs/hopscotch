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
    private var overlayWindows: [NSWindow] = []
    private let ANNOTATION_TIMEOUT: TimeInterval = 2.0 // 2 seconds as per PRD
    
    // Act mode: Draw an annotation at the specified coordinates
    func drawAnnotation(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, targetBundleID: String, completion: @escaping (Bool) -> Void) {
        // First validate that we're in the correct app
        guard validateTargetApp(bundleID: targetBundleID) else {
            completion(false)
            return
        }
        
        // Clean up any existing overlays
        clearOverlays()
        
        // Create an overlay for each screen
        for screen in NSScreen.screens {
            let overlayWindow = createOverlayWindow(for: screen)
            let annotationView = createAnnotationView(x: x, y: y, width: width, height: height, on: screen)
            
            overlayWindow.contentView = NSHostingView(rootView: annotationView)
            overlayWindow.orderFrontRegardless()
            
            overlayWindows.append(overlayWindow)
        }
        
        // Schedule the annotation to dismiss after timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + ANNOTATION_TIMEOUT) { [weak self] in
            self?.clearOverlays()
        }
        
        // Report success
        completion(true)
        
        // Send JSON acknowledgment
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let acknowledgment = "{\"status\":\"drawn\", \"ts\":\(timestamp)}"
        print(acknowledgment) // This will go to stdout for the CLI to capture
    }
    
    // Clear all overlay windows
    func clearOverlays() {
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()
    }
    
    // Validate that the frontmost app matches the target bundle ID
    private func validateTargetApp(bundleID: String) -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return false
        }
        
        return frontmostApp.bundleIdentifier == bundleID
    }
    
    // Create a transparent overlay window for a screen
    private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        
        window.level = .screenSaver // As specified in PRD
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true // Click-through
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        
        return window
    }
    
    // Create the annotation view with specific coordinates
    private func createAnnotationView(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, on screen: NSScreen) -> some View {
        return AnnotationView(rect: CGRect(x: x, y: y, width: width, height: height))
    }
}

// SwiftUI view for the annotation
struct AnnotationView: View {
    var rect: CGRect
    
    var body: some View {
        ZStack {
            Color.clear
            
            // Annotation rectangle
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.green, lineWidth: 2)
                .background(Color.green.opacity(0.2))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
        }
        .edgesIgnoringSafeArea(.all)
    }
} 