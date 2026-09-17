import SwiftUI
import SwiftData

/// Navigation shell: three-column split (folders → scripts → editor) with a
/// full-screen prompter overlay. Owned by scaffold — feature work happens in the
/// child views; do not change child-view signatures without tech-lead sign-off.
struct RootView: View {
    @Environment(AppState.self) private var appState
    @State private var sidebarSelection: SidebarItem? = .allScripts
    @State private var selectedScript: Script?

    var body: some View {
        Group {
            // Cross-platform full-screen presentation (fullScreenCover does not
            // exist on macOS). QA Bug H: presenting the prompter as an .overlay
            // kept the split view — and the editor's focused text view — ALIVE
            // underneath it, so key events (Space/Esc/typing) went to the
            // hidden TextEditor and silently mutated the script mid-prompt.
            // The prompter now REPLACES the window content: while it is up
            // there is no editor in the hierarchy to hold key focus or receive
            // leaked input. Sidebar/script selection live in this view's
            // @State, so the editor returns to the same script on exit.
            if let script = appState.prompterScript {
                // The prompter's own background and touch surface extend to
                // the screen edges; the text and control bar must NOT, or on
                // iPhone the first line runs under the status bar / Dynamic
                // Island and the bar sits on the home indicator.
                PrompterView(script: script)
            } else {
                splitView
            }
        }
        #if os(macOS)
        // QA Bug E: the window toolbar (+, search, word-count pill) floated
        // over the prompter text. Hide it while the prompter is presented so
        // the reading view is genuinely "full-screen, no bars" (SPEC F3).
        .toolbar(appState.prompterScript == nil ? .automatic : .hidden,
                 for: .windowToolbar)
        #endif
    }

    private var splitView: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebarSelection)
        } content: {
            ScriptListView(
                sidebarItem: sidebarSelection ?? .allScripts,
                selection: $selectedScript
            )
        } detail: {
            if let script = selectedScript {
                EditorView(script: script)
            } else {
                ContentUnavailableView("No Script Selected", systemImage: "doc.text")
            }
        }
    }
}
