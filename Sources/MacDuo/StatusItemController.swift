import AppKit
import Combine
import SwiftUI

/// The menu bar item and the settings popover.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {

    /// Absent while the icon is hidden.
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let preferences: Preferences
    private let controller: LidController
    private var titleTimer: Timer?
    private var barWindowMoved: NSObjectProtocol?
    private var iconSubscription: AnyCancellable?

    init(controller: LidController, preferences: Preferences) {
        self.controller = controller
        self.preferences = preferences
        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let hostingController = NSHostingController(
            rootView: SettingsView(
                preferences: preferences,
                controller: controller,
                onQuit: { NSApp.terminate(nil) }
            )
        )
        // Without this the popover keeps its default height and clips the content.
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTitle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        titleTimer = timer
        setIconVisible(preferences.showsMenuBarIcon)
        // `@Published` sends the new value before the property holds it, so
        // the setting is taken from the value that arrives here.
        iconSubscription = preferences.$showsMenuBarIcon
            .removeDuplicates()
            .sink { [weak self] shows in
                self?.setIconVisible(shows)
            }
        watchBarWindow()
    }

    deinit {
        titleTimer?.invalidate()
        if let barWindowMoved {
            NotificationCenter.default.removeObserver(barWindowMoved)
        }
    }

    /// Puts the icon in the menu bar, or takes it out. The app keeps running
    /// either way, and `reveal()` is the way back.
    private func setIconVisible(_ visible: Bool) {
        guard visible else {
            guard let statusItem else { return }
            if popover.isShown { popover.performClose(nil) }
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            return
        }
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "laptopcomputer",
                accessibilityDescription: "Mac Duo"
            )
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        statusItem = item
        refreshTitle()
    }

    /// Brings a hidden icon back and opens the panel. Opening the app again
    /// while it runs lands here, which is the only way back to the settings.
    func reveal() {
        if !preferences.showsMenuBarIcon {
            preferences.showsMenuBarIcon = true
        }
        setIconVisible(true)
        guard let button = statusItem?.button, !popover.isShown else { return }
        NSApp.activate()
        anchor(to: button)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate()
            anchor(to: button)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Showing the angle changes the button width, and the status item window
    /// slides along the menu bar about a tenth of a second later. AppKit places
    /// the popover on the width change, before the slide, so it lands a whole
    /// button width away until the window has settled.
    private func watchBarWindow() {
        barWindowMoved = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, self.popover.isShown,
                      let button = self.statusItem?.button,
                      let moved = notification.object as? NSWindow,
                      moved === button.window else { return }
                // Re-showing an animating popover makes it flicker shut.
                let animates = self.popover.animates
                self.popover.animates = false
                self.anchor(to: button)
                self.popover.animates = animates
            }
        }
    }

    /// An empty rectangle means the button's own bounds.
    private func anchor(to button: NSStatusBarButton) {
        popover.show(relativeTo: .zero, of: button, preferredEdge: .minY)
    }

    private func refreshTitle() {
        guard let button = statusItem?.button else { return }
        if preferences.showsAngleInMenuBar {
            button.title = String(format: " %.0f°", controller.currentAngle)
        } else if !button.title.isEmpty {
            button.title = ""
        }
    }
}
