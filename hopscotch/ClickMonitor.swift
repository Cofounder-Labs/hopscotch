//
//  ClickMonitor.swift
//  hopscotch
//
//  Created by Abhimanyu Yadav on 4/28/25.
//

import Foundation
import Cocoa
import UserNotifications

class ClickMonitor: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Regions to monitor
    private var monitoredRegions: [String: NSRect] = [:]
    
    // Throttling
    private var lastClickTimestamp: Date = Date.distantPast
    private let throttleInterval: TimeInterval = 0.3 // 300ms throttle
    
    // Static callback function for the event tap
    private static let eventCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo = userInfo else {
            return Unmanaged.passUnretained(event)
        }
        
        let monitor = Unmanaged<ClickMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        
        if type == .leftMouseDown {
            monitor.handleMouseClick(event)
        }
        return Unmanaged.passUnretained(event)
    }
    
    // Start monitoring for clicks
    func startMonitoring() {
        // Ensure previous tap is stopped if restarting
        stopMonitoring()
        print("[ClickMonitor] Attempting to start monitoring and create event tap...")

        // Create an event tap to monitor mouse clicks
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue)
        
        // Create a pointer to self that we can pass to the C callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: ClickMonitor.eventCallback,
            userInfo: selfPtr
        )
        
        if let eventTap = eventTap {
            // --- Tap Creation Succeeded ---
            print("[ClickMonitor] SUCCESS: CGEvent.tapCreate succeeded.")
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let runLoopSource = runLoopSource {
                 CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
                 CGEvent.tapEnable(tap: eventTap, enable: true)
                 print("[ClickMonitor] Event tap enabled and added to run loop.")
            } else {
                 print("[ClickMonitor] ERROR: Failed to create run loop source even though tap was created.")
                 // Clean up tap if source creation failed
                 CFMachPortInvalidate(eventTap)
                 self.eventTap = nil
            }
        } else {
            // --- Tap Creation Failed ---
            print("[ClickMonitor] ERROR: CGEvent.tapCreate failed. This likely means Input Monitoring permission is missing or denied.")
            print("[ClickMonitor] Please check System Settings > Privacy & Security > Input Monitoring.")
            // Optionally show notification (already present)
            showInputMonitoringNotification()
        }
    }
    
    // Show a notification for Input Monitoring permission
    private func showInputMonitoringNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, error in
            if granted {
                let content = UNMutableNotificationContent()
                content.title = "Input Monitoring Permission Required"
                content.body = "Unable to monitor mouse clicks. Please check that Input Monitoring permission is granted."
                
                let request = UNNotificationRequest(identifier: "clickMonitor", content: content, trigger: nil)
                center.add(request) { error in
                    if let error = error {
                        print("Error showing notification: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    // Stop monitoring for clicks
    func stopMonitoring() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
    }
    
    // Add a region to monitor
    func addMonitoredRegion(id: String, rect: NSRect) {
        monitoredRegions[id] = rect
    }
    
    // Remove a monitored region
    func removeMonitoredRegion(id: String) {
        monitoredRegions.removeValue(forKey: id)
    }
    
    // Clear all monitored regions
    func clearMonitoredRegions() {
        monitoredRegions.removeAll()
    }
    
    // Handle mouse click events
    func handleMouseClick(_ event: CGEvent) {
        let clickLocation = event.location // Top-left origin screen coordinates
        
        // Check if the click is within throttling interval
        let now = Date()
        if now.timeIntervalSince(lastClickTimestamp) < throttleInterval {
            // print("[ClickMonitor] Click throttled") // Optional debug log
            return
        }
        lastClickTimestamp = now
        print("[ClickMonitor] Handling click at screen coordinates: \(clickLocation)")
        
        // // Convert Quartz coordinates to Cocoa coordinates - REMOVED as both event and regions use top-left origin
        // let clickLocationCocoa = convertQuartzCoordinatesToCocoa(clickLocation)
        
        // Check if click (using top-left origin) is inside any monitored region (also top-left origin)
        var foundRegion = false
        for (regionId, rect) in monitoredRegions {
             print("[ClickMonitor]   Checking against region ID \(regionId): \(rect)")
            if rect.contains(clickLocation) { // Use clickLocation directly
                print("[ClickMonitor]   Click IS inside region ID \(regionId)")
                reportClickInRegion(regionId: regionId)
                foundRegion = true
                break // Stop checking once found
            }
        }
        if !foundRegion {
             print("[ClickMonitor] Click was outside all monitored regions.")
        }
    }
    
    // Convert Quartz coordinates to Cocoa coordinates
    private func convertQuartzCoordinatesToCocoa(_ point: CGPoint) -> NSPoint {
        // Quartz has origin at top-left, Cocoa has origin at bottom-left
        // THIS FUNCTION IS LIKELY INCORRECT FOR THIS USE CASE AND IS NO LONGER CALLED
        guard let mainScreen = NSScreen.main else {
            return NSPoint(x: point.x, y: point.y)
        }
        
        let screenHeight = mainScreen.frame.height
        return NSPoint(x: point.x, y: screenHeight - point.y)
    }
    
    // Report click in a region
    private func reportClickInRegion(regionId: String) {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let clickEvent = "{\"event\":\"click-inside\", \"rectId\":\"\(regionId)\", \"ts\":\(timestamp)}"
        print(clickEvent) // Output to stdout for CLI capture
    }
} 