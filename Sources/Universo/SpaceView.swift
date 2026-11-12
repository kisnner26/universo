import SwiftUI

struct SpaceView: View {
    @Bindable var model: Model
    @State private var lastDrag = CGSize.zero
    @State private var lastMagnification: CGFloat = 1

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                SpaceRenderer(model: model).render(&ctx, size: size, date: tl.date)
            }
        }
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { model.setSize(g.size) }
                    .onChange(of: g.size) { _, s in model.setSize(s) }
            }
        )
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { v in
                    model.pan(dx: v.translation.width - lastDrag.width, dy: v.translation.height - lastDrag.height)
                    lastDrag = v.translation
                }
                .onEnded { _ in lastDrag = .zero }
        )
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { v in
                    model.zoom(by: Double(v.magnification / lastMagnification), at: v.startLocation)
                    lastMagnification = v.magnification
                }
                .onEnded { _ in lastMagnification = 1 }
        )
        .simultaneousGesture(
            SpatialTapGesture().onEnded { v in model.click(at: v.location) }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): model.hover(at: p)
            case .ended: model.hovered = nil
            }
        }
    }
}

struct SpaceRenderer {
    let model: Model

    func render(_ ctx: inout GraphicsContext, size: CGSize, date: Date) {
        guard let u = model.universe else { return }
        let now = date.timeIntervalSinceReferenceDate
        let t = model.time(at: now)
        let cam = model.camera(at: date)
        let sc = cam.scale
        let W = size.width, H = size.height

        func S(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - cam.cx) * sc + W / 2, y: (p.y - cam.cy) * sc + H / 2)
        }
        func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        let onScreen = CGRect(x: -40, y: -40, width: W + 80, height: H + 80)

        // fondo de estrellas lejanas
        for b in model.backdrop {
            var x = b.x * W - cam.cx * sc * b.depth * 0.05
            var y = b.y * H - cam.cy * sc * b.depth * 0.05
            x = x.truncatingRemainder(dividingBy: W); if x < 0 { x += W }
            y = y.truncatingRemainder(dividingBy: H); if y < 0 { y += H }
            let a = (0.18 + 0.4 * b.depth) * (0.65 + 0.35 * sin(now * 0.8 + b.phase))
            ctx.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: b.size, height: b.size)),
                with: .color(.white.opacity(a))
            )
        }

        let P = u.stars.indices.map { u.position($0, t: t) }
        let SP = P.map(S)

        let sel = model.selected
        var hot = Set<Int>()
        if let s = sel {
            hot.insert(s)
            for n in u.neighbors(of: s) { hot.insert(n.star) }
        }
        let hasQuery = !model.matchSet.isEmpty
        let focusGalaxy = model.activeGalaxy

        func dim(_ i: Int) -> Double {
            var d = 1.0
            if sel != nil, !hot.contains(i) { d = 0.26 }
            else if sel == nil, let g = focusGalaxy, u.stars[i].galaxy != g { d = 0.45 }
            if hasQuery, !model.matchSet.contains(i) { d = min(d, 0.18) }
            return d
        }

        // halos de galaxia
        for (gi, g) in u.galaxies.enumerated() where g.members.count > 1 {
            let c = S(g.center)
            let r = g.radius * sc * 1.45
            guard onScreen.insetBy(dx: -r, dy: -r).contains(c) else { continue }
            let strong = (focusGalaxy == gi) ? 1.5 : 1.0
            ctx.fill(
                circle(c, r),
                with: .radialGradient(
                    Gradient(colors: [
                        g.color.opacity(0.20 * strong),
                        g.color.opacity(0.07 * strong),
                        g.color.opacity(0)
                    ]),
                    center: c, startRadius: 0, endRadius: r
                )
            )
        }

        // aristas
        let amount = model.edgeAmount
        if amount > 0.01 {
            var intra = Path(), cross = Path(), hotPath = Path()
            for l in u.links {
                let pa = SP[l.a], pb = SP[l.b]
                let isHot = sel != nil && (l.a == sel || l.b == sel)
                if !isHot, !onScreen.contains(pa), !onScreen.contains(pb) { continue }
                if isHot {
                    hotPath.move(to: pa); hotPath.addLine(to: pb)
                } else if l.cross {
                    let mid = CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
                    let dx = pb.x - pa.x, dy = pb.y - pa.y
                    let ctl = CGPoint(x: mid.x - dy * 0.16, y: mid.y + dx * 0.16)
                    cross.move(to: pa); cross.addQuadCurve(to: pb, control: ctl)
                } else {
                    intra.move(to: pa); intra.addLine(to: pb)
                }
            }
            let k = sel == nil ? 1.0 : 0.45
            ctx.stroke(intra, with: .color(.white.opacity(0.10 * amount * 1.6 * k)), lineWidth: 0.6)
            ctx.stroke(cross, with: .color(.white.opacity(0.16 * amount * 1.6 * k)), lineWidth: 0.6)
            ctx.stroke(hotPath, with: .color(Palette.accent.opacity(0.95)), lineWidth: 1.3)
        } else if let s = sel {
            var hotPath = Path()
            for n in u.neighbors(of: s) {
                hotPath.move(to: SP[s]); hotPath.addLine(to: SP[n.star])
            }
            ctx.stroke(hotPath, with: .color(Palette.accent.opacity(0.95)), lineWidth: 1.3)
        }

        // estrellas
        let grow = max(0.6, min(2.4, pow(sc, 0.55)))
        for i in u.stars.indices {
            let p = SP[i]
            guard onScreen.contains(p) else { continue }
            let s = u.stars[i]
            let color = u.galaxies[s.galaxy].color
            let a = 0.68 + 0.32 * sin(now * 1.4 + s.phase)
            let d = dim(i)
            let r = s.size * grow
            ctx.fill(circle(p, r * 3.2), with: .color(color.opacity(0.10 * a * d)))
            ctx.fill(circle(p, r * 1.9), with: .color(color.opacity(0.22 * a * d)))
            switch s.type {
            case "concept", "rationale":
                ctx.stroke(circle(p, r), with: .color(color.opacity(0.95 * d)), lineWidth: max(1, r * 0.35))
            case "document", "image":
                let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(roundedRect: rect, cornerRadius: r * 0.3), with: .color(color.opacity(0.95 * d)))
            default:
                ctx.fill(circle(p, r), with: .color(color.opacity(0.95 * d)))
                ctx.fill(circle(p, r * 0.45), with: .color(.white.opacity(0.9 * a * d)))
            }
        }

        // anillos de selección
        if let s = sel {
            let p = SP[s]
            let pulse = 1 + 0.12 * sin(now * 3)
            let r = (u.stars[s].size * grow + 6) * pulse
            ctx.stroke(circle(p, r), with: .color(.white.opacity(0.95)), lineWidth: 1.6)
            for n in u.neighbors(of: s) {
                let q = SP[n.star]
                ctx.stroke(circle(q, u.stars[n.star].size * grow + 4), with: .color(Palette.accent), lineWidth: 1.2)
            }
        }
        if let h = model.hovered, h != sel {
            ctx.stroke(circle(SP[h], u.stars[h].size * grow + 5), with: .color(.white.opacity(0.8)), lineWidth: 1.2)
        }

        // etiquetas de galaxia
        let galaxyFade = min(1, max(0, (1.5 - sc) / 0.6))
        var galaxyTaken: [CGRect] = []
        if galaxyFade > 0 {
            let order = u.galaxies.indices.sorted {
                if $0 == focusGalaxy { return true }
                if $1 == focusGalaxy { return false }
                return u.galaxies[$0].members.count > u.galaxies[$1].members.count
            }
            for gi in order {
                let g = u.galaxies[gi]
                if g.members.count < 6 && sc < 0.55 { continue }
                let c = S(g.center)
                guard onScreen.contains(c) else { continue }
                let y = c.y - g.radius * sc * 0.82 * Double(u.tilt) - 10
                let w = Double(g.name.count) * 7.0 + 10
                let rect = CGRect(x: c.x - w / 2, y: y - 18, width: w, height: 18)
                if gi != focusGalaxy, galaxyTaken.contains(where: { $0.intersects(rect) }) { continue }
                galaxyTaken.append(rect)
                var op = galaxyFade * 0.9
                if let f = focusGalaxy, f != gi { op *= 0.5 }
                if sel != nil { op *= 0.5 }
                let txt = ctx.resolve(
                    Text(g.name).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.white.opacity(op))
                )
                ctx.draw(txt, at: CGPoint(x: c.x, y: y), anchor: .bottom)
            }
        }

        // etiquetas de estrellas
        var candidates: [(idx: Int, prio: Int)] = []
        if let s = sel {
            candidates.append((s, 0))
            let ns = u.neighbors(of: s)
            if ns.count <= 16 { for n in ns { candidates.append((n.star, 1)) } }
        }
        if let h = model.hovered { candidates.append((h, 0)) }
        for i in model.matchList.prefix(24) { candidates.append((i, 2)) }
        let thr = sc > 2.2 ? 0 : sc > 1.5 ? 2 : sc > 1.0 ? 4 : 99
        if thr < 99 {
            for i in u.stars.indices where u.stars[i].degree >= thr && onScreen.contains(SP[i]) {
                candidates.append((i, 3))
            }
        }
        candidates.sort { $0.prio < $1.prio }
        var taken: [CGRect] = []
        var seen = Set<Int>()
        for c in candidates.prefix(140) {
            guard seen.insert(c.idx).inserted else { continue }
            let p = SP[c.idx]
            guard onScreen.contains(p) else { continue }
            let s = u.stars[c.idx]
            let label = s.label.count > 34 ? String(s.label.prefix(33)) + "…" : s.label
            let r = s.size * grow
            let rect = CGRect(x: p.x + r + 4, y: p.y - 8, width: Double(label.count) * 5.9 + 6, height: 16)
            if c.prio >= 2, taken.contains(where: { $0.intersects(rect) }) { continue }
            taken.append(rect)
            let strong = c.prio <= 1
            let txt = ctx.resolve(
                Text(label)
                    .font(.system(size: 10.5, weight: strong ? .semibold : .medium))
                    .foregroundStyle(Color.white.opacity(strong ? 0.95 : 0.7 * dim(c.idx) + 0.1))
            )
            ctx.draw(txt, at: CGPoint(x: p.x + r + 5, y: p.y), anchor: .leading)
        }
    }
}
