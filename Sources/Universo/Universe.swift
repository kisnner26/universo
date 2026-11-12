import SwiftUI

struct RawGraph: Decodable {
    let nodes: [RawNode]
    let links: [RawLink]
}

struct RawNode: Decodable {
    let id: String
    let label: String?
    let community: Int?
    let community_name: String?
    let file_type: String?
    let source_file: String?
    let source_location: String?
}

struct RawLink: Decodable {
    let source: String
    let target: String
    let relation: String?
    let confidence: String?
}

struct Star {
    let key: String
    let label: String
    let galaxy: Int
    let type: String
    let file: String
    let loc: String
    var degree = 0
    var local = CGPoint.zero
    var phase = 0.0
    var size: CGFloat = 1.4
}

struct Galaxy {
    var community = -1
    var name: String
    var members: [Int]
    var center = CGPoint.zero
    var radius: CGFloat = 30
    var spin = 0.02
    var color: Color
}

struct Link {
    let a: Int
    let b: Int
    let relation: String
    let confidence: String
    let cross: Bool
}

struct Backdrop {
    let x: Double
    let y: Double
    let depth: Double
    let size: Double
    let phase: Double
}

struct SeededRNG {
    var s: UInt64
    mutating func next() -> Double {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

final class Universe {
    var stars: [Star] = []
    var galaxies: [Galaxy] = []
    var links: [Link] = []
    var adj: [[Int]] = []
    var bounds = CGRect.zero
    let tilt: CGFloat = 0.82

    init(raw: RawGraph) {
        var rng = SeededRNG(s: 42)
        var index: [String: Int] = [:]
        var gmap: [Int: Int] = [:]
        var gnames: [String] = []
        var gcomm: [Int] = []

        for n in raw.nodes {
            let c = n.community ?? -1
            if gmap[c] == nil {
                gmap[c] = gnames.count
                gnames.append(n.community_name ?? "Sin galaxia")
                gcomm.append(c)
            }
            index[n.id] = stars.count
            stars.append(Star(
                key: n.id,
                label: n.label ?? n.id,
                galaxy: gmap[c]!,
                type: n.file_type ?? "code",
                file: n.source_file ?? "",
                loc: n.source_location ?? "",
                phase: rng.next() * 6.283
            ))
        }

        adj = Array(repeating: [], count: stars.count)
        for l in raw.links {
            guard let a = index[l.source], let b = index[l.target], a != b else { continue }
            let li = links.count
            links.append(Link(
                a: a, b: b,
                relation: l.relation ?? "",
                confidence: l.confidence ?? "EXTRACTED",
                cross: stars[a].galaxy != stars[b].galaxy
            ))
            adj[a].append(li)
            adj[b].append(li)
            stars[a].degree += 1
            stars[b].degree += 1
        }

        for i in stars.indices {
            stars[i].size = min(6.5, 1.3 + 0.95 * CGFloat(stars[i].degree).squareRoot())
        }

        galaxies = gnames.enumerated().map { i, name in
            let hue = (Double(gcomm[i] + 3) * 0.61803398875).truncatingRemainder(dividingBy: 1)
            return Galaxy(
                community: gcomm[i],
                name: name,
                members: [],
                spin: 0.014 + 0.02 * rng.next(),
                color: Color(hue: hue, saturation: 0.52, brightness: 0.96)
            )
        }
        for i in stars.indices { galaxies[stars[i].galaxy].members.append(i) }

        for g in galaxies.indices {
            let m = galaxies[g].members.sorted {
                stars[$0].degree != stars[$1].degree
                    ? stars[$0].degree > stars[$1].degree
                    : stars[$0].label < stars[$1].label
            }
            galaxies[g].members = m
            var rmax: CGFloat = 0
            for (i, si) in m.enumerated() {
                if m.count == 1 {
                    stars[si].local = .zero
                    continue
                }
                let r = 11.0 * (Double(i) + 0.8).squareRoot() * (1 + (rng.next() - 0.5) * 0.18)
                let th = log(r + 1) * 2.2 + Double(i % 2) * Double.pi + (rng.next() - 0.5) * 0.32
                stars[si].local = CGPoint(x: r * cos(th), y: r * sin(th))
                rmax = max(rmax, CGFloat(r))
            }
            galaxies[g].radius = rmax + 26
        }

        layoutGalaxies(rng: &rng)
        computeBounds()
    }

    private func layoutGalaxies(rng: inout SeededRNG) {
        let G = galaxies.count
        guard G > 1 else { return }
        var weights: [Int: Int] = [:]
        for l in links where l.cross {
            let a = min(stars[l.a].galaxy, stars[l.b].galaxy)
            let b = max(stars[l.a].galaxy, stars[l.b].galaxy)
            weights[a * 1000 + b, default: 0] += 1
        }
        let order = galaxies.indices.sorted { galaxies[$0].members.count > galaxies[$1].members.count }
        var pos = [CGPoint](repeating: .zero, count: G)
        for (k, g) in order.enumerated() {
            let r = 150 * Double(k).squareRoot()
            let a = Double(k) * 2.39996
            pos[g] = CGPoint(x: r * cos(a), y: r * sin(a))
        }
        for iter in 0..<900 {
            var f = [CGPoint](repeating: .zero, count: G)
            for i in 0..<G {
                for j in (i + 1)..<G {
                    let dx = pos[j].x - pos[i].x
                    let dy = pos[j].y - pos[i].y
                    let dist = max(hypot(dx, dy), 1)
                    let ux = dx / dist, uy = dy / dist
                    let minD = galaxies[i].radius + galaxies[j].radius + 55
                    let w = weights[i * 1000 + j] ?? 0
                    var force: CGFloat = 0
                    if dist < minD {
                        force = -(minD - dist) * 0.35
                    } else if w > 0 {
                        let target = minD + 140 / CGFloat(1 + w)
                        force = (dist - target) * 0.02 * CGFloat(min(w, 6))
                    }
                    f[i].x += ux * force; f[i].y += uy * force
                    f[j].x -= ux * force; f[j].y -= uy * force
                }
                f[i].x -= pos[i].x * 0.002
                f[i].y -= pos[i].y * 0.002
            }
            let cool = 0.8 * pow(0.995, Double(iter))
            for i in 0..<G {
                pos[i].x += f[i].x * cool
                pos[i].y += f[i].y * cool
            }
        }
        for g in 0..<G { galaxies[g].center = pos[g] }
    }

    private func computeBounds() {
        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for g in galaxies {
            minX = min(minX, g.center.x - g.radius)
            maxX = max(maxX, g.center.x + g.radius)
            minY = min(minY, g.center.y - g.radius)
            maxY = max(maxY, g.center.y + g.radius)
        }
        bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func position(_ i: Int, t: Double) -> CGPoint {
        let s = stars[i]
        let g = galaxies[s.galaxy]
        let a = g.spin * t
        let c = cos(a), sn = sin(a)
        let x = Double(s.local.x) * c - Double(s.local.y) * sn
        let y = (Double(s.local.x) * sn + Double(s.local.y) * c) * Double(tilt)
        return CGPoint(x: g.center.x + x, y: g.center.y + y)
    }

    func neighbors(of i: Int) -> [(star: Int, link: Link)] {
        adj[i].map { li in
            let l = links[li]
            return (l.a == i ? l.b : l.a, l)
        }
    }
}
