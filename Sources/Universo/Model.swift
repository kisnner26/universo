import SwiftUI
import AppKit
import Observation

enum Palette {
    static let accent = Color(red: 0.16, green: 0.40, blue: 0.93)
    static let bgTop = Color(red: 0.07, green: 0.075, blue: 0.095)
    static let bgBottom = Color(red: 0.13, green: 0.135, blue: 0.16)
}

struct Camera {
    var cx: Double
    var cy: Double
    var scale: Double
}

struct Flight {
    var from: Camera
    var to: Camera
    var start: Double
    var duration: Double
}

enum ScopeChoice: String, CaseIterable, Identifiable {
    case all = "Todo"
    case galaxy = "Galaxia"
    case vicinity = "Vecindad"
    var id: String { rawValue }
}

@Observable
final class Model {
    var conciseExport = true
    var scopeChoice: ScopeChoice = .vicinity
    var toast: String?
    var baselineTokens = 1
    var universe: Universe?
    var loadError: String?
    var graphURL: URL
    var graphChosen = false
    var selected: Int?
    var hovered: Int?
    var activeGalaxy: Int?
    var query = ""
    var matchList: [Int] = []
    var matchSet: Set<Int> = []
    var edgeAmount = 0.6
    var rotate = true
    var base = Camera(cx: 0, cy: 0, scale: 0.3)
    var flight: Flight?
    var viewSize = CGSize(width: 1280, height: 820)
    var fitted = false
    var clockOffset = 0.0
    var pausedAt: Double?
    var backdrop: [Backdrop] = []

    static let insetLeft: Double = 312
    static let insetRight: Double = 352

    init() {
        let saved = UserDefaults.standard.string(forKey: "graphPath")
        graphURL = URL(fileURLWithPath: saved ?? NSHomeDirectory())
        var rng = SeededRNG(s: 7)
        backdrop = (0..<260).map { _ in
            Backdrop(x: rng.next(), y: rng.next(), depth: rng.next(), size: 0.6 + rng.next() * 1.4, phase: rng.next() * 6.283)
        }
        if saved != nil {
            graphChosen = true
            reload()
        }
    }

    // MARK: carga

    func reload() {
        load(url: graphURL)
    }

    func load(url: URL) {
        graphChosen = true
        do {
            let data = try Data(contentsOf: url)
            let raw = try JSONDecoder().decode(RawGraph.self, from: data)
            guard !raw.nodes.isEmpty else {
                universe = nil
                loadError = "El archivo no tiene nodos."
                return
            }
            let u = Universe(raw: raw)
            graphURL = url
            UserDefaults.standard.set(url.path, forKey: "graphPath")
            universe = u
            loadError = nil
            selected = nil
            hovered = nil
            activeGalaxy = nil
            flight = nil
                        baselineTokens = tokenEstimate(buildExport(.scope, scope: .all, concise: false, universe: u))
            updateQuery()
            fit(animated: false)
            fitted = true
        } catch {
            universe = nil
            loadError = error.localizedDescription
        }
    }

    func flash(_ text: String) {
        toast = text
        let current = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if self.toast == current { self.toast = nil }
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Elige el graph.json que genera graphify"
        panel.directoryURL = graphURL.deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { load(url: url) }
    }

    var rootFolder: URL {
        graphURL.deletingLastPathComponent().deletingLastPathComponent()
    }

    func fileURL(for path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let candidate = path.hasPrefix("/") ? URL(fileURLWithPath: path) : rootFolder.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    // MARK: tiempo y cámara

    func time(at now: Double) -> Double {
        if let p = pausedAt { return p - clockOffset }
        return now - clockOffset
    }

    func setRotation(_ on: Bool) {
        let now = Date().timeIntervalSinceReferenceDate
        if on, let p = pausedAt {
            clockOffset += now - p
            pausedAt = nil
        } else if !on, pausedAt == nil {
            pausedAt = now
        }
        rotate = on
    }

    func camera(at date: Date) -> Camera {
        guard let f = flight else { return base }
        let t = (date.timeIntervalSinceReferenceDate - f.start) / f.duration
        if t >= 1 { return f.to }
        let e = t * t * (3 - 2 * t)
        let s = exp(log(f.from.scale) * (1 - e) + log(f.to.scale) * e)
        return Camera(
            cx: f.from.cx + (f.to.cx - f.from.cx) * e,
            cy: f.from.cy + (f.to.cy - f.from.cy) * e,
            scale: s
        )
    }

    func settle() {
        guard flight != nil else { return }
        base = camera(at: Date())
        flight = nil
    }

    func fly(to cam: Camera, duration: Double = 0.9) {
        let now = Date()
        flight = Flight(
            from: camera(at: now),
            to: cam,
            start: now.timeIntervalSinceReferenceDate,
            duration: duration
        )
    }

    private func visibleOffset(rightPanel: Bool) -> Double {
        (Model.insetLeft - (rightPanel ? Model.insetRight : 0)) / 2
    }

    private func visibleSize(rightPanel: Bool) -> CGSize {
        CGSize(
            width: max(200, viewSize.width - Model.insetLeft - (rightPanel ? Model.insetRight : 0)),
            height: max(200, viewSize.height - 110)
        )
    }

    private func camera(centering p: CGPoint, scale: Double, rightPanel: Bool) -> Camera {
        Camera(
            cx: Double(p.x) - visibleOffset(rightPanel: rightPanel) / scale,
            cy: Double(p.y),
            scale: scale
        )
    }

    func fit(animated: Bool = true) {
        guard let u = universe else { return }
        let vs = visibleSize(rightPanel: false)
        let b = u.bounds
        let scale = max(0.05, min(vs.width / b.width, vs.height / (b.height * Double(u.tilt))) * 0.98)
        let cam = camera(centering: CGPoint(x: b.midX, y: b.midY), scale: scale, rightPanel: false)
        activeGalaxy = nil
        if animated {
            fly(to: cam, duration: 1.1)
        } else {
            base = cam
            flight = nil
        }
    }

    func setSize(_ s: CGSize) {
        viewSize = s
        if !fitted, universe != nil {
            fit(animated: false)
            fitted = true
        }
    }

    func flyToGalaxy(_ g: Int) {
        guard let u = universe else { return }
        let gal = u.galaxies[g]
        let vs = visibleSize(rightPanel: selected != nil)
        let scale = max(0.2, min(3.0, min(vs.width, vs.height) / (gal.radius * 2.8)))
        activeGalaxy = g
        fly(to: camera(centering: gal.center, scale: scale, rightPanel: selected != nil))
    }

    func select(_ i: Int, fly doFly: Bool) {
        guard let u = universe else { return }
        selected = i
        activeGalaxy = u.stars[i].galaxy
        guard doFly else { return }
        let now = Date()
        let cam = camera(at: now)
        let tEnd = time(at: now.timeIntervalSinceReferenceDate + 0.9)
        let p = u.position(i, t: tEnd)
        fly(to: camera(centering: p, scale: min(3.2, max(cam.scale, 1.5)), rightPanel: true))
    }

    func clearSelection() {
        selected = nil
        activeGalaxy = nil
    }

    // MARK: interacción

    func screenToWorld(_ p: CGPoint, cam: Camera) -> CGPoint {
        CGPoint(
            x: (p.x - viewSize.width / 2) / cam.scale + cam.cx,
            y: (p.y - viewSize.height / 2) / cam.scale + cam.cy
        )
    }

    func pan(dx: Double, dy: Double) {
        settle()
        base.cx -= dx / base.scale
        base.cy -= dy / base.scale
    }

    func zoom(by factor: Double, at p: CGPoint) {
        settle()
        let before = screenToWorld(p, cam: base)
        base.scale = min(8, max(0.04, base.scale * factor))
        base.cx = Double(before.x) - (Double(p.x) - viewSize.width / 2) / base.scale
        base.cy = Double(before.y) - (Double(p.y) - viewSize.height / 2) / base.scale
    }

    func hit(at p: CGPoint) -> Int? {
        guard let u = universe else { return nil }
        let now = Date()
        let cam = camera(at: now)
        let t = time(at: now.timeIntervalSinceReferenceDate)
        let grow = max(0.6, min(2.4, pow(cam.scale, 0.55)))
        var best: Int?
        var bestD = Double.infinity
        for i in u.stars.indices {
            let w = u.position(i, t: t)
            let sx = (Double(w.x) - cam.cx) * cam.scale + viewSize.width / 2
            let sy = (Double(w.y) - cam.cy) * cam.scale + viewSize.height / 2
            let d = hypot(sx - Double(p.x), sy - Double(p.y))
            let reach = max(9.0, Double(u.stars[i].size) * grow * 2.4)
            if d < reach, d < bestD {
                bestD = d
                best = i
            }
        }
        return best
    }

    func click(at p: CGPoint) {
        if let i = hit(at: p) {
            select(i, fly: false)
        } else {
            clearSelection()
        }
    }

    func hover(at p: CGPoint) {
        let h = hit(at: p)
        if h != hovered { hovered = h }
    }

    // MARK: búsqueda

    func updateQuery() {
        guard let u = universe else { return }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else {
            matchList = []
            matchSet = []
            return
        }
        let found = u.stars.indices.filter { i in
            let s = u.stars[i]
            return s.label.lowercased().contains(q)
                || s.file.lowercased().contains(q)
                || u.galaxies[s.galaxy].name.lowercased().contains(q)
        }
        matchSet = Set(found)
        matchList = found.sorted { u.stars[$0].degree > u.stars[$1].degree }
    }
}
