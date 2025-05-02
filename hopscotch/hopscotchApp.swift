//
//  hopscotchApp.swift
//  hopscotch
//
//  Created by Abhimanyu Yadav on 4/28/25.
//

import SwiftUI

// Observable object to hold test result data
class TestResultData: ObservableObject {
    @Published var image: NSImage? = nil
    @Published var prompt: String = ""
    @Published var text: String = ""
}

@main
struct hopscotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Create an instance of the observable object
    @StateObject private var testResultData = TestResultData()
    
    var body: some Scene {
        WindowGroup {
            // Pass the environment object and the openWindow action
            ChatInterface(overlayController: appDelegate.overlayController)
                .environmentObject(testResultData) // Inject the data object
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.bottom)
        .commandsRemoved()

        // New WindowGroup scene for the test result
        WindowGroup(id: "llmTestResultWindow") { 
            // Read data from the environment object
            TestResultView(image: testResultData.image, prompt: testResultData.prompt, resultText: testResultData.text)
                 .environmentObject(testResultData) // Also provide it here if needed by subviews
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            PreferencesView(overlayController: appDelegate.overlayController)
                .frame(minWidth: 600, minHeight: 500)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem!
    private var permissionsManager = PermissionsManager()
    
    // Make overlay controller accessible to the main app
    lazy var overlayController: OverlayController = {
        let controller = OverlayController()
        return controller
    }()
    
    private var preferencesWindow: NSWindow?
    private var preferencesHostingController: NSHostingController<PreferencesView>?
    private var modeUpdateTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        checkPermissions()
        
        // Subscribe to mode changes - but set up the timer to be invalidated properly
        setupModeChangeObservation()
        
        // Don't show preferences window on launch - let the chat interface show instead
        // showPreferences()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up timers
        modeUpdateTimer?.invalidate()
        modeUpdateTimer = nil
        
        // Clean up any overlays
        overlayController.cleanupForTermination()
        
        // Close preferences window safely
        closePreferencesWindow()
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
        DispatchQueue.main.async {
            if let button = self.statusItem.button {
                switch mode {
                case .observe:
                    button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Observe Mode")
                case .act:
                    button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Act Mode")
                }
            }
        }
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        // Add preferences menu item
        menu.addItem(NSMenuItem(title: "Controls...", action: #selector(showPreferences), keyEquivalent: ","))
        
        menu.addItem(NSMenuItem.separator())
        
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
    
    @objc private func showPreferences() {
        DispatchQueue.main.async {
            // First close any existing window to prevent duplication
            self.closePreferencesWindow()
            
            // Create new preferences view with a clean controller reference
            let preferencesView = PreferencesView(overlayController: self.overlayController)
            let hostingController = NSHostingController(rootView: preferencesView)
            self.preferencesHostingController = hostingController
            
            // Create a new window
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: true
            )
            
            window.title = "Overlay Assistant Controls"
            window.contentViewController = hostingController
            window.center()
            window.setContentSize(NSSize(width: 600, height: 520))
            window.delegate = self
            
            self.preferencesWindow = window
            window.makeKeyAndOrderFront(nil)
            
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func closePreferencesWindow() {
        if let window = preferencesWindow {
            window.close()
        }
        preferencesWindow = nil
        preferencesHostingController = nil
    }
    
    private func updatePermissionStatuses() {
        DispatchQueue.main.async {
            guard let menu = self.statusItem.menu,
                  let permissionsMenu = menu.item(withTitle: "Permissions")?.submenu else { return }
            
            if let accessibilityItem = permissionsMenu.item(withTitle: permissionsMenu.items[0].title) {
                accessibilityItem.title = "Accessibility: \(self.permissionsManager.accessibilityPermissionGranted ? "Granted" : "Not Granted")"
            }
            
            if let screenRecordingItem = permissionsMenu.item(withTitle: permissionsMenu.items[1].title) {
                screenRecordingItem.title = "Screen Recording: \(self.permissionsManager.screenRecordingPermissionGranted ? "Granted" : "Not Granted")"
            }
            
            if let inputMonitoringItem = permissionsMenu.item(withTitle: permissionsMenu.items[2].title) {
                inputMonitoringItem.title = "Input Monitoring: \(self.permissionsManager.inputMonitoringPermissionGranted ? "Granted" : "Not Granted")"
            }
        }
    }
    
    private func checkPermissions() {
        permissionsManager.checkAllPermissions()
    }
    
    private func setupModeChangeObservation() {
        // Invalidate any existing timer first
        modeUpdateTimer?.invalidate()
        
        // Create a new timer with a weak reference
        modeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.updateMenuBarIcon(for: self.overlayController.currentMode)
                self.updateModeMenuItems()
            }
        }
    }
    
    @objc private func toggleObserveMode() {
        DispatchQueue.main.async {
            self.overlayController.setMode(mode: .observe)
            self.updateMenuBarIcon(for: .observe)
            self.updateModeMenuItems()
        }
    }
    
    @objc private func toggleActMode() {
        DispatchQueue.main.async {
            self.overlayController.setMode(mode: .act)
            self.updateMenuBarIcon(for: .act)
            self.updateModeMenuItems()
        }
    }
    
    private func updateModeMenuItems() {
        DispatchQueue.main.async {
            guard let menu = self.statusItem.menu,
                  let modeMenu = menu.item(withTitle: "Mode")?.submenu else { return }
            
            if let observeItem = modeMenu.item(withTitle: "Observe") {
                observeItem.state = self.overlayController.currentMode == .observe ? .on : .off
            }
            
            if let actItem = modeMenu.item(withTitle: "Act") {
                actItem.state = self.overlayController.currentMode == .act ? .on : .off
            }
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

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Safely handle window closing
        if let closingWindow = notification.object as? NSWindow, 
           closingWindow == preferencesWindow {
            // Only set references to nil after window is fully closed
            DispatchQueue.main.async {
                if self.preferencesWindow == closingWindow {
                    self.preferencesWindow = nil
                    self.preferencesHostingController = nil
                }
            }
        }
    }
}

enum AppMode {
    case observe
    case act
}
