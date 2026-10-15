import SwiftUI

@main
struct ClimateBarApp: App {
  @State private var store = Store()

  var body: some Scene {
    MenuBarExtra {
      PanelView(store: store)
    } label: {
      // Live state in the menu bar: snowflake plus the target while running.
      let ac = store.current
      if ac.on {
        HStack(spacing: 4) {
          Image(systemName: "snowflake")
          Text("\(Int(ac.target))°")
        }
      } else {
        Image(systemName: "snowflake")
      }
    }
    .menuBarExtraStyle(.window)
  }
}

// Placeholder state until the Midea protocol is wired in.
struct ACUnit: Identifiable {
  let id: String
  var name: String
  var online: Bool
  var on = false
  var target = 24.0
  var indoor = 28.0
  var fan = "Auto"
}

@Observable
final class Store {
  var units = [
    ACUnit(id: "192.168.1.101", name: "Office", online: true, on: true),
    ACUnit(id: "192.168.1.100", name: "AC 2", online: false),
  ]
  var selected = 0

  var current: ACUnit { units[selected] }
}

struct PanelView: View {
  @Bindable var store: Store
  @Namespace private var glass

  private var unit: Binding<ACUnit> { $store.units[store.selected] }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("ClimateBar").font(.headline)
      switcher
      card
    }
    .padding(14)
    .frame(width: 380)
    // Our own glass instead of the system panel material, tinted by the target temperature.
    .glassEffect(.clear.tint(temperatureTint(store.current)), in: .rect(cornerRadius: 18))
    .animation(.smooth(duration: 0.6), value: store.current.target)
    .animation(.smooth(duration: 0.6), value: store.current.on)
    .containerBackground(.clear, for: .window)
  }

  /// Icy blue at 16°, neutral around 23°, warm amber at 30°; untinted while off.
  private func temperatureTint(_ ac: ACUnit) -> Color {
    guard ac.on else { return .clear }
    let warmth = (ac.target - 16) / 14  // 0…1
    return warmth < 0.5
      ? Color.cyan.opacity((0.5 - warmth) * 2 * 0.35)
      : Color.orange.opacity((warmth - 0.5) * 2 * 0.35)
  }

  private var switcher: some View {
    glassSegments(store.units.indices.map { $0 }, selected: store.selected, id: "tab") { index in
      store.selected = index
    } label: { index in
      let item = store.units[index]
      HStack(spacing: 6) {
        Circle().fill(item.online ? Color.green : .secondary).frame(width: 5, height: 5)
        Text(item.name).fontWeight(index == store.selected ? .semibold : .regular)
        if !item.online { Image(systemName: "wifi.slash").font(.caption2) }
      }
      .foregroundStyle(item.online ? .primary : .secondary)
    }
  }

  private static let fanSpeeds = ["Auto", "Low", "Medium", "High"]

  private func fanControl(_ ac: ACUnit) -> some View {
    HStack(spacing: 10) {
      // Spins while running, faster at higher speeds.
      Image(systemName: "fan")
        .font(.title3)
        .symbolEffect(
          .rotate, options: .repeat(.continuous).speed(["Low": 0.5, "High": 2][ac.fan] ?? 1),
          isActive: ac.on
        )
        .frame(width: 30)
      glassSegments(Self.fanSpeeds, selected: ac.fan, id: "fan") { speed in
        unit.fan.wrappedValue = speed
      } label: { speed in
        Text(speed).font(.callout).fontWeight(speed == ac.fan ? .semibold : .regular)
      }
    }
  }

  /// Clear glass capsule; the selected option is a glass pill that morphs across to the new choice.
  private func glassSegments<Option: Hashable, Label: View>(
    _ options: [Option], selected current: Option, id: String,
    select: @escaping (Option) -> Void, @ViewBuilder label: @escaping (Option) -> Label
  ) -> some View {
    GlassEffectContainer {
      HStack(spacing: 2) {
        ForEach(options, id: \.self) { option in
          Button {
            withAnimation(.snappy) { select(option) }
          } label: {
            label(option)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 7)
              .contentShape(.capsule)
              .background {
                if option == current {
                  Color.clear
                    .glassEffect(.clear.interactive(), in: .capsule)
                    .glassEffectID(id, in: glass)
                }
              }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(3)
      .glassEffect(.clear, in: .capsule)
    }
  }

  private var card: some View {
    let ac = unit.wrappedValue
    return VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(ac.online ? (ac.on ? "On" : "Off") : "Offline").font(.headline)
        Spacer()
        powerButton(ac)
      }
      ACHero(running: ac.on, readout: "\(Int(ac.target))", fan: ac.fan)
      Group {
        ThermostatDial(target: unit.target, indoor: ac.indoor)
        fanControl(ac)
      }
      .disabled(!ac.on)
      .opacity(ac.on ? 1 : 0.4)
    }
    .padding(16)
    .glassEffect(.clear, in: .rect(cornerRadius: 14))
    .disabled(!ac.online)
  }

  private func powerButton(_ ac: ACUnit) -> some View {
    Button {
      withAnimation(.bouncy) { unit.on.wrappedValue.toggle() }
    } label: {
      Image(systemName: "power")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(ac.on ? Color.black : .primary)
        .frame(width: 38, height: 38)
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .glassEffect(ac.on ? .clear.tint(.white).interactive() : .clear.interactive(), in: .circle)
  }
}
