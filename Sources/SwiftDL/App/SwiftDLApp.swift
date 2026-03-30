import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Use the generated AppIcon.icns for the Dock icon
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }
    }
}

@main
struct SwiftDLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var downloadManager = DownloadManager()
    @State private var settingsManager = SettingsManager()
    @State private var libraryManager = LibraryManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(downloadManager)
                .environment(settingsManager)
                .environment(libraryManager)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 700, height: 620)
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button("Paste") {
                    if let string = NSPasteboard.general.string(forType: .string) {
                        NSApp.sendAction(#selector(NSText.insertText(_:)), to: nil, from: string)
                    }
                }
                .keyboardShortcut("v", modifiers: .command)
            }
            CommandGroup(after: .appSettings) {                // ⌘, is handled via the toolbar gear button in ContentView
            }
        }
    }
}
