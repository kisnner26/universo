import AppKit

enum ScopeKind {
    case all
    case galaxy(Int)
    case vicinity(Int)
}

enum ExportKind {
    case scope
    case summary
    case session
}

func tokenEstimate(_ s: String) -> Int {
    max(1, s.count / 4)
}

func formatTokens(_ n: Int) -> String {
    n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
}

extension Model {
    var effectiveScope: ScopeKind {
        guard let u = universe else { return .all }
        switch scopeChoice {
        case .all:
            return .all
        case .galaxy:
            if let g = activeGalaxy ?? selected.map({ u.stars[$0].galaxy }) { return .galaxy(g) }
            return .all
        case .vicinity:
            if let s = selected { return .vicinity(s) }
            if let g = activeGalaxy { return .galaxy(g) }
            return .all
        }
    }

    func scopeIndices(_ u: Universe, _ kind: ScopeKind) -> [Int] {
        switch kind {
        case .all:
            return Array(u.stars.indices)
        case .galaxy(let g):
            return u.galaxies[g].members
        case .vicinity(let s):
            var seen: Set<Int> = [s]
            var frontier = [s]
            for _ in 0..<2 {
                var next: [Int] = []
                for i in frontier {
                    for n in u.neighbors(of: i) where seen.insert(n.star).inserted { next.append(n.star) }
                }
                frontier = next
            }
            return Array(seen)
        }
    }

    func scopeTitle(_ kind: ScopeKind) -> String {
        guard let u = universe else { return "" }
        switch kind {
        case .all: return "Todo el grafo"
        case .galaxy(let g): return "Galaxia \u{201C}\(u.galaxies[g].name)\u{201D}"
        case .vicinity(let s): return "Vecindad de \u{201C}\(u.stars[s].label)\u{201D}"
        }
    }

    var scopeIsFallback: Bool {
        switch (scopeChoice, effectiveScope) {
        case (.galaxy, .all), (.vicinity, .all), (.vicinity, .galaxy): return true
        default: return false
        }
    }

    // Prefijo estable: no depende del alcance, va siempre primero para que el caché de prompts lo reutilice.
    func stablePrefix(_ u: Universe, concise: Bool) -> String {
        let order = u.galaxies.indices.sorted { u.galaxies[$0].members.count > u.galaxies[$1].members.count }
        if concise {
            let gs = order.map { "\(u.galaxies[$0].name)(\(u.galaxies[$0].members.count))" }.joined(separator: " · ")
            return """
            # Universo
            \(u.stars.count) nodos · \(u.links.count) conexiones · \(u.galaxies.count) galaxias (graphify). Grafo: `\(graphURL.path)`. Consulta `/graphify query` antes de leer archivos.
            Galaxias: \(gs)

            """
        }
        var s = "# Universo: mapa del proyecto\n\n"
        s += "Grafo `\(graphURL.path)` con \(u.stars.count) nodos, \(u.links.count) conexiones y \(u.galaxies.count) galaxias, generado con graphify. "
        s += "Antes de leer archivos del repositorio, consulta el grafo con `/graphify query \"...\"`.\n\n## Galaxias\n"
        for g in order { s += "- \(u.galaxies[g].name) (\(u.galaxies[g].members.count) nodos)\n" }
        return s + "\n"
    }

    func scopeBody(_ u: Universe, _ kind: ScopeKind, concise: Bool) -> String {
        let idx = scopeIndices(u, kind).sorted {
            u.stars[$0].degree != u.stars[$1].degree ? u.stars[$0].degree > u.stars[$1].degree : u.stars[$0].label < u.stars[$1].label
        }
        let inScope = Set(idx)
        var edgeLines: [String] = []
        var seen = Set<String>()
        for l in u.links where inScope.contains(l.a) && inScope.contains(l.b) {
            let rel = l.relation.isEmpty ? "relacionado" : l.relation.replacingOccurrences(of: "_", with: " ")
            let flag = l.confidence == "EXTRACTED" ? "" : " [\(l.confidence.lowercased())]"
            let line = concise
                ? "\(u.stars[l.a].label) -\(rel)-> \(u.stars[l.b].label)\(flag)"
                : "- \(u.stars[l.a].label) → \(rel) → \(u.stars[l.b].label)\(flag)"
            if seen.insert(line).inserted { edgeLines.append(line) }
        }
        var s = ""
        if concise {
            s += "## \(scopeTitle(kind)) (\(idx.count) nodos)\n"
            for i in idx {
                let st = u.stars[i]
                s += "\(st.label)|\(st.type)|\(st.file.isEmpty ? "-" : st.file)\n"
            }
            if !edgeLines.isEmpty { s += "--\n" + edgeLines.joined(separator: "\n") + "\n" }
        } else {
            s += "## Alcance: \(scopeTitle(kind))\n\(idx.count) nodos y \(edgeLines.count) conexiones.\n\n### Nodos\n"
            for i in idx {
                let st = u.stars[i]
                var line = "- **\(st.label)** — \(st.type)"
                if !st.file.isEmpty { line += ", `\(st.file)\(st.loc.isEmpty ? "" : ":" + st.loc)`" }
                line += ", galaxia \(u.galaxies[st.galaxy].name)"
                s += line + "\n"
            }
            if !edgeLines.isEmpty { s += "\n### Conexiones\n" + edgeLines.joined(separator: "\n") + "\n" }
        }
        return s
    }

    func summaryBody(_ u: Universe, concise: Bool) -> String {
        let order = u.galaxies.indices.sorted { u.galaxies[$0].members.count > u.galaxies[$1].members.count }
        var s = concise ? "## Nodos clave por galaxia\n" : "## Nodos clave por galaxia\nLos tres más conectados de cada galaxia.\n\n"
        for g in order where u.galaxies[g].members.count > 1 {
            let top = u.galaxies[g].members.prefix(3).map { u.stars[$0].label }.joined(separator: "; ")
            s += concise ? "\(u.galaxies[g].name): \(top)\n" : "- **\(u.galaxies[g].name)**: \(top)\n"
        }
        return s
    }

    func buildExport(_ kind: ExportKind, scope: ScopeKind, concise: Bool, universe u: Universe) -> String {
        let prefix = stablePrefix(u, concise: concise)
        switch kind {
        case .scope:
            return prefix + scopeBody(u, scope, concise: concise)
        case .summary:
            return prefix + summaryBody(u, concise: concise)
        case .session:
            let intro = """
            Continúa el trabajo en este proyecto. Abajo está el contexto mínimo; no releas el repositorio entero.
            El estado cambia: verifica contra GitHub y ClickUp antes de actuar.


            """
            return intro + prefix + scopeBody(u, scope, concise: concise)
        }
    }

    func currentExportTokens(_ kind: ExportKind) -> Int {
        guard let u = universe else { return 0 }
        return tokenEstimate(buildExport(kind, scope: effectiveScope, concise: conciseExport, universe: u))
    }

    func copyExport(_ kind: ExportKind) {
        guard let u = universe else { return }
        let text = buildExport(kind, scope: effectiveScope, concise: conciseExport, universe: u)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let t = tokenEstimate(text)
        let saved = max(0, Int((1 - Double(t) / Double(baselineTokens)) * 100))
        let what: String
        switch kind {
        case .scope: what = "Contexto copiado"
        case .summary: what = "Resumen copiado"
        case .session: what = "Prompt de sesión nueva copiado"
        }
        flash("\(what) · ~\(formatTokens(t)) tokens · \(saved) % menos")
    }
}
