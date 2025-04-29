//
//  hopscotchApp.swift
//  hopscotch
//
//  Created by Abhimanyu Yadav on 4/28/25.
//

import SwiftUI

@main
struct hopscotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    private var permissionsManager = PermissionsManager()
    private var overlayController = OverlayController()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        checkPermissions()
        
        // Subscribe to mode changes from overlay controller
        observeModeChanges()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Overlay Assistant")
            updateMenuBarIcon(for: overlayController.currentMode)
        }
        
        setupMenu()
    }
    
    private func updateMenuBarIcon(for mode: AppMode) {
        if let button = statusItem.button {
            switch mode {
            case .observe:
                button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Observe Mode")
            case .act:
                button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Act Mode")
            }
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        let modeMenuItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeSubmenu = NSMenu()
        
        let observeItem = NSMenuItem(title: "Observe", action: #selector(toggleObserveMode), keyEquivalent: "o")
        observeItem.state = overlayController.currentMode == .observe ? .on : .off
        modeSubmenu.addItem(observeItem)
        
        let actItem = NSMenuItem(title: "Act", action: #selector(toggleActMode), keyEquivalent: "a")
        actItem.state = overlayController.currentMode == .act ? .on : .off
        modeSubmenu.addItem(actItem)
        
        modeMenuItem.submenu = modeSubmenu
        menu.addItem(modeMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let permissionsItem = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
        let permissionsSubmenu = NSMenu()
        
        let accessibilityItem = NSMenuItem(title: "Accessibility: Checking...", action: #selector(requestAccessibilityPermission), keyEquivalent: "")
        permissionsSubmenu.addItem(accessibilityItem)
        
        let screenRecordingItem = NSMenuItem(title: "Screen Recording: Checking...", action: #selector(requestScreenRecordingPermission), keyEquivalent: "")
        permissionsSubmenu.addItem(screenRecordingItem)
        
        let inputMonitoringItem = NSMenuItem(title: "Input Monitoring: Checking...", action: #selector(requestInputMonitoringPermission), keyEquivalent: "")
        permissionsSubmenu.addItem(inputMonitoringItem)
        
        permissionsItem.submenu = permissionsSubmenu
        menu.addItem(permissionsItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
        
        // Update permission statuses in menu
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updatePermissionStatuses()
        }
    }
    
    private func updatePermissionStatuses() {
        guard let menu = statusItem.menu,
              let permissionsMenu = menu.item(withTitle: "Permissions")?.submenu else { return }
        
        if let accessibilityItem = permissionsMenu.item(withTitle: permissionsMenu.items[0].title) {
            accessibilityItem.title = "Accessibility: \(permissionsManager.accessibilityPermissionGranted ? "Granted" : "Not Granted")"
        }
        
        if let screenRecordingItem = permissionsMenu.item(withTitle: permissionsMenu.items[1].title) {
            screenRecordingItem.title = "Screen Recording: \(permissionsManager.screenRecordingPermissionGranted ? "Granted" : "Not Granted")"
        }
        
        if let inputMonitoringItem = permissionsMenu.item(withTitle: permissionsMenu.items[2].title) {
            inputMonitoringItem.title = "Input Monitoring: \(permissionsManager.inputMonitoringPermissionGranted ? "Granted" : "Not Granted")"
        }
    }
    
    private func checkPermissions() {
        permissionsManager.checkAllPermissions()
    }
    
    private func observeModeChanges() {
        // In a real app, we would use Combine or other observation methods
        // For now, we'll just update periodically
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.updateMenuBarIcon(for: self.overlayController.currentMode)
            self.updateModeMenuItems()
        }
    }
    
    @objc private func toggleObserveMode() {
        overlayController.setMode(mode: .observe)
        updateMenuBarIcon(for: .observe)
        updateModeMenuItems()
    }
    
    @objc private func toggleActMode() {
        overlayController.setMode(mode: .act)
        updateMenuBarIcon(for: .act)
        updateModeMenuItems()
    }
    
    private func updateModeMenuItems() {
        guard let menu = statusItem.menu,
              let modeMenu = menu.item(withTitle: "Mode")?.submenu else { return }
        
        if let observeItem = modeMenu.item(withTitle: "Observe") {
            observeItem.state = overlayController.currentMode == .observe ? .on : .off
        }
        
        if let actItem = modeMenu.item(withTitle: "Act") {
            actItem.state = overlayController.currentMode == .act ? .on : .off
        }
    }
    
    @objc private func requestAccessibilityPermission() {
        permissionsManager.requestAccessibilityPermission()
    }
    
    @objc private func requestScreenRecordingPermission() {
        permissionsManager.requestScreenRecordingPermission()
    }
    
    @objc private func requestInputMonitoringPermission() {
        permissionsManager.requestInputMonitoringPermission()
    }
}

enum AppMode {
    case observe
    case act
}
