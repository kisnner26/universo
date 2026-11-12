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

        for n in raw.nodes {
            let c = n.community ?? -1
            if gmap[c] == nil {
                gmap[c] = gnames.count
                gnames.append(n.community_name ?? "Sin galaxia")
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
            let hue = (Double(i) * 0.61803398875).truncatingRemainder(dividingBy: 1)
            return Galaxy(
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
