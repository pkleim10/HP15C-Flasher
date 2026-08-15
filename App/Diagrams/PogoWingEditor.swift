#if DEBUG
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Debug-only node editor for the pogo wings. Same workflow as the lunar-lander tracer:
/// place / drag points, then copy a Swift snippet into `PogoWingOutline.left`.
struct PogoWingEditorView: View {
    @State private var nodes: [CGPoint] = []
    @State private var history: [[CGPoint]] = []
    @State private var selected: Int?
    @State private var dragging = false
    @State private var hover: CGPoint?
    @State private var photo: NSImage?
    @State private var photoOpacity: Double = 0.55
    @State private var photoScale: Double = 1.0
    @State private var photoOffset: CGSize = .zero
    @State private var pickingPhoto = false
    @State private var status = "Click a segment to insert a node between its ends. Select a node, then Delete."
    @State private var copied = false
    @FocusState private var canvasFocused: Bool

    private let canvasHeight: CGFloat = 520

    private var photoOffsetX: Binding<Double> {
        Binding(
            get: { Double(photoOffset.width) },
            set: { photoOffset.width = $0 }
        )
    }

    private var photoOffsetY: Binding<Double> {
        Binding(
            get: { Double(photoOffset.height) },
            set: { photoOffset.height = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            canvas
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
            snippet
        }
        .padding(16)
        .frame(minWidth: 560, idealWidth: 620)
        .onPasteCommand(of: [.plainText]) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String else { return }
                    DispatchQueue.main.async { applyPasted(text) }
                }
            }
        }
        .fileImporter(isPresented: $pickingPhoto, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                photo = NSImage(contentsOf: url)
                status = photo == nil ? "Could not load photo" : "Photo loaded — align with the housing, then trace the left wing"
            case .failure(let error):
                status = error.localizedDescription
            }
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pogo Wing Editor")
                .font(.title2.weight(.semibold))
            Text("Click a segment to insert. Select a node, then Delete. Paste previous reloads a Swift snippet or JSON from the last run.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Load photo…") { pickingPhoto = true }
                Button("Undo") { undo() }
                    .disabled(history.isEmpty)
                Button("Delete node") { deleteSelected() }
                    .disabled(selected == nil)
                    .keyboardShortcut(.delete, modifiers: [])
                Button("Clear") {
                    pushHistory()
                    nodes = []
                    selected = nil
                    status = "Cleared"
                }
                Button(copied ? "Copied" : "Copy Swift") { copySwift() }
                Button("Paste previous") { pastePrevious() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Spacer()
            }
            HStack(spacing: 16) {
                labeledSlider("Photo", value: $photoOpacity, range: 0...1)
                labeledSlider("Scale", value: $photoScale, range: 0.4...2.4)
                labeledSlider("X", value: photoOffsetX, range: -120...120)
                labeledSlider("Y", value: photoOffsetY, range: -120...120)
            }
        }
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Slider(value: value, in: range)
                .frame(maxWidth: 180)
        }
    }

    private var canvasWidth: CGFloat {
        canvasHeight * PogoPlugDrawing.aspect
    }

    private var canvas: some View {
        ZStack {
            if let photo {
                Image(nsImage: photo)
                    .resizable()
                    .scaledToFit()
                    .opacity(photoOpacity)
                    .scaleEffect(photoScale)
                    .offset(photoOffset)
                    .frame(width: canvasWidth, height: canvasHeight)
                    .clipped()
                    .allowsHitTesting(false)
            }
            PogoPlugDrawing(leftWingOverride: nodes.count >= 3 ? nodes : nil)
                .frame(width: canvasWidth, height: canvasHeight)
                .allowsHitTesting(false)
            Canvas { context, size in
                let box = PogoPlugDrawing.drawingBox(in: size)
                if nodes.count >= 2 {
                    var path = Path()
                    path.move(to: PogoPlugDrawing.viewPoint(nodes[0], in: box))
                    for n in nodes.dropFirst() {
                        path.addLine(to: PogoPlugDrawing.viewPoint(n, in: box))
                    }
                    path.closeSubpath()
                    context.stroke(path, with: .color(Color.accentColor.opacity(0.85)), lineWidth: 1.4)
                }
                if let hover, nodes.count >= 2, hitIndex(hover) == nil, let ghost = insertPreview(hover) {
                    let p = PogoPlugDrawing.viewPoint(ghost, in: box)
                    let rect = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.orange.opacity(0.9)))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1)
                }
                for (i, n) in nodes.enumerated() {
                    let p = PogoPlugDrawing.viewPoint(n, in: box)
                    let r: CGFloat = i == selected ? 6.5 : 4.5
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(i == selected ? Color.green : Color.accentColor))
                    context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85)), lineWidth: 1)
                }
            }
            .frame(width: canvasWidth, height: canvasHeight)
            .contentShape(Rectangle())
            .focusable()
            .focused($canvasFocused)
            .onContinuousHover { phase in
                switch phase {
                case .active(let loc):
                    let box = PogoPlugDrawing.drawingBox(in: CGSize(width: canvasWidth, height: canvasHeight))
                    hover = PogoPlugDrawing.normalizedPoint(loc, in: box)
                case .ended:
                    hover = nil
                }
            }
            .gesture(editGesture)
            .onDeleteCommand { deleteSelected() }
            .onAppear {
                canvasFocused = true
                if nodes.isEmpty, PogoWingOutline.left.count >= 3 {
                    nodes = PogoWingOutline.left
                    status = "Loaded \(nodes.count) nodes from PogoWingOutline.left"
                }
            }
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Rectangle().stroke(Color.secondary.opacity(0.35), lineWidth: 1))
    }

    private var editGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                canvasFocused = true
                let box = PogoPlugDrawing.drawingBox(in: CGSize(width: canvasWidth, height: canvasHeight))
                let n = PogoPlugDrawing.normalizedPoint(value.location, in: box)
                if !dragging {
                    guard let hit = hitIndex(n) else { return }
                    pushHistory()
                    selected = hit
                    dragging = true
                }
                if dragging, let i = selected {
                    nodes[i] = clamp(n)
                }
            }
            .onEnded { value in
                let box = PogoPlugDrawing.drawingBox(in: CGSize(width: canvasWidth, height: canvasHeight))
                let n = clamp(PogoPlugDrawing.normalizedPoint(value.location, in: box))
                let moved = value.translation.width.magnitude >= 3 || value.translation.height.magnitude >= 3
                if dragging {
                    status = moved ? "Moved node \( (selected ?? 0) + 1 )" : "Selected node \((selected ?? 0) + 1) — Delete to remove"
                    dragging = false
                    return
                }
                if let hit = hitIndex(n) {
                    selected = hit
                    status = "Selected node \(hit + 1) of \(nodes.count) — Delete to remove"
                    return
                }
                pushHistory()
                insert(n)
            }
    }

    private var snippet: some View {
        TextEditor(text: .constant(swiftSnippet))
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 140, maxHeight: 180)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.35)))
            .onPasteCommand(of: [.plainText]) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                        guard let text = object as? String else { return }
                        DispatchQueue.main.async { applyPasted(text) }
                    }
                }
            }
    }

    private var swiftSnippet: String {
        guard nodes.count >= 3 else {
            return "// Place at least 3 nodes on the left wing"
        }
        let lines = nodes.map { p in
            let x = String(format: "%.3f", p.x)
            let y = String(format: "%.3f", p.y)
            return "        CGPoint(x: \(x), y: \(y)),"
        }
        return ([
            "// Paste into App/Diagrams/WizardDiagrams.swift — PogoWingOutline.left",
            "enum PogoWingOutline {",
            "    /// Closed left-wing outline in 0–1 drawing space. Right wing is mirrored.",
            "    static let left: [CGPoint] = ["
        ] + lines + [
            "    ]",
            "}"
        ]).joined(separator: "\n")
    }

    private func hitIndex(_ n: CGPoint) -> Int? {
        let threshold: CGFloat = 0.035
        return nodes.enumerated().min(by: {
            hypot($0.element.x - n.x, $0.element.y - n.y) < hypot($1.element.x - n.x, $1.element.y - n.y)
        }).flatMap { hypot($0.element.x - n.x, $0.element.y - n.y) < threshold ? $0.offset : nil }
    }

    private func insert(_ n: CGPoint) {
        guard nodes.count >= 2 else {
            nodes.append(n)
            selected = nodes.count - 1
            status = "Placed node \(nodes.count)"
            return
        }
        let index = nearestSegmentIndex(n)
        nodes.insert(n, at: index)
        selected = index
        status = "Inserted node \(index + 1) of \(nodes.count) between neighbors"
    }

    private func insertPreview(_ n: CGPoint) -> CGPoint? {
        guard nodes.count >= 2 else { return nil }
        let i = nearestSegmentIndex(n)
        let a = nodes[(i + nodes.count - 1) % nodes.count]
        let b = nodes[i % nodes.count]
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-8 { return a }
        let t = max(0, min(1, ((n.x - a.x) * dx + (n.y - a.y) * dy) / len2))
        return CGPoint(x: a.x + t * dx, y: a.y + t * dy)
    }

    private func nearestSegmentIndex(_ n: CGPoint) -> Int {
        var bestI = 1
        var bestD = CGFloat.greatestFiniteMagnitude
        for i in 0..<nodes.count {
            let a = nodes[i]
            let b = nodes[(i + 1) % nodes.count]
            let d = distanceToSegment(n, a, b)
            if d < bestD {
                bestD = d
                bestI = i + 1
            }
        }
        return bestI
    }

    private func deleteSelected() {
        guard let i = selected, nodes.indices.contains(i) else {
            status = "Select a node first, then Delete"
            return
        }
        pushHistory()
        nodes.remove(at: i)
        if nodes.isEmpty {
            selected = nil
        } else {
            selected = min(i, nodes.count - 1)
        }
        status = "Deleted node — \(nodes.count) remaining"
    }

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-8 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, -0.05), 1.05), y: min(max(p.y, -0.05), 1.05))
    }

    private func pushHistory() {
        history.append(nodes)
        if history.count > 80 { history.removeFirst() }
    }

    private func undo() {
        guard let prev = history.popLast() else { return }
        nodes = prev
        selected = nil
        status = "Undo"
    }

    private func copySwift() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(swiftSnippet, forType: .string)
        copied = true
        status = "Swift snippet copied — paste into PogoWingOutline.left"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }

    private func pastePrevious() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        applyPasted(text)
    }

    private func applyPasted(_ text: String) {
        guard let imported = Self.parseWingImport(text) else {
            status = "Clipboard is not a previous Swift snippet or JSON export"
            return
        }
        pushHistory()
        nodes = imported
        selected = nil
        status = "Pasted previous run: \(nodes.count) nodes"
    }

    /// Accepts a Swift `PogoWingOutline` snippet or a tracer JSON export.
    private static func parseWingImport(_ text: String) -> [CGPoint]? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            if let dict = json as? [String: Any] {
                if let drawing = dict["drawing"] as? [String: Any],
                   let points = points(fromJSON: drawing["left"]) {
                    return points
                }
                if let points = points(fromJSON: dict["left"]) { return points }
                if let image = dict["imageSpace"] as? [String: Any],
                   let points = points(fromJSON: image["nodes"]) {
                    return points
                }
            }
            if let points = points(fromJSON: json) { return points }
        }
        let regex = try? NSRegularExpression(pattern: #"CGPoint\s*\(\s*x:\s*([-+0-9.eE]+)\s*,\s*y:\s*([-+0-9.eE]+)\s*\)"#)
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        let matches = regex?.matches(in: raw, range: range) ?? []
        let points: [CGPoint] = matches.compactMap { match in
            guard match.numberOfRanges >= 3,
                  let xr = Range(match.range(at: 1), in: raw),
                  let yr = Range(match.range(at: 2), in: raw),
                  let x = Double(raw[xr]),
                  let y = Double(raw[yr])
            else { return nil }
            return CGPoint(x: x, y: y)
        }
        return points.count >= 2 ? points : nil
    }

    private static func points(fromJSON value: Any?) -> [CGPoint]? {
        guard let array = value as? [Any], array.count >= 2 else { return nil }
        let pts: [CGPoint] = array.compactMap { item in
            if let pair = item as? [Any], pair.count >= 2, let x = double(pair[0]), let y = double(pair[1]) {
                return CGPoint(x: x, y: y)
            }
            if let dict = item as? [String: Any], let x = double(dict["x"]), let y = double(dict["y"]) {
                return CGPoint(x: x, y: y)
            }
            return nil
        }
        return pts.count >= 2 ? pts : nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }
}
#endif
