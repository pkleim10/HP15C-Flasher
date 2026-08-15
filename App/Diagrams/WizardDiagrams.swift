import SwiftUI

struct CalculatorDisplay: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary, lineWidth: 1)
            )
    }
}

private enum Step1Layout {
    static let bayAspect: CGFloat = 1.85
    static let bayMaxWidth: CGFloat = 270
    static let bayMaxHeight: CGFloat = 147
    static let bayWidthFrac: CGFloat = 0.93
    static let bayHeightFrac: CGFloat = 0.90
    static let wellWidthFrac: CGFloat = 0.22
    static let wellHeightFrac: CGFloat = 0.26
    static let padClusterWidthFrac: CGFloat = 0.38
    static let padRadiusFrac: CGFloat = 0.075

    static var bayCanvasSize: CGSize {
        let width = min(bayMaxWidth, bayMaxHeight * bayAspect)
        return CGSize(width: width, height: width / bayAspect)
    }

    /// Connector rectangle only — not the keyed wings.
    static var connectorBodyWidth: CGFloat {
        bayCanvasSize.width * bayWidthFrac * wellWidthFrac
    }

    static var padArrayWidth: CGFloat {
        let wellW = connectorBodyWidth
        let wellH = bayCanvasSize.height * bayHeightFrac * wellHeightFrac
        let padR = min(wellW, wellH) * padRadiusFrac
        return wellW * padClusterWidthFrac + padR * 2
    }

    /// Bottom pogo rectangle: midway between the main body and the pad cluster.
    static var pogoNoseWidthFracOfBody: CGFloat {
        ((connectorBodyWidth + padArrayWidth) / 2) / connectorBodyWidth
    }

    static let pogoNoseBottom: CGFloat = 0.865

    static var padDiameterFracOfBody: CGFloat {
        let wellW = connectorBodyWidth
        let wellH = bayCanvasSize.height * bayHeightFrac * wellHeightFrac
        return (min(wellW, wellH) * padRadiusFrac * 2) / wellW
    }

    static var padCenterSpacingFracOfBody: CGFloat {
        padClusterWidthFrac / 2
    }
}

struct CableDiagram: View {
    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(spacing: 8) {
                BatteryBayDrawing()
                    .aspectRatio(Step1Layout.bayAspect, contentMode: .fit)
                    .frame(maxWidth: Step1Layout.bayMaxWidth, maxHeight: Step1Layout.bayMaxHeight)
                Text("Pogo connector · narrow key left, wide key right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                let plugSize = PogoPlugDrawing.sizeMatching(connectorBodyWidth: Step1Layout.connectorBodyWidth)
                PogoPlugDrawing()
                    .frame(width: plugSize.width, height: plugSize.height)
                Text("Pogo plug")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel("Battery bay with two coin cells and keyed pogo connector. Pogo plug shown to the right, pins down.")
    }
}

/// Closed left-wing outline in 0–1 `PogoPlugDrawing` space.
/// Empty uses the built-in curves. Paste tracer output here; the right wing is mirrored.
enum PogoWingOutline {
    /// Closed left-wing outline in 0–1 drawing space. Right wing is mirrored.
    static let left: [CGPoint] = [
        CGPoint(x: 0.144, y: 0.296),
        CGPoint(x: 0.148, y: 0.387),
        CGPoint(x: 0.168, y: 0.723),
        CGPoint(x: 0.188, y: 0.780),
        CGPoint(x: 0.199, y: 0.817),
        CGPoint(x: 0.166, y: 0.813),
        CGPoint(x: 0.236, y: 0.877),
        CGPoint(x: 0.214, y: 0.745),
        CGPoint(x: 0.210, y: 0.393),
        CGPoint(x: 0.253, y: 0.392),
        CGPoint(x: 0.251, y: 0.294),
    ]
}

/// Side-view silhouette of the USB-C pogo plug, pins down, filled dark grey.
/// The main body is a golden rectangle (height / width = φ); the head is scaled to match.
struct PogoPlugDrawing: View {
    @Environment(\.colorScheme) private var colorScheme

    /// When set (Debug wing editor), replaces `PogoWingOutline.left`.
    var leftWingOverride: [CGPoint]? = nil

    private static let phi: CGFloat = (1 + sqrt(5)) / 2
    private static let bodyTop: CGFloat = 0.215
    private static let bodyBottom: CGFloat = 0.80
    private static let bodyH: CGFloat = bodyBottom - bodyTop
    private static let bodyW: CGFloat = 0.50
    private static let widthBoost: CGFloat = 1.10
    private static let bodyLeft: CGFloat = (1 - bodyW) / 2
    private static let bodyRight: CGFloat = 1 - bodyLeft
    static let aspect: CGFloat = {
        let rAspect = bodyH / (bodyW * phi) * widthBoost
        return rAspect * 0.96 / 0.92
    }()

    static func drawingBox(in size: CGSize) -> CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.04, dy: size.height * 0.02)
    }

    static func viewPoint(_ n: CGPoint, in box: CGRect) -> CGPoint {
        CGPoint(x: box.minX + n.x * box.width, y: box.minY + n.y * box.height)
    }

    static func normalizedPoint(_ p: CGPoint, in box: CGRect) -> CGPoint {
        CGPoint(x: (p.x - box.minX) / box.width, y: (p.y - box.minY) / box.height)
    }

    static func sizeMatching(connectorBodyWidth target: CGFloat) -> CGSize {
        let height = target * phi / (bodyH * 0.96 * widthBoost)
        return CGSize(width: height * aspect, height: height)
    }

    var body: some View {
        Canvas { context, size in
            let fill = colorScheme == .dark ? Color(white: 0.72) : Color(white: 0.28)
            let box = Self.drawingBox(in: size)
            context.fill(housingPath(in: box), with: .color(fill))
            context.fill(leftWingPath(in: box), with: .color(fill))
            context.fill(rightWingPath(in: box), with: .color(fill))
            let pinStroke = StrokeStyle(lineWidth: max(1.0, size.width / 140), lineCap: .round, lineJoin: .round)
            for pin in pinRects(in: box) {
                context.stroke(pinOutline(in: pin), with: .color(fill), style: pinStroke)
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func bodyEdges(in r: CGRect) -> (left: CGFloat, right: CGFloat) {
        let w = (Self.bodyH * r.height / Self.phi) / r.width * Self.widthBoost
        let left = (1 - w) / 2
        return (left, 1 - left)
    }

    private func pt(_ x: CGFloat, _ y: CGFloat, in r: CGRect) -> CGPoint {
        CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
    }

    private func housingPath(in r: CGRect) -> Path {
        let e = bodyEdges(in: r)
        let bodyW = e.right - e.left
        let cableW = bodyW * 0.39
        let noseW = bodyW * Step1Layout.pogoNoseWidthFracOfBody
        let cableL = (1 - cableW) / 2
        let cableR = 1 - cableL
        let noseL = (1 - noseW) / 2
        let noseR = 1 - noseL
        var p = Path()
        p.move(to: pt(cableL, 0.00, in: r))
        p.addLine(to: pt(cableR, 0.00, in: r))
        p.addLine(to: pt(cableR, Self.bodyTop, in: r))
        p.addLine(to: pt(e.right, Self.bodyTop, in: r))
        p.addLine(to: pt(e.right, Self.bodyBottom, in: r))
        p.addLine(to: pt(noseR, Self.bodyBottom, in: r))
        p.addLine(to: pt(noseR, Step1Layout.pogoNoseBottom, in: r))
        p.addLine(to: pt(noseL, Step1Layout.pogoNoseBottom, in: r))
        p.addLine(to: pt(noseL, Self.bodyBottom, in: r))
        p.addLine(to: pt(e.left, Self.bodyBottom, in: r))
        p.addLine(to: pt(e.left, Self.bodyTop, in: r))
        p.addLine(to: pt(cableL, Self.bodyTop, in: r))
        p.closeSubpath()
        return p
    }

    private var leftWingPoints: [CGPoint] {
        leftWingOverride ?? PogoWingOutline.left
    }

    private func polyline(_ points: [CGPoint], in r: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: pt(first.x, first.y, in: r))
        for point in points.dropFirst() {
            p.addLine(to: pt(point.x, point.y, in: r))
        }
        p.closeSubpath()
        return p
    }

    private func leftWingPath(in r: CGRect) -> Path {
        let custom = leftWingPoints
        if custom.count >= 3 {
            return polyline(custom, in: r)
        }
        let L = bodyEdges(in: r).left
        var p = Path()
        p.move(to: pt(L, 0.33, in: r))
        p.addQuadCurve(to: pt(0.04, 0.54, in: r), control: pt(0.02, 0.36, in: r))
        p.addQuadCurve(to: pt(L - 0.08, 0.805, in: r), control: pt(0.03, 0.72, in: r))
        p.addLine(to: pt(L + 0.04, 0.795, in: r))
        p.addLine(to: pt(L - 0.02, 0.77, in: r))
        p.addQuadCurve(to: pt(0.13, 0.54, in: r), control: pt(0.13, 0.70, in: r))
        p.addQuadCurve(to: pt(L, 0.39, in: r), control: pt(0.14, 0.40, in: r))
        p.closeSubpath()
        return p
    }

    private func rightWingPath(in r: CGRect) -> Path {
        let custom = leftWingPoints
        if custom.count >= 3 {
            return polyline(custom.map { CGPoint(x: 1 - $0.x, y: $0.y) }, in: r)
        }
        let R = bodyEdges(in: r).right
        var p = Path()
        p.move(to: pt(R, 0.33, in: r))
        p.addQuadCurve(to: pt(0.96, 0.54, in: r), control: pt(0.98, 0.36, in: r))
        p.addQuadCurve(to: pt(R + 0.08, 0.805, in: r), control: pt(0.97, 0.72, in: r))
        p.addLine(to: pt(R - 0.04, 0.795, in: r))
        p.addLine(to: pt(R + 0.02, 0.77, in: r))
        p.addQuadCurve(to: pt(0.87, 0.54, in: r), control: pt(0.87, 0.70, in: r))
        p.addQuadCurve(to: pt(R, 0.39, in: r), control: pt(0.86, 0.40, in: r))
        p.closeSubpath()
        return p
    }

    private func pinRects(in r: CGRect) -> [CGRect] {
        let bodyW = bodyEdges(in: r).right - bodyEdges(in: r).left
        let y = r.minY + Step1Layout.pogoNoseBottom * r.height
        let h = (1 - Step1Layout.pogoNoseBottom) * r.height * 0.85
        let w = bodyW * Step1Layout.padDiameterFracOfBody * r.width
        let span = bodyW * Step1Layout.padCenterSpacingFracOfBody * r.width
        let start = r.midX - span - w / 2
        return (0..<3).map { i in
            CGRect(x: start + CGFloat(i) * span, y: y, width: w, height: h)
        }
    }

    private func pinOutline(in rect: CGRect) -> Path {
        let radius = min(rect.width / 2, rect.height / 2)
        let tip = CGPoint(x: rect.midX, y: rect.maxY - radius)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: tip.y))
        path.addArc(
            center: tip,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Line drawing of the 15C CE battery bay, door off, display end at the top.
/// The keyed pogo connector has a narrow slot on the left and a wide slot on the right.
struct BatteryBayDrawing: View {
    var body: some View {
        Canvas { context, size in
            let ink = Color.primary.opacity(0.78)
            let dim = Color.secondary
            let lw = max(1.15, size.width / 300)
            let line = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)

            func stroke(_ path: Path, color: Color = ink, width: CGFloat? = nil) {
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: width ?? lw, lineCap: .round, lineJoin: .round)
                )
            }

            let bay = CGRect(
                x: size.width * 0.035,
                y: size.height * 0.05,
                width: size.width * Step1Layout.bayWidthFrac,
                height: size.height * Step1Layout.bayHeightFrac
            )
            stroke(Path(roundedRect: bay, cornerRadius: bay.height * 0.07))

            let batteryR = bay.height * 0.32
            let leftC = CGPoint(x: bay.minX + bay.width * 0.26, y: bay.minY + bay.height * 0.36)
            let rightC = CGPoint(x: bay.minX + bay.width * 0.74, y: leftC.y)

            drawBattery(at: leftC, radius: batteryR, in: &context, ink: ink, dim: dim, line: line)
            drawBattery(at: rightC, radius: batteryR, in: &context, ink: ink, dim: dim, line: line)

            let tabW = batteryR * 0.18
            let tabH = batteryR * 0.32
            for center in [leftC, rightC] {
                stroke(Path(roundedRect: CGRect(
                    x: center.x + batteryR - tabW * 0.35,
                    y: center.y - tabH / 2,
                    width: tabW,
                    height: tabH
                ), cornerRadius: 1.5))
            }

            let plusArm = batteryR * 0.20
            let plus = CGPoint(x: bay.midX, y: leftC.y)
            var plusPath = Path()
            plusPath.move(to: CGPoint(x: plus.x - plusArm, y: plus.y))
            plusPath.addLine(to: CGPoint(x: plus.x + plusArm, y: plus.y))
            plusPath.move(to: CGPoint(x: plus.x, y: plus.y - plusArm))
            plusPath.addLine(to: CGPoint(x: plus.x, y: plus.y + plusArm))
            stroke(plusPath, width: lw * 1.7)

            let wellW = bay.width * Step1Layout.wellWidthFrac
            let wellH = bay.height * Step1Layout.wellHeightFrac
            let well = CGRect(
                x: bay.midX - wellW / 2,
                y: bay.maxY - wellH - bay.height * 0.055,
                width: wellW,
                height: wellH
            )
            let narrowKeyW = wellH * 0.16
            let keyH = wellH * 0.70
            let keyY = well.midY - keyH / 2
            let leftKey = CGRect(x: well.minX - narrowKeyW, y: keyY, width: narrowKeyW, height: keyH)

            let innerW = wellH * 0.1804
            let padTop = wellH * 0.155
            let padRight = wellH * 0.080
            let padBottom = wellH * 0.182
            let innerTop = well.midY - wellH * 0.266
            let innerH = well.maxY - padBottom * 1.5 - innerTop
            let innerRect = CGRect(x: well.maxX, y: innerTop, width: innerW, height: innerH)
            let rightKey = CGRect(
                x: well.maxX,
                y: innerRect.minY - padTop,
                width: innerW + padRight,
                height: well.maxY - (innerRect.minY - padTop)
            )
            stroke(keyedWellPath(well: well, leftKey: leftKey, rightKey: rightKey))
            stroke(rightKeyInnerBorder(well: well, inner: innerRect))

            let padR = min(wellW, wellH) * Step1Layout.padRadiusFrac
            let clusterW = wellW * Step1Layout.padClusterWidthFrac
            let clusterH = wellH * 0.34
            let padArea = CGRect(
                x: well.midX - clusterW / 2,
                y: well.midY - clusterH / 2,
                width: clusterW,
                height: clusterH
            )
            for row in 0..<2 {
                for col in 0..<3 {
                    let x = padArea.minX + padArea.width * CGFloat(col) / 2
                    let y = padArea.minY + padArea.height * CGFloat(row)
                    let rect = CGRect(x: x - padR, y: y - padR, width: padR * 2, height: padR * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.accentColor.opacity(0.9)))
                    stroke(Path(ellipseIn: rect))
                }
            }
        }
    }

    private func drawBattery(
        at center: CGPoint,
        radius: CGFloat,
        in context: inout GraphicsContext,
        ink: Color,
        dim: Color,
        line: StrokeStyle
    ) {
        let outer = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: outer), with: .color(ink), style: line)
        let p = radius * 0.16
        var plus = Path()
        plus.move(to: CGPoint(x: center.x - p, y: center.y))
        plus.addLine(to: CGPoint(x: center.x + p, y: center.y))
        plus.move(to: CGPoint(x: center.x, y: center.y - p))
        plus.addLine(to: CGPoint(x: center.x, y: center.y + p))
        context.stroke(plus, with: .color(dim), style: line)
    }

    /// Inner lip of the wide key: top, right, and bottom only. Size is independent of outer padding.
    private func rightKeyInnerBorder(well: CGRect, inner: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: well.maxX, y: inner.minY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.minY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
        path.addLine(to: CGPoint(x: well.maxX, y: inner.maxY))
        return path
    }

    private func keyedWellPath(well: CGRect, leftKey: CGRect, rightKey: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: well.minX, y: well.minY))
        path.addLine(to: CGPoint(x: well.maxX, y: well.minY))
        path.addLine(to: CGPoint(x: well.maxX, y: rightKey.minY))
        path.addLine(to: CGPoint(x: rightKey.maxX, y: rightKey.minY))
        path.addLine(to: CGPoint(x: rightKey.maxX, y: rightKey.maxY))
        path.addLine(to: CGPoint(x: well.maxX, y: rightKey.maxY))
        path.addLine(to: CGPoint(x: well.maxX, y: well.maxY))
        path.addLine(to: CGPoint(x: well.minX, y: well.maxY))
        path.addLine(to: CGPoint(x: well.minX, y: leftKey.maxY))
        path.addLine(to: CGPoint(x: leftKey.minX, y: leftKey.maxY))
        path.addLine(to: CGPoint(x: leftKey.minX, y: leftKey.minY))
        path.addLine(to: CGPoint(x: well.minX, y: leftKey.minY))
        path.closeSubpath()
        return path
    }
}

struct ProgrammingModeDiagram: View {
    var body: some View {
        HStack(spacing: 20) {
            buttonCallout("1. Hold ERASE", systemImage: "e.square.fill")
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            buttonCallout("2. Press RESET", systemImage: "r.square.fill")
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            buttonCallout("3. Release ERASE", systemImage: "e.square")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel("Hold ERASE, press RESET, then release ERASE")
    }

    private func buttonCallout(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .frame(width: 90)
        }
    }
}

struct FinishDiagram: View {
    var body: some View {
        HStack(spacing: 28) {
            VStack(spacing: 6) {
                Image(systemName: "r.square.fill")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                Text("Press RESET")
                    .font(.caption)
            }
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Image(systemName: "power")
                    .font(.title)
                    .foregroundStyle(Color.accentColor)
                Text("Then ON")
                    .font(.caption)
            }
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                CalculatorDisplay("Pr Error")
                Text("Expected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel("Press RESET on the cable, then ON. Pr Error is expected")
    }
}

struct ChecksumDiagram: View {
    var body: some View {
        HStack(spacing: 16) {
            buttonCallout("1. Hold g + ENTER", systemImage: "g.square.fill")
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            buttonCallout("2. Press ON", systemImage: "power")
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                CalculatorDisplay("1.L 2.C 3.H")
                Text("3. Press 2")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel("Hold g and ENTER, press ON, then press 2 for the checksum")
    }

    private func buttonCallout(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .frame(width: 100)
        }
    }
}
