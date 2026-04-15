import Cocoa
import IOKit.ps
import ServiceManagement
import SwiftUI

// MARK: - Design Tokens

private enum DS {
    static let bg      = Color(red: 0.98, green: 0.98, blue: 0.99)
    static let surface = Color(red: 0.93, green: 0.93, blue: 0.95)
    static let primary   = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let secondary = Color(red: 0.56, green: 0.56, blue: 0.60)
    static let accent    = Color(red: 1.0,  green: 0.39, blue: 0.33)
    static let divider   = Color.black.opacity(0.07)
    static let width: CGFloat = 280
    static let hPad:  CGFloat = 16
}

// MARK: - Hover Row

struct HoverRow<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.hPad)
                .padding(.vertical, 10)
                .background(hovering ? DS.surface : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Timer Tiers

private enum TimerTier: Equatable {
    case slow    // > 30% or charging → 3600 s
    case medium  // 10–30%            → 1800 s
    case fast    // ≤ 10%             →  300 s

    var interval: TimeInterval {
        switch self {
        case .slow:   return 3600
        case .medium: return 1800
        case .fast:   return 300
        }
    }
}

// MARK: - Alert Overlay

final class AlertOverlayController {
    private var panel: NSPanel?

    func show(level: Int) {
        guard panel == nil else { return }

        let view = AlertView(level: level)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 280)

        let p = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .screenSaver
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.contentView = hosting
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(
                x: screen.frame.minX + (screen.frame.width  - hosting.frame.width)  / 2,
                y: screen.frame.minY + (screen.frame.height - hosting.frame.height) / 2
            ))
        }

        panel = p
        p.orderFrontRegardless()
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - Battery Monitor

final class BatteryMonitor: ObservableObject {
    @Published var batteryLevel: Int  = 100
    @Published var isCharging:   Bool = false
    @Published var isOnBattery:  Bool = false

    var threshold: Int = 5

    private var hasAlerted:  Bool            = false
    private var currentTier: TimerTier       = .slow
    private var timer:       Timer?
    private var powerSource: CFRunLoopSource?
    private let overlay = AlertOverlayController()

    init() {
        readBattery()
        scheduleTier(tierFor())
        registerPowerNotifications()
    }

    deinit {
        if let src = powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    // MARK: Power source notifications

    private func registerPowerNotifications() {
        let ctx = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue().readBattery()
        }, ctx)?.takeRetainedValue() else { return }

        powerSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
    }

    // MARK: Read

    func readBattery() {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        // Determine power source from the system level, not per-source state field
        let providerType = IOPSGetProvidingPowerSourceType(info)?.takeRetainedValue() as? String ?? ""
        isOnBattery = (providerType == (kIOPSBatteryPowerValue as String))

        for src in list {
            guard
                let desc = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue()
                               as? [String: Any],
                let type = desc[kIOPSTypeKey as String] as? String,
                type == (kIOPSInternalBatteryType as String)
            else { continue }

            batteryLevel = (desc[kIOPSCurrentCapacityKey as String] as? Int)  ?? batteryLevel
            isCharging   = (desc[kIOPSIsChargingKey       as String] as? Bool) ?? false
            break
        }

        checkAlertCondition()
        let newTier = tierFor()
        if newTier != currentTier { scheduleTier(newTier) }
    }

    // MARK: Alert logic

    private func checkAlertCondition() {
        if batteryLevel > threshold + 5 { hasAlerted = false }

        // Plugged in — dismiss overlay and reset so it fires again next time
        if !isOnBattery {
            hasAlerted = false
            DispatchQueue.main.async { [weak self] in self?.overlay.dismiss() }
            return
        }

        if batteryLevel <= threshold && !hasAlerted {
            hasAlerted = true
            let level = batteryLevel
            DispatchQueue.main.async { [weak self] in self?.overlay.show(level: level) }
        }
    }

    // MARK: Timer

    private func tierFor() -> TimerTier {
        if isCharging || batteryLevel > 30 { return .slow   }
        if batteryLevel >= 10              { return .medium  }
        return .fast
    }

    private func scheduleTier(_ tier: TimerTier) {
        timer?.invalidate()
        currentTier = tier
        timer = Timer.scheduledTimer(withTimeInterval: tier.interval, repeats: true) { [weak self] _ in
            self?.readBattery()
        }
    }

    var iconName: String {
        batteryLevel <= 10 ? "drop.halffull" : "drop.fill"
    }
}

// MARK: - Alert View

struct AlertView: View {
    let level: Int

    @State private var scale:   CGFloat = 0.88
    @State private var opacity: Double  = 0.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(DS.bg)
                .shadow(color: .black.opacity(0.14), radius: 30, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(DS.divider, lineWidth: 1)
                )

            VStack(spacing: 14) {
                Image(systemName: "drop")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(DS.accent)

                Text("\(level)%")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.primary)

                Text("Battery Low")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.secondary)

                Text("Plug in to continue")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.secondary.opacity(0.6))
                    .padding(.top, 2)
            }
            .padding(32)
        }
        .preferredColorScheme(.light)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                scale   = 1.0
                opacity = 1.0
            }
        }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    @EnvironmentObject var monitor: BatteryMonitor
    @AppStorage("threshold") private var threshold: Double = 5
    @State private var launchAtLogin = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            HStack(alignment: .center, spacing: 12) {
                Image(systemName: monitor.iconName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(monitor.batteryLevel <= 10 ? DS.accent : DS.primary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(monitor.batteryLevel)%")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.primary)
                    Text(monitor.isOnBattery ? "On Battery" : "Charging")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, DS.hPad)
            .padding(.vertical, 14)

            DS.divider.frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("ALERT THRESHOLD")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.secondary)
                        .kerning(0.4)
                    Spacer()
                    Text("\(Int(threshold))%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.accent)
                }
                Slider(value: $threshold, in: 1...10, step: 1)
                    .tint(DS.accent)
                    .onChange(of: threshold) { _, v in monitor.threshold = Int(v) }
            }
            .padding(.horizontal, DS.hPad)
            .padding(.vertical, 12)

            DS.divider.frame(height: 1)

            HoverRow(action: { launchAtLogin.toggle() }) {
                HStack {
                    Text("Launch at Login")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.primary)
                    Spacer()
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .scaleEffect(0.75)
                        .tint(DS.accent)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled { try SMAppService.mainApp.register()   }
                    else       { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin = !enabled
                }
            }

            DS.divider.frame(height: 1)

            HoverRow(action: { NSApp.terminate(nil) }) {
                Text("Quit Juice")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.primary)
            }
        }
        .frame(width: DS.width)
        .background(DS.bg)
        .preferredColorScheme(.light)
        .onAppear {
            monitor.threshold = Int(threshold)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// MARK: - App Entry Point

@main
struct JuiceApp: App {
    @StateObject private var monitor = BatteryMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(monitor)
        } label: {
            Image(systemName: monitor.iconName)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}
