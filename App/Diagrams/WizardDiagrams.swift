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

struct CableDiagram: View {
    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            VStack(spacing: 8) {
                BatteryBayDrawing()
                    .aspectRatio(1.85, contentMode: .fit)
                    .frame(maxWidth: 360, maxHeight: 196)
                Text("Pogo connector · narrow key left, wide key right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                usbCGlyph
                Text("USB-C")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityLabel("Battery bay with two coin cells. Pogo connector at the bottom has a narrow key on the left and a wide key on the right. Then USB-C to the Mac.")
    }

    private var usbCGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary, lineWidth: 1.5)
                .frame(width: 72, height: 36)
            HStack(spacing: 8) {
                Circle().frame(width: 8, height: 8)
                Circle().frame(width: 8, height: 8)
            }
            .foregroundStyle(Color.accentColor)
        }
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
                width: size.width * 0.93,
                height: size.height * 0.90
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

            let wellW = bay.width * 0.22
            let wellH = bay.height * 0.26
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

            let padR = min(wellW, wellH) * 0.075
            let clusterW = wellW * 0.38
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
