import SwiftUI

/// Interactive knowledge graph: items as nodes coloured by memory state, edges for
/// prerequisites (arrows) and other relations. Pan, pinch-zoom, tap to select and
/// navigate between connected concepts. Weak prerequisites of failing items are flagged.
struct KnowledgeGraphView: View {
    let subjectID: UUID?
    @EnvironmentObject private var store: MemoraStore

    @State private var filterSubject: UUID?
    @State private var positions: [UUID: CGPoint] = [:]
    @State private var canvasSize: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var baseScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var selected: UUID?
    @State private var layoutKey = ""
    @State private var showLinkSheet = false

    private var activeSubject: UUID? { subjectID ?? filterSubject }

    private var nodes: [LearningItem] {
        Array(store.items(in: activeSubject).prefix(400))
    }

    private var edges: [ConceptLink] {
        let ids = Set(nodes.map(\.id))
        return store.db.links.filter { ids.contains($0.fromID) && ids.contains($0.toID) }
    }

    private var weakFoundationIDs: Set<UUID> {
        let diagnoses = PrerequisiteAnalyzer.diagnoses(items: store.db.items, logs: store.db.reviewLogs, links: store.db.links,
                                                       scheduler: store.scheduler, now: Date())
        return Set(diagnoses.flatMap { $0.weakPrerequisites.map(\.id) })
    }

    var body: some View {
        VStack(spacing: 0) {
            if subjectID == nil && !store.db.subjects.isEmpty {
                Picker(L("common.subject"), selection: $filterSubject) {
                    Text(L("common.allSubjects")).tag(UUID?.none)
                    ForEach(store.db.subjects) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if nodes.isEmpty {
                EmptyStateView(systemImage: "point.3.connected.trianglepath.dotted", title: L("graph.empty.title"), message: L("graph.empty.message"))
                Spacer()
            } else {
                GeometryReader { geo in
                    graphCanvas
                        .onAppear { relayout(size: geo.size) }
                        .onChange(of: geo.size) { _, size in relayout(size: size) }
                        .onChange(of: layoutSignature) { _, _ in relayout(size: geo.size) }
                }
                if let id = selected, let item = store.item(id) {
                    selectionPanel(item)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    legend
                }
            }
        }
        .memoraScreen()
        .navigationTitle(L("graph.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation(.spring()) { scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero }
                } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                .accessibilityLabel(L("graph.reset"))
            }
        }
        .sheet(isPresented: $showLinkSheet) {
            if let id = selected, let item = store.item(id) {
                LinkEditorSheet(item: item).environmentObject(store)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selected)
    }

    private var layoutSignature: String {
        "\(nodes.count)-\(edges.count)-\(activeSubject?.uuidString ?? "all")"
    }

    private func relayout(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let key = layoutSignature + "-\(Int(size.width))x\(Int(size.height))"
        guard key != layoutKey else { return }
        layoutKey = key
        canvasSize = size
        let ids = nodes.map(\.id)
        let pairs = edges.map { ($0.fromID, $0.toID) }
        Task.detached(priority: .userInitiated) {
            let computed = GraphLayout.layout(nodeIDs: ids, edges: pairs, size: size)
            await MainActor.run { positions = computed }
        }
    }

    private func screenPoint(_ p: CGPoint) -> CGPoint {
        let cx = canvasSize.width / 2, cy = canvasSize.height / 2
        return CGPoint(x: (p.x - cx) * scale + cx + offset.width, y: (p.y - cy) * scale + cy + offset.height)
    }

    private var graphCanvas: some View {
        let weak = weakFoundationIDs
        let items = nodes
        return Canvas { context, _ in
            for edge in edges {
                guard let a = positions[edge.fromID], let b = positions[edge.toID] else { continue }
                let p1 = screenPoint(a), p2 = screenPoint(b)
                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                let highlighted = selected == edge.fromID || selected == edge.toID
                let color: Color = edge.kind == .prerequisite ? Theme.accent : Theme.violet
                context.stroke(path, with: .color(color.opacity(highlighted ? 0.9 : 0.35)),
                               style: StrokeStyle(lineWidth: highlighted ? 2 : 1, dash: edge.kind == .prerequisite ? [] : [4, 4]))
                if edge.kind == .prerequisite {
                    let angle = atan2(p2.y - p1.y, p2.x - p1.x)
                    let tip = CGPoint(x: p2.x - cos(angle) * 12 * scale, y: p2.y - sin(angle) * 12 * scale)
                    var arrow = Path()
                    arrow.move(to: tip)
                    arrow.addLine(to: CGPoint(x: tip.x - cos(angle - 0.4) * 8, y: tip.y - sin(angle - 0.4) * 8))
                    arrow.move(to: tip)
                    arrow.addLine(to: CGPoint(x: tip.x - cos(angle + 0.4) * 8, y: tip.y - sin(angle + 0.4) * 8))
                    context.stroke(arrow, with: .color(color.opacity(highlighted ? 0.9 : 0.5)), lineWidth: 1.5)
                }
            }
            for item in items {
                guard let p = positions[item.id] else { continue }
                let center = screenPoint(p)
                let radius: CGFloat = (selected == item.id ? 11 : 8) * max(0.7, min(scale, 1.6))
                let state = MemoryStateClassifier.state(of: item, scheduler: store.scheduler, now: Date())
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Theme.color(for: state)))
                if weak.contains(item.id) {
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(Theme.danger), lineWidth: 2)
                }
                if selected == item.id {
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(.primary), lineWidth: 1.5)
                }
                if scale >= 0.8 || selected == item.id {
                    let label = Text(item.title).font(.system(size: 10, weight: .medium)).foregroundColor(.primary)
                    context.draw(label, at: CGPoint(x: center.x, y: center.y + radius + 9), anchor: .center)
                }
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    offset = CGSize(width: baseOffset.width + value.translation.width, height: baseOffset.height + value.translation.height)
                }
                .onEnded { _ in baseOffset = offset }
                .simultaneously(with:
                    MagnificationGesture()
                        .onChanged { value in scale = min(4, max(0.3, baseScale * value)) }
                        .onEnded { _ in baseScale = scale }
                )
        )
        .onTapGesture { location in
            selectNode(at: location)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LF("graph.a11y", nodes.count, edges.count))
    }

    private func selectNode(at location: CGPoint) {
        var best: (UUID, CGFloat)?
        for (id, p) in positions {
            let s = screenPoint(p)
            let d = hypot(s.x - location.x, s.y - location.y)
            if d < 28, d < (best?.1 ?? .infinity) { best = (id, d) }
        }
        selected = best?.0
        if best != nil { Haptics.selection() }
    }

    private func selectionPanel(_ item: LearningItem) -> some View {
        let prerequisites = PrerequisiteAnalyzer.prerequisiteIDs(of: item.id, links: store.db.links).compactMap { store.item($0) }
        let dependents = PrerequisiteAnalyzer.dependentIDs(of: item.id, links: store.db.links).compactMap { store.item($0) }
        let related = store.links(for: item.id).filter { $0.kind != .prerequisite }
            .compactMap { store.item($0.fromID == item.id ? $0.toID : $0.fromID) }
        let weak = store.weakPrerequisites(of: item)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.title).font(.headline).lineLimit(2)
                Spacer()
                MemoryStateBadge(state: store.memoryState(of: item))
                Button { selected = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel(L("common.close"))
            }
            if !weak.isEmpty {
                Label(LF("graph.weakFoundations", weak.map(\.title).joined(separator: "، ")), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.danger)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(prerequisites) { p in navChip(p, prefix: "↧") }
                    ForEach(dependents) { p in navChip(p, prefix: "↥") }
                    ForEach(related) { p in navChip(p, prefix: "↔") }
                }
            }
            HStack {
                NavigationLink { ItemDetailView(itemID: item.id) } label: { Label(L("graph.open"), systemImage: "doc.text.magnifyingglass") }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                Button { showLinkSheet = true } label: { Label(L("item.links.add"), systemImage: "link.badge.plus") }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true, tint: Theme.violet))
            }
        }
        .padding(Theme.padding)
        .background(.ultraThinMaterial)
    }

    private func navChip(_ item: LearningItem, prefix: String) -> some View {
        Button {
            selected = item.id
            if let p = positions[item.id] {
                withAnimation(.easeInOut) {
                    offset = CGSize(width: (canvasSize.width / 2 - p.x) * scale, height: (canvasSize.height / 2 - p.y) * scale)
                    baseOffset = offset
                }
            }
        } label: {
            Chip(text: prefix + " " + item.title, tint: Theme.color(for: store.memoryState(of: item)))
        }
        .buttonStyle(.plain)
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(MemoryState.allCases) { state in
                    HStack(spacing: 4) {
                        Circle().fill(Theme.color(for: state)).frame(width: 8, height: 8)
                        Text(state.title).font(.caption2)
                    }
                }
                HStack(spacing: 4) {
                    Circle().stroke(Theme.danger, lineWidth: 2).frame(width: 10, height: 10)
                    Text(L("graph.legend.weakFoundation")).font(.caption2)
                }
                Text(L("graph.legend.arrow")).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }
}
