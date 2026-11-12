import SwiftUI
import AppKit

struct RootView: View {
    @Bindable var model: Model
    @State private var monitor: Any?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Palette.bgTop, Palette.bgBottom],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Palette.accent.opacity(0.10), .clear],
                center: .init(x: 0.7, y: 0.25), startRadius: 0, endRadius: 700
            )

            if model.universe != nil {
                SpaceView(model: model)
            }

            if let u = model.universe {
                HStack(alignment: .top, spacing: 12) {
                    Sidebar(model: model)
                    Spacer(minLength: 0)
                    if let s = model.selected {
                        DetailCard(model: model, u: u, i: s)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(12)
                .animation(.smooth(duration: 0.3), value: model.selected)

                VStack(spacing: 10) {
                    ToolsBar(model: model)
                        .padding(.top, 14)
                    Spacer()
                    if let t = model.toast {
                        ToastView(text: t)
                    }
                    ContextCard(model: model)
                        .padding(.bottom, 18)
                }
                .padding(.leading, CGFloat(Model.insetLeft) - 12)
                .padding(.trailing, model.selected != nil ? CGFloat(Model.insetRight) - 12 : 0)
                .animation(.smooth(duration: 0.25), value: model.toast)
            } else {
                ErrorCard(model: model)
            }
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .frame(minWidth: 1040, minHeight: 660)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.load(url: url)
            return true
        }
        .onAppear {
            installScrollMonitor()
            applyLaunchArguments(model)
        }
        .onDisappear {
            if let m = monitor { NSEvent.removeMonitor(m) }
        }
    }

    private func installScrollMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            guard let w = e.window, let cv = w.contentView, model.universe != nil else { return e }
            let loc = e.locationInWindow
            let p = CGPoint(x: loc.x, y: cv.bounds.height - loc.y)
            if p.x < Model.insetLeft - 8 { return e }
            if model.selected != nil, p.x > cv.bounds.width - Model.insetRight + 8 { return e }
            if e.hasPreciseScrollingDeltas, !e.modifierFlags.contains(.option) {
                model.pan(dx: Double(e.scrollingDeltaX), dy: Double(e.scrollingDeltaY))
            } else {
                let k = e.hasPreciseScrollingDeltas ? 0.012 : 0.06
                model.zoom(by: exp(Double(e.scrollingDeltaY) * k), at: p)
            }
            return nil
        }
    }
}

@MainActor
func applyLaunchArguments(_ model: Model) {
    let args = CommandLine.arguments
    func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    if let g = value("--graph") {
        model.load(url: URL(fileURLWithPath: g), persist: false)
    }
    if let q = value("--select")?.lowercased(), let u = model.universe,
       let idx = u.stars.indices.first(where: { u.stars[$0].label.lowercased().contains(q) }) {
        model.select(idx, fly: false)
        model.debugFocus(idx)
    }
    if let s = value("--scope"), let c = ScopeChoice.allCases.first(where: { $0.rawValue.lowercased() == s.lowercased() }) {
        model.scopeChoice = c
    }
    if value("--noise") == "off" {
        model.hideNoise = false
        model.rebuild(animated: false)
    }
    if args.contains("--toast") { model.copyExport(.scope) }
    guard let out = value("--live") else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
        guard let w = NSApp.windows.first(where: { $0.isVisible }) else {
            print("live: sin ventana")
            exit(1)
        }
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else {
            print("live: CGWindowListCreateImage no disponible")
            exit(1)
        }
        let fn = unsafeBitCast(sym, to: Fn.self)
        // optionIncludingWindow = 1<<3, boundsIgnoreFraming = 1<<0
        guard let img = fn(.null, 1 << 3, UInt32(w.windowNumber), 1 << 0)?.takeRetainedValue() else {
            print("live: captura nula")
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: img)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
            print("live ok", out, img.width, img.height)
        }
        exit(0)
    }
}

@main
struct UniversoApp: App {
    @State private var model = Model()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1380, height: 880)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Abrir grafo…") { model.openPanel() }
                    .keyboardShortcut("o")
                Button("Recargar") { model.reload() }
                    .keyboardShortcut("r")
            }
        }
    }
}
