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
            // Create a run loop source and add it to the current run loop
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            
            // Enable the event tap
            CGEvent.tapEnable(tap: eventTap, enable: true)
        } else {
            // Failed to create event tap, show notification
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
        let clickLocation = event.location
        
        // Check if the click is within throttling interval
        let now = Date()
        if now.timeIntervalSince(lastClickTimestamp) < throttleInterval {
            return
        }
        
        // Update throttle timestamp
        lastClickTimestamp = now
        
        // Convert Quartz coordinates to Cocoa coordinates
        let clickLocationCocoa = convertQuartzCoordinatesToCocoa(clickLocation)
        
        // Check if click is inside any monitored region
        for (regionId, rect) in monitoredRegions {
            if rect.contains(clickLocationCocoa) {
                reportClickInRegion(regionId: regionId)
                break
            }
        }
    }
    
    // Convert Quartz coordinates to Cocoa coordinates
    private func convertQuartzCoordinatesToCocoa(_ point: CGPoint) -> NSPoint {
        // Quartz has origin at top-left, Cocoa has origin at bottom-left
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