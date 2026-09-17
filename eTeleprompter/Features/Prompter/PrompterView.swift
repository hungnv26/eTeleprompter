import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

/// Full-screen reading view (WP5): engine-driven scrolling text, mirror
/// transforms on the reading container ONLY, auto-hiding control overlay,
/// settings popover, keyboard Space/↑/↓/Esc.
///
/// Presented by RootView's overlay while `appState.prompterScript` is non-nil;
/// exits by setting it back to nil. Opens paused at the top (SPEC F2).
struct PrompterView: View {
    var script: Script

    @Environment(AppState.self) private var appState

    @State private var engine = PrompterEngine(clock: DisplayLinkClock())
    @State private var settingsStore = SettingsStore(fallback: Self.firstRunDefaults)

    /// iPhone gets a smaller first-run font; see ReadingSettings.phoneDefault.
    private static var firstRunDefaults: ReadingSettings {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? .phoneDefault : .default
        #else
        .default
        #endif
    }
    @State private var controlsVisible = true
    @State private var showSettings = false
    /// Mutated on every interaction WITHOUT invalidating the view (it is a
    /// class whose changes SwiftUI does not observe) — mouse-move events on
    /// macOS would otherwise re-evaluate the body continuously.
    @State private var interaction = InteractionTracker()

    /// SPEC F3: controls auto-hide after 3 s of inactivity during playback.
    private static let autoHideDelay: TimeInterval = 3
    private let autoHideTick = Timer.publish(every: 0.5, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                settingsStore.settings.backgroundColor.color
                    .ignoresSafeArea()

                // QA Bug B (dead touch): the prompter overlay's color/text are
                // pure SwiftUI drawing, so UIKit/AppKit hit-testing sent taps
                // to the hidden NavigationSplitView columns UNDERNEATH the
                // overlay (verified via hitTest: the script list's
                // UICollectionView received them) and the tap-to-reveal
                // gesture never fired. This empty platform view gives the
                // overlay a real hit-testable surface, so taps route to the
                // prompter and can never leak into the editor/list.
                //
                // QA Bug G: because this platform view WINS hit-testing over
                // the bare background, touches on it are consumed by UIKit and
                // never reach the ancestor SwiftUI `.onTapGesture` — so
                // tap-to-reveal was dead whenever the bar was hidden. The
                // reveal gesture therefore lives ON the interceptor itself as
                // a real platform gesture recognizer.
                #if os(macOS)
                // QA Bug H: the interceptor also owns an NSEvent local key
                // monitor (see TouchInterceptor) so Space/↑/↓/Esc are handled
                // deterministically while the prompter is up — hidden
                // `.keyboardShortcut` buttons and bare-key menu equivalents
                // proved unreliable on macOS (Space never fired under
                // HID-level key injection even with nothing else focused).
                TouchInterceptor(onTap: registerInteraction,
                                 onKeyDown: handleKeyDown)
                    .ignoresSafeArea()
                #else
                TouchInterceptor(onTap: registerInteraction)
                    .ignoresSafeArea()
                #endif

                readingContainer(size: geometry.size)

                #if os(iOS)
                keyboardShortcutButtons
                #endif

                // QA Bug G (part 2): the bar must NOT be shown by inserting it
                // with `if controlsVisible` + .transition — during playback the
                // engine invalidates this body every frame, and the per-frame
                // no-animation transactions kept restarting the insertion
                // transition from its inactive state, so the bar stayed at
                // ~opacity 0: invisible AND skipped by hit-testing (verified
                // live: body rendered with controlsVisible == true for 300+
                // frames while the screen showed no bar and taps at the bar's
                // location hit the interceptor). Auto-hide worked because a
                // REMOVED view is no longer rebuilt per frame. The bar is
                // therefore always in the hierarchy, and visibility is a
                // resting attribute of the body (opacity/offset), which
                // per-frame re-evaluation can only ever drive TOWARD the
                // correct value. .animation(value:) animates just the flips.
                PrompterControlsView(
                    engine: engine,
                    store: settingsStore,
                    showSettings: $showSettings,
                    onExit: exitPrompter
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .opacity(controlsVisible ? 1 : 0)
                .offset(y: controlsVisible ? 0 : 24)
                .allowsHitTesting(controlsVisible)
                .accessibilityHidden(!controlsVisible)
                .animation(.easeOut(duration: 0.2), value: controlsVisible)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            #if os(iOS)
            // Reading mode hides unnecessary UI (SPEC F3). On iPad this also
            // gives the text the full height it had before safe-area insets
            // were respected; on Dynamic Island phones the island inset stays.
            .statusBarHidden(true)
            #endif
        }
        .contentShape(Rectangle())
        .onTapGesture { registerInteraction() } // Tap anywhere reveals controls (iPad).
        #if os(macOS)
        .onContinuousHover { phase in // Mouse move reveals controls (Mac).
            if case .active = phase { registerInteraction() }
        }
        #endif
        .onReceive(autoHideTick) { _ in autoHideIfIdle() }
        .onChange(of: engine.state) { registerInteraction() }
        .onChange(of: engine.speed) {
            // Persist the target speed globally (SPEC F3) and keep the
            // readout visible when speed is changed via keys/menu.
            settingsStore.settings.speed = engine.speed
            registerInteraction()
        }
        .onChange(of: settingsStore.settings) { registerInteraction() }
        .onAppear { engine.speed = settingsStore.settings.speed }
        .onDisappear { engine.stop() }
        .focusedSceneValue(\.prompterEngine, engine)
    }

    // MARK: Reading container (the ONLY thing that gets mirrored)

    private func readingContainer(size: CGSize) -> some View {
        PrompterTextBlock(
            content: script.content,
            settings: settingsStore.settings,
            viewportWidth: size.width
        )
        .equatable() // Text is laid out once; scrolling is translation only.
        // QA Bug A: the viewport frame below proposes a FINITE height, which
        // makes Text truncate with an ellipsis after ~1.5 screens. fixedSize
        // re-proposes nil height so the block always lays out at its full
        // natural height inside the clipped viewport.
        .fixedSize(horizontal: false, vertical: true)
        // QA Bug B (no auto-stop): the WP5 preference-key measurement was
        // never delivered on iPadOS 26 (engine.contentHeight stayed 0, which
        // disables auto-stop, so playback scrolled forever into black).
        // onGeometryChange reports the laid-out height reliably.
        .onGeometryChange(for: Double.self) { proxy in
            proxy.size.height
        } action: { height in
            engine.contentHeight = height
        }
        .offset(y: -engine.offset)
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
        .mirrorTransforms(settingsStore.settings)
        .allowsHitTesting(false)
    }

    // MARK: Keyboard — iOS only (hidden buttons work from iOS 17.0;
    // .onKeyPress would need 17.4 — see team/PLAN.md and DECISIONS.md).
    //
    // QA Bug H: on macOS ALL prompter keys (Space/↑/↓/Esc) are handled by the
    // NSEvent local monitor in TouchInterceptor (see handleKeyDown) — hidden
    // `.keyboardShortcut` buttons proved unreliable there and are compiled
    // out, so each key has exactly ONE binding path per platform. The
    // Playback menu items (PrompterCommands) are kept for discoverability;
    // the monitor swallows handled keys before menu-equivalent matching, so
    // they cannot double-fire.

    #if os(iOS)
    private var keyboardShortcutButtons: some View {
        Group {
            // Esc exits (cancelAction == Escape).
            Button("Exit Prompter", action: exitPrompter)
                .keyboardShortcut(.cancelAction)
            Button("Play/Pause") { engine.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Faster") { engine.increaseSpeed() }
                .keyboardShortcut(.upArrow, modifiers: [])
            Button("Slower") { engine.decreaseSpeed() }
                .keyboardShortcut(.downArrow, modifiers: [])
        }
        .buttonStyle(.plain)
        .labelsHidden()
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
    #endif

    #if os(macOS)
    /// QA Bug H: authoritative macOS key handling for the prompter, driven by
    /// the TouchInterceptor's NSEvent local monitor. Returns true when the
    /// key was handled (the event is then swallowed, so it can neither reach
    /// a hidden shortcut button/menu equivalent — no double-fire — nor any
    /// other responder). Space via `.keyboardShortcut`/menu equivalents was
    /// unreliable under real HID key events, so the shortcuts live here.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              !showSettings // don't hijack keys while the settings popover is up
        else { return false }
        switch event.keyCode {
        case 49: // Space
            engine.togglePlayPause()
            return true
        case 126: // ↑
            engine.increaseSpeed()
            return true
        case 125: // ↓
            engine.decreaseSpeed()
            return true
        case 53: // Esc
            exitPrompter()
            return true
        default:
            return false
        }
    }
    #endif

    // MARK: Control-overlay visibility

    // Visibility flips are plain state writes; the .animation(value:) on the
    // control bar animates them (withAnimation-driven transitions proved
    // unreliable under the per-frame playback invalidation — see Bug G note).
    private func registerInteraction() {
        interaction.lastInteraction = .now
        if !controlsVisible {
            controlsVisible = true
        }
    }

    private func autoHideIfIdle() {
        guard engine.state == .playing,
              controlsVisible,
              !showSettings,
              Date.now.timeIntervalSince(interaction.lastInteraction) >= Self.autoHideDelay
        else { return }
        controlsVisible = false
    }

    // MARK: Exit

    private func exitPrompter() {
        engine.stop()
        appState.prompterScript = nil
    }
}

/// Reference-type timestamp holder so interaction tracking never triggers a
/// SwiftUI view invalidation (see `PrompterView.interaction`).
private final class InteractionTracker {
    var lastInteraction: Date = .now
}

/// Empty platform view giving the prompter overlay a REAL hit-testable
/// surface (see the QA Bug B comment in `PrompterView.body`). SwiftUI-drawn
/// pixels alone do not participate in UIKit/AppKit hit-testing, so without
/// this, interactions over the overlay would not route to the prompter.
///
/// Because this view consumes the touches it wins (QA Bug G), the
/// tap-anywhere-to-reveal gesture is attached HERE as a platform gesture
/// recognizer calling `onTap` — a SwiftUI `.onTapGesture` on an ancestor
/// never fires for touches that UIKit/AppKit delivers to a foreign view.
#if os(iOS)
private struct TouchInterceptor: UIViewRepresentable {
    var onTap: () -> Void

    final class Coordinator: NSObject {
        var onTap: () -> Void

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap() {
            onTap()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
    }
}
#elseif os(macOS)
private struct TouchInterceptor: NSViewRepresentable {
    var onTap: () -> Void
    /// Returns true when the key event was handled; the event is swallowed.
    var onKeyDown: (NSEvent) -> Bool

    final class Coordinator: NSObject {
        var onTap: () -> Void
        var onKeyDown: (NSEvent) -> Bool
        private var keyMonitor: Any?

        init(onTap: @escaping () -> Void,
             onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onTap = onTap
            self.onKeyDown = onKeyDown
        }

        @objc func handleTap() {
            onTap()
        }

        /// QA Bug H: an NSEvent LOCAL monitor sees key events before menu
        /// key-equivalent matching and before the responder chain, so the
        /// prompter's keys work no matter what has (or steals) key focus and
        /// for every injection path (physical keyboard, HID, AppleScript).
        /// Returning nil swallows handled keys, so they can never fall
        /// through to anything else. Lives only as long as the prompter's
        /// interceptor view (started in makeNSView, stopped in dismantle).
        func startKeyMonitor() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.onKeyDown(event) ? nil : event
            }
        }

        func stopKeyMonitor() {
            if let keyMonitor {
                NSEvent.removeMonitor(keyMonitor)
                self.keyMonitor = nil
            }
        }

        deinit {
            stopKeyMonitor()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onKeyDown: onKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let click = NSClickGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleTap))
        view.addGestureRecognizer(click)
        context.coordinator.startKeyMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopKeyMonitor()
    }
}
#endif
