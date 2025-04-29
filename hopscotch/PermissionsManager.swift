//
//  PermissionsManager.swift
//  hopscotch
//
//  Created by Abhimanyu Yadav on 4/28/25.
//

import Foundation
import Cocoa
import ApplicationServices

class PermissionsManager: ObservableObject {
    @Published var accessibilityPermissionGranted = false
    @Published var screenRecordingPermissionGranted = false
    @Published var inputMonitoringPermissionGranted = false
    
    func checkAllPermissions() {
        checkAccessibilityPermission()
        checkScreenRecordingPermission()
        checkInputMonitoringPermission()
    }
    
    func checkAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityPermissionGranted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func checkScreenRecordingPermission() {
        screenRecordingPermissionGranted = CGPreflightScreenCaptureAccess()
    }
    
    func checkInputMonitoringPermission() {
        // There's no direct API to check input monitoring permission
        // Instead, we'll try to create an event tap and see if it succeeds
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue)
        
        if let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, _, _, _ in nil },
            userInfo: nil
        ) {
            inputMonitoringPermissionGranted = true
            CFRelease(eventTap)
        } else {
            inputMonitoringPermissionGranted = false
        }
    }
    
    func requestAccessibilityPermission() {
        // Requesting with prompt set to true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // After requesting, check again after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkAccessibilityPermission()
        }
    }
    
    func requestScreenRecordingPermission() {
        // Simply trying to capture screen will trigger the permission dialog
        CGRequestScreenCaptureAccess()
        
        // Check again after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.checkScreenRecordingPermission()
        }
    }
    
    func requestInputMonitoringPermission() {
        // Open System Preferences to the Input Monitoring section
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
        
        // Show notification to guide the user
        let notification = NSUserNotification()
        notification.title = "Input Monitoring Permission Required"
        notification.informativeText = "Please add this app to the list of allowed apps and enable it."
        NSUserNotificationCenter.default.deliver(notification)
    }
} 