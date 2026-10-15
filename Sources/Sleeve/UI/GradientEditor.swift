import SwiftUI

/// Edits a multi-stop gradient: a live bar with a handle per colour stop.
///
/// - Drag a handle to move its stop.
/// - Click the bar to add a stop there, coloured to match the gradient at that point.
/// - Select a handle to recolour it, or remove it (two stops always remain).
struct GradientEditor: View {
    @Binding var stops: [GradientStop]
    @Binding var angle: Double

    @State private var selectedID: GradientStop.ID?

    private let barHeight: CGFloat = 26
    private let handleSize: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    // Checkerboard under the bar so translucent stops read as translucent.
                    Checkerboard()
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .frame(height: barHeight)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(stops: sorted.map { .init(color: $0.color.color, location: $0.location) },
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: barHeight)
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.15)))
                        .contentShape(Rectangle())
                        .onTapGesture { location in addStop(at: location.x / max(width, 1)) }

                    ForEach(stops) { stop in
                        handle(for: stop)
                            .position(x: CGFloat(stop.location) * width, y: barHeight + handleSize / 2 + 3)
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
            .frame(height: barHeight + handleSize + 6)
            .padding(.horizontal, handleSize / 2)

            HStack(spacing: 12) {
                if let index = stops.firstIndex(where: { $0.id == selectedID }) {
                    ColorPicker("Stop colour", selection: Binding(
                        get: { stops[index].color.color },
                        set: { stops[index].color = RGBA($0) }))
                    Text("\(Int(stops[index].location * 100))%")
                        .monospacedDigit().foregroundStyle(.secondary)
                    Button(role: .destructive) {
                        stops.remove(at: index)
                        selectedID = nil
                    } label: { Image(systemName: "trash") }
                    .disabled(stops.count <= 2)
                    .help("Remove this stop")
                } else {
                    Text("Click the bar to add a colour · select a handle to edit it")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    stops = stops.map { GradientStop(id: $0.id, color: $0.color, location: 1 - $0.location) }
                } label: { Image(systemName: "arrow.left.arrow.right") }
                .help("Reverse")
            }

            HStack(spacing: 10) {
                Text("Angle")
                AngleDial(angle: $angle)
                Slider(value: $angle, in: 0...360, step: 1)
                Text("\(Int(angle))°").monospacedDigit().frame(width: 40, alignment: .trailing)
                ForEach([0.0, 45, 90, 135], id: \.self) { preset in
                    Button("\(Int(preset))°") { angle = preset }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
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
