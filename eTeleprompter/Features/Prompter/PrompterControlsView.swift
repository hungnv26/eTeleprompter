import SwiftUI

/// Bottom control overlay (WP5): transport, speed slider + −/+ + numeric
/// readout, quick mirror/rotation toggles, settings popover, exit.
/// Never mirrored/rotated — it sits outside the reading container (SPEC F3).
struct PrompterControlsView: View {
    var engine: PrompterEngine
    @Bindable var store: SettingsStore
    @Binding var showSettings: Bool
    var onExit: () -> Void

    /// iPhone (compact width) cannot fit all ten controls in one row: on a
    /// 402 pt screen the single-row layout clipped Play/Stop off the left edge
    /// and rotation/settings/exit off the right, so the prompter could not be
    /// paused or exited at all. Compact width stacks the bar into two rows.
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .compact {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        transportControls
                        speedControls
                    }
                    HStack(spacing: 12) {
                        mirrorControls
                        Divider().frame(height: 28)
                        settingsAndExit
                    }
                }
            } else {
                HStack(spacing: 16) {
                    transportControls
                    speedControls
                    Spacer(minLength: 8)
                    mirrorControls
                    Divider().frame(height: 28)
                    settingsAndExit
                }
            }
        }
        .padding(.horizontal, sizeClass == .compact ? 14 : 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: 860)
    }

    // MARK: Transport

    private var transportControls: some View {
        HStack(spacing: 10) {
            Button {
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.state == .playing ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 40, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(engine.state == .playing ? "Pause" : "Play")

            Button {
                engine.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Stop")
        }
    }

    // MARK: Speed

    /// Slider is continuous across 10...300 and snaps to integers (SPEC F2).
    private var speedBinding: Binding<Double> {
        Binding(
            get: { engine.speed },
            set: { engine.speed = $0.rounded() }
        )
    }

    private var speedControls: some View {
        HStack(spacing: 10) {
            Button {
                engine.decreaseSpeed()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Slower")

            Slider(value: speedBinding, in: PrompterEngine.speedRange)
                .frame(minWidth: 90, maxWidth: 260)
                .accessibilityLabel("Speed")

            Button {
                engine.increaseSpeed()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Faster")

            // Numeric readout shows the TARGET speed (changes immediately,
            // while the actual rate ramps over 0.3 s — SPEC F2).
            VStack(spacing: 0) {
                Text("\(Int(engine.speed))")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("pts/s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 44)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Speed \(Int(engine.speed)) points per second")
        }
    }

    // MARK: Mirror / rotation quick toggles

    private var mirrorControls: some View {
        HStack(spacing: 6) {
            Toggle(isOn: $store.settings.mirrorHorizontal) {
                Image(systemName: "arrow.left.and.right")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Horizontal mirror")

            Toggle(isOn: $store.settings.flipVertical) {
                Image(systemName: "arrow.up.and.down")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Vertical flip")

            Menu {
                Picker("Rotation", selection: $store.settings.rotation) {
                    ForEach(RotationAngle.allCases, id: \.self) { angle in
                        Text("\(angle.rawValue)°").tag(angle)
                    }
                }
            } label: {
                Image(systemName: "rotate.right")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .fixedSize()
            .accessibilityLabel("Rotation")
        }
    }

    // MARK: Settings + exit

    private var settingsAndExit: some View {
        HStack(spacing: 6) {
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape.fill")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Reading settings")
            // QA Bug D: on iPadOS the popover presented invisibly (dimmed the
            // bar, rendered nothing). A sheet is the reliable presentation on
            // iOS; macOS keeps the anchored popover.
            #if os(iOS)
            .sheet(isPresented: $showSettings) {
                PrompterSettingsSheet(store: store)
            }
            #else
            .popover(isPresented: $showSettings, arrowEdge: .top) {
                PrompterSettingsSheet(store: store)
            }
            #endif

            Button(action: onExit) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Close prompter")
        }
    }
}
