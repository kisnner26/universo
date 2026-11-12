import SwiftUI
import AppKit

private let muted = Color.white.opacity(0.55)

struct Sidebar: View {
    @Bindable var model: Model
    @FocusState private var searchFocused: Bool

    var body: some View {
        guard let u = model.universe else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Universo")
                        .font(.system(size: 28, weight: .bold))
                    Text("\(u.stars.count) nodos · \(u.links.count) conexiones · \(u.galaxies.count) galaxias")
                        .font(.system(size: 12))
                        .foregroundStyle(muted)
                }
                .padding(.top, 34)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(muted)
                    TextField("Buscar nodo, galaxia o archivo", text: $model.query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onChange(of: model.query) { _, _ in model.updateQuery() }
                    if !model.query.isEmpty {
                        Button {
                            model.query = ""
                            model.updateQuery()
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)

                ScrollView {
                    LazyVStack(spacing: 3) {
                        if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
                            ForEach(galaxyOrder(u), id: \.self) { g in
                                GalaxyRow(model: model, u: u, g: g)
                            }
                        } else if model.matchList.isEmpty {
                            Text("Sin resultados.")
                                .font(.system(size: 13))
                                .foregroundStyle(muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        } else {
                            ForEach(model.matchList.prefix(80), id: \.self) { i in
                                StarRow(model: model, u: u, i: i)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)

                Button("") { searchFocused = true }
                    .keyboardShortcut("f")
                    .frame(width: 0, height: 0)
                    .opacity(0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
            .frame(width: 296)
            .frame(maxHeight: .infinity)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        )
    }

    private func galaxyOrder(_ u: Universe) -> [Int] {
        u.galaxies.indices.sorted { u.galaxies[$0].members.count > u.galaxies[$1].members.count }
    }
}

struct GalaxyRow: View {
    @Bindable var model: Model
    let u: Universe
    let g: Int

    var body: some View {
        let gal = u.galaxies[g]
        let active = model.activeGalaxy == g
        Button {
            model.selected = nil
            model.flyToGalaxy(g)
        } label: {
            HStack(spacing: 10) {
                Circle().fill(gal.color).frame(width: 9, height: 9)
                Text(gal.name)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(gal.members.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(active ? 0.12 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct StarRow: View {
    @Bindable var model: Model
    let u: Universe
    let i: Int

    var body: some View {
        let s = u.stars[i]
        Button {
            model.select(i, fly: true)
        } label: {
            HStack(spacing: 10) {
                Circle().fill(u.galaxies[s.galaxy].color).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.label).font(.system(size: 13)).lineLimit(1)
                    Text(u.galaxies[s.galaxy].name)
                        .font(.system(size: 11))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(model.selected == i ? 0.12 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct DetailCard: View {
    @Bindable var model: Model
    let u: Universe
    let i: Int

    private func typeName(_ t: String) -> String {
        switch t {
        case "code": return "Código"
        case "document": return "Documento"
        case "concept": return "Concepto"
        case "rationale": return "Razón de diseño"
        case "image": return "Imagen"
        default: return t.capitalized
        }
    }

    var body: some View {
        let s = u.stars[i]
        let gal = u.galaxies[s.galaxy]
        let ns = u.neighbors(of: i).sorted { u.stars[$0.star].degree > u.stars[$1.star].degree }

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(s.label)
                    .font(.system(size: 22, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    model.clearSelection()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }

            HStack(spacing: 8) {
                Chip(text: typeName(s.type), color: nil)
                Chip(text: gal.name, color: gal.color)
            }

            if !s.file.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.loc.isEmpty ? s.file : "\(s.file) · \(s.loc)")
                        .font(.system(size: 12))
                        .foregroundStyle(muted)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = model.fileURL(for: s.file) {
                        Button("Mostrar en Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                    }
                }
            }

            Text("Conexiones (\(ns.count))")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 4)

            if ns.isEmpty {
                Text("Este nodo no tiene conexiones en el grafo.")
                    .font(.system(size: 13))
                    .foregroundStyle(muted)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(ns.enumerated()), id: \.offset) { _, n in
                            Button {
                                model.select(n.star, fly: true)
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(u.galaxies[u.stars[n.star].galaxy].color)
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(u.stars[n.star].label)
                                            .font(.system(size: 13))
                                            .lineLimit(1)
                                        Text(relationText(n.link))
                                            .font(.system(size: 11))
                                            .foregroundStyle(muted)
                                    }
                                    Spacer(minLength: 4)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(18)
        .frame(width: 328)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private func relationText(_ l: Link) -> String {
        var r = relationLabel(l.relation)
        switch l.confidence {
        case "INFERRED": r += " · inferida"
        case "AMBIGUOUS": r += " · ambigua"
        default: break
        }
        return r
    }
}

struct Chip: View {
    let text: String
    let color: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let c = color { Circle().fill(c).frame(width: 7, height: 7) }
            Text(text).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }
}

struct ToolsBar: View {
    @Bindable var model: Model

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button("Ajustar vista") { model.fit() }
                    .buttonStyle(.glass)

                HStack(spacing: 10) {
                    Text("Conexiones")
                        .font(.system(size: 12))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                        .fixedSize()
                    Slider(value: $model.edgeAmount, in: 0...1)
                        .frame(width: 110)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .glassEffect(.regular, in: .capsule)

                Button(model.rotate ? "Pausar giro" : "Girar galaxias") {
                    model.setRotation(!model.rotate)
                }
                .buttonStyle(.glass)

                Button("Recargar") { model.reload() }
                    .buttonStyle(.glass)

                Button("Abrir grafo…") { model.openPanel() }
                    .buttonStyle(.glass)
            }
        }
    }
}

struct ToggleChip: View {
    let title: String
    let isOn: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(isOn ? Palette.accent : Color.white.opacity(0.25))
                    .frame(width: 8, height: 8)
                Text(title).font(.system(size: 12.5, weight: .medium))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .glassEffect(isOn ? .regular.tint(Palette.accent.opacity(0.30)) : .regular, in: .capsule)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct ContextCard: View {
    @Bindable var model: Model

    var body: some View {
        let scope = model.effectiveScope
        let tokens = model.currentExportTokens(.scope)
        let baseline = max(1, model.baselineTokens)
        let frac = min(1, Double(tokens) / Double(baseline))
        let saved = max(0, Int((1 - frac) * 100))
        let subtitle: String = {
            let t = model.scopeTitle(scope)
            return model.scopeIsFallback ? "\(t) · elige una galaxia o un nodo para acotar" : t
        }()

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Contexto para IA").font(.system(size: 17, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Picker("Alcance", selection: $model.scopeChoice) {
                    ForEach(ScopeChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 236)
            }

            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.10))
                        Capsule().fill(Palette.accent).frame(width: max(8, g.size.width * frac))
                    }
                }
                .frame(height: 8)
                HStack(spacing: 6) {
                    Text("~\(formatTokens(tokens)) tokens").font(.system(size: 13, weight: .semibold))
                    Text("de ~\(formatTokens(baseline)) del grafo completo · \(saved) % menos")
                        .font(.system(size: 12))
                        .foregroundStyle(muted)
                }
            }

            HStack(spacing: 8) {
                ToggleChip(
                    title: "Conciso", isOn: model.conciseExport,
                    help: "Modo caveman: sin prosa, una línea por nodo"
                ) { model.conciseExport.toggle() }
                ToggleChip(
                    title: "Sin ruido", isOn: model.hideNoise,
                    help: model.hiddenCount > 0
                        ? "Oculta \(model.hiddenCount) nodos de configuración (YAML, JSON, XML)"
                        : "Oculta nodos de configuración (YAML, JSON, XML)"
                ) {
                    model.hideNoise.toggle()
                    model.rebuild(animated: true)
                }
                Spacer(minLength: 6)
                Button("Resumen") { model.copyExport(.summary) }
                    .buttonStyle(.glass)
                Button("Sesión nueva") { model.copyExport(.session) }
                    .buttonStyle(.glass)
                Button("Copiar contexto") { model.copyExport(.scope) }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.accent)
            }

            Text("Se copia como Markdown con el prefijo estable primero, para que el caché de prompts lo reutilice.")
                .font(.system(size: 11))
                .foregroundStyle(muted)
        }
        .padding(18)
        .frame(width: 640)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

struct ErrorCard: View {
    @Bindable var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.graphChosen {
                Text("No se pudo abrir el grafo")
                    .font(.system(size: 22, weight: .bold))
                Text(model.graphURL.path)
                    .font(.system(size: 12))
                    .foregroundStyle(muted)
                    .textSelection(.enabled)
                if let e = model.loadError {
                    Text(e).font(.system(size: 13))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Causas probables").font(.system(size: 13, weight: .semibold))
                    Text("• El archivo no existe o se movió de carpeta.")
                    Text("• graphify todavía no generó graph.json.")
                    Text("• El archivo no es un graph.json de graphify.")
                }
                .font(.system(size: 13))
                .foregroundStyle(muted)
                HStack(spacing: 10) {
                    Button("Reintentar") { model.reload() }.buttonStyle(.glass)
                    Button("Abrir grafo…") { model.openPanel() }
                        .buttonStyle(.glassProminent)
                        .tint(Palette.accent)
                }
            } else {
                Text("Abre un grafo")
                    .font(.system(size: 22, weight: .bold))
                Text("Universo dibuja el graph.json que genera graphify: cada comunidad es una galaxia y cada nodo una estrella.")
                    .font(.system(size: 13))
                    .foregroundStyle(muted)
                Text("Arrástralo a esta ventana o usa el botón.")
                    .font(.system(size: 13))
                    .foregroundStyle(muted)
                Button("Abrir grafo…") { model.openPanel() }
                    .buttonStyle(.glassProminent)
                    .tint(Palette.accent)
            }
        }
        .padding(24)
        .frame(width: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}
