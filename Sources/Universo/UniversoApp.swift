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

                VStack {
                    Spacer()
                    BottomBar(model: model)
                        .padding(.bottom, 18)
                        .padding(.leading, CGFloat(Model.insetLeft) - 12)
                        .padding(.trailing, model.selected != nil ? CGFloat(Model.insetRight) - 12 : 0)
                }
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
        .onAppear { installScrollMonitor() }
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
