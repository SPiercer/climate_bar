import SwiftUI

/// Wall unit with a lit display; air streams out of the vent while it runs.
struct ACHero: View {
  let running: Bool
  let readout: String
  let fan: String
  @State private var changedAt = Date.distantPast
  @State private var fading = false
  @State private var clock = AirClock()

  private static let ramp = 0.8

  var body: some View {
    TimelineView(.animation(paused: !running && !fading)) { context in
      Canvas { canvas, size in
        draw(&canvas, size: size, now: context.date)
      } symbols: {
        Image(systemName: "snowflake").font(.system(size: 8, weight: .semibold)).tag("mode")
      }
    }
    .frame(height: 150)
    .frame(maxWidth: .infinity)
    .accessibilityHidden(true)
    .onChange(of: running) {
      changedAt = .now
      fading = true
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.ramp + 0.1) { fading = false }
    }
  }

  private func draw(_ canvas: inout GraphicsContext, size: CGSize, now: Date) {
    let progress = min(1, now.timeIntervalSince(changedAt) / Self.ramp)
    let level = running ? progress : 1 - progress  // 0 = off, 1 = fully running
    let ink = Color.primary
    let time = now.timeIntervalSinceReferenceDate
    // Air speed follows the fan; Auto gently breathes between slower and faster.
    let fanSpeed = ["Low": 0.5, "Medium": 1, "High": 1.8][fan] ?? 1 + 0.4 * sin(time * 0.25)
    let phase = clock.advance(to: now, toward: fanSpeed)
    let strength = 0.55 + 0.35 * clock.speed  // fainter on Low, denser on High

    // Body.
    let width = min(size.width * 0.66, 240)
    let unit = CGRect(x: (size.width - width) / 2, y: 6, width: width, height: 70)
    let shell = Path(roundedRect: unit, cornerRadius: 7, style: .continuous)
    canvas.fill(shell, with: .linearGradient(
      Gradient(colors: [ink.opacity(0.14), ink.opacity(0.04)]),
      startPoint: CGPoint(x: unit.midX, y: unit.minY), endPoint: CGPoint(x: unit.midX, y: unit.maxY)))
    canvas.stroke(shell, with: .color(ink.opacity(0.25 + 0.2 * level)), lineWidth: 1)
    var shine = Path()
    shine.move(to: CGPoint(x: unit.minX + 8, y: unit.minY + 1.5))
    shine.addLine(to: CGPoint(x: unit.maxX - 8, y: unit.minY + 1.5))
    canvas.stroke(shine, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, lineCap: .round))

    // Display: snowflake + target temperature, blank when off.
    let display = CGRect(x: unit.maxX - 64, y: unit.minY + 14, width: 46, height: 18)
    canvas.fill(Path(roundedRect: display, cornerRadius: 4, style: .continuous), with: .color(.black.opacity(0.3)))
    var lit = canvas
    lit.opacity = level
    if let symbol = canvas.resolveSymbol(id: "mode") {
      lit.draw(symbol, at: CGPoint(x: display.minX + 11, y: display.midY))
    }
    lit.draw(Text(readout).font(.system(size: 10, weight: .semibold).monospacedDigit()),
             at: CGPoint(x: display.maxX - 14, y: display.midY))

    // Vent grille.
    let vent = CGRect(x: unit.minX + 18, y: unit.maxY - 20, width: width - 36, height: 11)
    canvas.fill(Path(roundedRect: vent, cornerRadius: 2), with: .color(.black.opacity(0.35)))
    var slats = Path()
    var x = vent.minX + 6
    while x < vent.maxX - 3 {
      slats.move(to: CGPoint(x: x, y: vent.minY + 2))
      slats.addLine(to: CGPoint(x: x, y: vent.maxY - 2))
      x += 7
    }
    canvas.stroke(slats, with: .color(ink.opacity(0.18)), lineWidth: 1)

    // Airflow: wisps fanning out and down from the vent.
    guard level > 0.01 else { return }
    let top = vent.maxY + 6, depth = size.height - top - 4
    func point(_ t: Double, _ p: Double, _ seed: Double) -> CGPoint {
      let spread = t * (vent.width / 2 - 10 + p * width * 0.32)
      let sway = sin(time * 1.6 + seed) * 3 * p
      return CGPoint(x: unit.midX + spread + sway, y: top + p * depth)
    }
    canvas.drawLayer { air in
      air.addFilter(.blur(radius: 0.6))
      let streams = 11
      for stream in 0..<streams {
        let t = Double(stream) / Double(streams - 1) * 2 - 1
        for wisp in 0..<3 {
          let seed = Double(stream * 7 + wisp * 13)
          let cycle = (phase * 0.4 * (0.85 + 0.3 * abs(sin(seed))) + Double(wisp) / 3 + sin(seed * 1.7) * 0.5)
            .truncatingRemainder(dividingBy: 1)
          let head = cycle, tail = max(0, head - 0.32)
          guard head > 0.02 else { continue }
          var path = Path()
          path.move(to: point(t, tail, seed))
          for step in 1...8 { path.addLine(to: point(t, tail + (head - tail) * Double(step) / 8, seed)) }
          let alpha = sin(.pi * cycle) * (0.45 - abs(t) * 0.15) * level * strength
          air.stroke(path, with: .linearGradient(
            Gradient(colors: [ink.opacity(0), ink.opacity(alpha)]),
            startPoint: point(t, tail, seed), endPoint: point(t, head, seed)),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
        // Cold particles drifting between the wisps.
        if stream % 2 == 1 {
          let seed = Double(stream * 11)
          let cycle = (phase * 0.3 + cos(seed)).truncatingRemainder(dividingBy: 1)
          let dot = point(t + 0.06, abs(cycle), seed + 1)
          air.fill(Path(ellipseIn: CGRect(x: dot.x - 1.2, y: dot.y - 1.2, width: 2.4, height: 2.4)),
                   with: .color(ink.opacity(sin(.pi * abs(cycle)) * 0.5 * level)))
        }
      }
    }
  }
}

/// Integrates air speed over time, easing toward the fan's speed, so changing it doesn't make the air jump.
final class AirClock {
  private(set) var phase = 0.0
  private(set) var speed = 1.0
  private var last: Date?

  func advance(to now: Date, toward target: Double) -> Double {
    let dt = last.map { min(now.timeIntervalSince($0), 0.1) } ?? 0
    last = now
    speed += (target - speed) * min(1, dt * 3)
    phase += dt * speed
    return phase
  }
}
