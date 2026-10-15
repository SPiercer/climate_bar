import SwiftUI

/// Circular glass thermostat: drag around the ring, or use − / + in the gap at the bottom.
struct ThermostatDial: View {
  @Binding var target: Double
  let indoor: Double?

  private static let range = 16.0...30.0
  private static let start = 135.0  // degrees, 0 = 3 o'clock, increasing clockwise on screen
  private static let sweep = 270.0  // leaves a 90° gap at the bottom

  private var fraction: Double {
    (target - Self.range.lowerBound) / (Self.range.upperBound - Self.range.lowerBound)
  }

  var body: some View {
    GeometryReader { geo in
      let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
      let radius = RingArc.radius(in: geo.size)
      ZStack {
        // Glass track.
        Color.clear.glassEffect(.clear, in: RingArc(start: Self.start, sweep: Self.sweep, width: 22))
        // Set range, coloured from icy blue to warm amber.
        RingArc(start: Self.start, sweep: Self.sweep * fraction, width: 8)
          .fill(AngularGradient(
            colors: [.cyan, .white, .orange], center: .center,
            startAngle: .degrees(Self.start), endAngle: .degrees(Self.start + Self.sweep)))
        // Knob.
        Color.clear
          .frame(width: 26, height: 26)
          .glassEffect(.clear.interactive(), in: .circle)
          .position(point(at: Self.start + Self.sweep * fraction, radius: radius, center: center))
        // Readout.
        VStack(spacing: 2) {
          HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(Int(target))").font(.system(size: 56, weight: .light)).contentTransition(.numericText())
            Text("°C").font(.title3).foregroundStyle(.secondary)
          }
          Label("\(indoor.map { String(format: "%.1f", $0) } ?? "–")° indoors", systemImage: "thermometer.medium")
            .font(.caption).foregroundStyle(.secondary)
        }
        HStack(spacing: 36) {
          stepButton("minus", by: -1)
          stepButton("plus", by: 1)
        }
        .position(x: center.x, y: center.y + radius * 0.82)
      }
      .contentShape(.rect)
      .gesture(
        DragGesture(minimumDistance: 0).onChanged { drag in
          // Only drags that start on the ring turn the dial.
          guard distance(drag.startLocation, center) > radius - 26 else { return }
          let angle = atan2(drag.location.y - center.y, drag.location.x - center.x) * 180 / .pi
          var along = (angle - Self.start + 720).truncatingRemainder(dividingBy: 360)
          if along > Self.sweep { along = along - Self.sweep < (360 - Self.sweep) / 2 ? Self.sweep : 0 }
          let value = (Self.range.lowerBound + along / Self.sweep * 14).rounded()
          // No wrapping straight across the gap from 30 to 16.
          guard value != target, abs(value - target) <= 7 else { return }
          withAnimation(.snappy) { target = value }
        })
    }
    .frame(height: 210)
    // A trackpad tick for every degree, like a physical dial.
    .sensoryFeedback(.alignment, trigger: target)
  }

  private func stepButton(_ symbol: String, by delta: Double) -> some View {
    Button {
      withAnimation { target = min(Self.range.upperBound, max(Self.range.lowerBound, target + delta)) }
    } label: {
      Image(systemName: symbol).frame(width: 30, height: 30).contentShape(.circle)
    }
    .buttonStyle(.plain)
    .glassEffect(.clear.interactive(), in: .circle)
  }

  private func point(at degrees: Double, radius: CGFloat, center: CGPoint) -> CGPoint {
    let radians = degrees * .pi / 180
    return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
  }

  private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

/// A stroked arc, so it can be both filled and used as a glass shape.
struct RingArc: Shape {
  var start: Double
  var sweep: Double
  var width: CGFloat

  static func radius(in size: CGSize) -> CGFloat { min(size.width, size.height) / 2 - 16 }

  func path(in rect: CGRect) -> Path {
    var arc = Path()
    arc.addArc(
      center: CGPoint(x: rect.midX, y: rect.midY), radius: Self.radius(in: rect.size),
      startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
    return arc.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round))
  }
}
