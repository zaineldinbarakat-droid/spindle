import SwiftUI

/// Edits a multi-stop gradient.
///
/// - Start from a palette, or build your own: click the bar to add a colour there
///   (matched to the gradient at that point), drag a handle to move it, select one to
///   recolour it from the swatches or the colour picker.
/// - Point it any way: arrow buttons for the common directions, or the dial.
struct GradientEditor: View {
    @Binding var stops: [GradientStop]
    @Binding var angle: Double

    @State private var selectedID: GradientStop.ID?

    private let barHeight: CGFloat = 30
    private let handleSize: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            palettes

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    Checkerboard()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .frame(height: barHeight)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(stops: sorted.map { .init(color: $0.color.color, location: $0.location) },
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: barHeight)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15)))
                        .contentShape(Rectangle())
                        .onTapGesture { location in addStop(at: location.x / max(width, 1)) }
                        .help("Click to add a colour here")

                    ForEach(stops) { stop in
                        handle(for: stop)
                            .position(x: CGFloat(stop.location) * width, y: barHeight + handleSize / 2 + 4)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        selectedID = stop.id
                                        move(stop.id, to: value.location.x / max(width, 1))
                                    }
                            )
                    }
                }
            }
            .frame(height: barHeight + handleSize + 8)
            .padding(.horizontal, handleSize / 2)

            HStack(spacing: 8) {
                Button { addStop(at: largestGapMiddle) } label: { Label("Add Color", systemImage: "plus") }
                Button("Space Evenly", action: spaceEvenly)
                    .disabled(stops.count < 3)
                Button {
                    stops = stops.map { GradientStop(id: $0.id, color: $0.color, location: 1 - $0.location) }
                } label: { Label("Reverse", systemImage: "arrow.left.arrow.right") }
                Spacer()
            }
            .controlSize(.small)

            if let index = stops.firstIndex(where: { $0.id == selectedID }) {
                selectedStopEditor(index)
            } else {
                Text("Select a color handle to change it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            direction
        }
    }

    // MARK: - Pieces

    private var palettes: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MenuBarStyle.palettes, id: \.0) { name, colors in
                    Button {
                        stops = colors.enumerated().map { index, color in
                            GradientStop(color: color, location: Double(index) / Double(max(colors.count - 1, 1)))
                        }
                        selectedID = nil
                    } label: {
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(LinearGradient(colors: colors.map(\.color), startPoint: .leading, endPoint: .trailing))
                                .frame(width: 58, height: 18)
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
                            Text(name).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Use the \(name) colors")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func selectedStopEditor(_ index: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(MenuBarStyle.swatches.enumerated()), id: \.offset) { _, swatch in
                Button { stops[index].color = swatch } label: {
                    Circle().fill(swatch.color).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                }
                .buttonStyle(.plain)
            }
            ColorPicker("", selection: Binding(
                get: { stops[index].color.color },
                set: { stops[index].color = RGBA($0) }))
                .labelsHidden()
                .help("Any color")
            Spacer()
            Button(role: .destructive) {
                stops.remove(at: index)
                selectedID = nil
            } label: { Image(systemName: "trash") }
            .buttonStyle(.borderless)
            .disabled(stops.count <= 2)
            .help("Remove this color")
        }
    }

    private var direction: some View {
        HStack(spacing: 8) {
            Text("Direction")
            ForEach([(0.0, "arrow.right"), (45, "arrow.down.right"), (90, "arrow.down"),
                     (135, "arrow.down.left"), (180, "arrow.left")], id: \.0) { value, symbol in
                Button { angle = value } label: {
                    Image(systemName: symbol)
                        .frame(width: 22, height: 20)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(Int(angle) == Int(value) ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            AngleDial(angle: $angle)
            Text("\(Int(angle))°").monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
        }
    }

    private var sorted: [GradientStop] { stops.sorted { $0.location < $1.location } }

    private func handle(for stop: GradientStop) -> some View {
        let selected = stop.id == selectedID
        return ZStack {
            Circle().fill(Color.white).frame(width: handleSize, height: handleSize)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            Circle().fill(stop.color.color.opacity(1)).frame(width: handleSize - 5, height: handleSize - 5)
        }
        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2.5 : 0)
            .frame(width: handleSize + 5, height: handleSize + 5))
        .contentShape(Circle().inset(by: -6))
    }

    // MARK: - Editing

    private func move(_ id: GradientStop.ID, to location: Double) {
        guard let index = stops.firstIndex(where: { $0.id == id }) else { return }
        stops[index].location = min(max(location, 0), 1)
    }

    private func addStop(at location: Double) {
        let location = min(max(location, 0), 1)
        let stop = GradientStop(color: color(at: location), location: location)
        stops.append(stop)
        selectedID = stop.id
    }

    private func spaceEvenly() {
        let order = sorted.map(\.id)
        for (rank, id) in order.enumerated() {
            if let index = stops.firstIndex(where: { $0.id == id }) {
                stops[index].location = Double(rank) / Double(max(order.count - 1, 1))
            }
        }
    }

    /// The middle of the widest gap between stops: where "Add Color" puts a new one.
    private var largestGapMiddle: Double {
        let locations = sorted.map(\.location)
        guard locations.count >= 2 else { return 0.5 }
        var best = (gap: 0.0, middle: 0.5)
        for (a, b) in zip(locations, locations.dropFirst()) where b - a > best.gap {
            best = (b - a, (a + b) / 2)
        }
        return best.middle
    }

    /// The gradient's colour at `location`, so a new stop doesn't change the look.
    private func color(at location: Double) -> RGBA {
        let s = sorted
        guard let upper = s.firstIndex(where: { $0.location >= location }) else { return s.last?.color ?? RGBA(r: 1, g: 1, b: 1) }
        guard upper > 0 else { return s[0].color }
        let a = s[upper - 1], b = s[upper]
        let t = (location - a.location) / max(b.location - a.location, 0.0001)
        return RGBA(r: a.color.r + (b.color.r - a.color.r) * t,
                    g: a.color.g + (b.color.g - a.color.g) * t,
                    b: a.color.b + (b.color.b - a.color.b) * t,
                    a: a.color.a + (b.color.a - a.color.a) * t)
    }
}

/// A small dial: drag around it to set the angle.
private struct AngleDial: View {
    @Binding var angle: Double

    var body: some View {
        GeometryReader { geo in
            let size = geo.size.width
            let center = CGPoint(x: size / 2, y: size / 2)
            ZStack {
                Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.5)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: size / 2 - 3, height: 2.5)
                    .offset(x: size / 4 - 1.5)
                    .rotationEffect(.degrees(angle))
                Circle().fill(Color.accentColor).frame(width: 4, height: 4)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let degrees = atan2(value.location.y - center.y, value.location.x - center.x) * 180 / .pi
                angle = (degrees + 360).truncatingRemainder(dividingBy: 360).rounded()
            })
        }
        .frame(width: 24, height: 24)
        .help("Drag to set any angle")
    }
}

private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 6
            for row in 0..<Int(ceil(size.height / cell)) {
                for column in 0..<Int(ceil(size.width / cell)) where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(Color.primary.opacity(0.08)))
                }
            }
        }
    }
}
