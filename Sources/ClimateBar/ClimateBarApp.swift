import SwiftUI

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

struct ACUnit: Identifiable {
  let id: String  // IP
  var name: String
  var online: Bool?  // nil until the first reply
  var on = false
  var target = 24.0
  var indoor: Double?
  var fan = "Auto"
}

@MainActor @Observable
final class Store {
  var units: [ACUnit] = []
  var selected = 0
  var error: String?
  @ObservationIgnored private var devices: [String: MideaAC] = [:]
  @ObservationIgnored private var pending: [String: Task<Void, Never>] = [:]

  init() {
    load()
    // Keep the panel and menu bar label in sync with changes made from the remote or the official app,
    // and periodically re-scan the LAN so ACs that moved (DHCP) or came online are picked up.
    Task {
      var cycle = 0
      while true {
        if cycle % 10 == 0 { await rediscover() }  // on launch, then ~every 5 min
        refreshAll()
        cycle += 1
        try? await Task.sleep(for: .seconds(30))
      }
    }
  }

  /// Re-scan the LAN and move any saved AC to its current IP. Known ACs only —
  /// a brand-new AC needs its token, which comes from onboarding.
  func rediscover() async {
    let found = await Task.detached { Discovery.scan() }.value
    guard !found.isEmpty, var configs = try? Devices.load() else { return }
    var changed = false
    for ac in found {
      guard let i = configs.firstIndex(where: { $0.device_id == ac.deviceID }), configs[i].ip != ac.ip
      else { continue }
      let c = configs[i]
      configs[i] = DeviceConfig(name: c.name, ip: ac.ip, device_id: c.device_id, token: c.token, key: c.key)
      changed = true
    }
    if changed {
      try? Devices.save(configs)
      load()  // rebuild the units + clients at their new IPs
      refreshAll()
    }
  }

  /// No saved ACs yet -> the panel shows onboarding instead of an error.
  var needsOnboarding: Bool { units.isEmpty }

  /// (Re)load the saved devices; a missing file just means "not onboarded yet".
  func load() {
    guard let configs = try? Devices.load() else { units = []; devices = [:]; return }
    units = configs.map { ACUnit(id: $0.ip, name: $0.name) }
    devices = Dictionary(uniqueKeysWithValues: configs.map { ($0.ip, MideaAC($0)) })
    error = nil
  }

  var current: ACUnit {
    units.indices.contains(selected) ? units[selected] : ACUnit(id: "", name: "No ACs", online: false)
  }

  func refreshAll() {
    for unit in units { Task { await refresh(unit.id) } }
  }

  func refresh(_ id: String) async {
    // A command in flight owns the connection (the AC takes one client at a time) and will report back itself.
    guard let device = devices[id], pending[id] == nil else { return }
    let status = try? await device.status()
    guard pending[id] == nil, let i = units.firstIndex(where: { $0.id == id }) else { return }
    if let status { apply(status, at: i) } else { units[i].online = false }
  }

  /// Sends the unit's current panel state to the AC. Rapid changes (dragging the dial) collapse into one command.
  func push(_ id: String) {
    guard let device = devices[id], let unit = units.first(where: { $0.id == id }) else { return }
    pending[id]?.cancel()
    pending[id] = Task {
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      let (on, target, fan) = (unit.on, unit.target, unit.fan)
      let status = try? await device.update {
        $0.power = on
        $0.target = target
        $0.fan = fan
      }
      pending[id] = nil
      if let status, let i = units.firstIndex(where: { $0.id == id }) {
        apply(status, at: i)
      } else {
        await refresh(id)  // failed: show what the AC actually has
      }
    }
  }

  private func apply(_ status: ACStatus, at i: Int) {
    units[i].online = true
    units[i].on = status.power
    units[i].target = status.target
    units[i].fan = status.fan
    units[i].indoor = status.indoor
  }
}

struct PanelView: View {
  @Bindable var store: Store
  @Namespace private var glass

  private var unit: Binding<ACUnit> { $store.units[store.selected] }

  var body: some View {
    if store.needsOnboarding {
      OnboardingView(model: OnboardingModel { _ in store.load() })
    } else {
      panel
    }
  }

  private var panel: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("ClimateBar").font(.headline)
      if let error = store.error {
        Text(error).font(.caption).foregroundStyle(.red)
      }
      switcher
      card
    }
    .padding(14)
    .frame(width: 380)
    // Our own glass instead of the system panel material, tinted by the target temperature.
    .panelGlass(in: .rect(cornerRadius: 18), tint: temperatureTint(store.current))
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
        Circle().fill(item.online == true ? Color.green : .secondary).frame(width: 5, height: 5)
        Text(item.name).fontWeight(index == store.selected ? .semibold : .regular)
        if item.online == false { Image(systemName: "wifi.slash").font(.caption2) }
      }
      .foregroundStyle(item.online == false ? .secondary : .primary)
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
        store.push(ac.id)
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
    GlassBox {
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
                  Color.clear.pillGlass(id: id, in: glass)
                }
              }
          }
          .buttonStyle(.plain)
        }
      }
      .padding(3)
      .panelGlass(in: .capsule)
    }
  }

  private var card: some View {
    let ac = unit.wrappedValue
    return VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(ac.online == nil ? "Connecting…" : ac.online == true ? (ac.on ? "On" : "Off") : "Offline").font(.headline)
        Spacer()
        powerButton(ac)
      }
      ACHero(running: ac.on, readout: "\(Int(ac.target))", fan: ac.fan)
      Group {
        ThermostatDial(
          target: Binding(
            get: { unit.target.wrappedValue },
            set: {
              unit.target.wrappedValue = $0
              store.push(ac.id)
            }), indoor: ac.indoor)
        fanControl(ac)
      }
      .disabled(!ac.on)
      .opacity(ac.on ? 1 : 0.4)
    }
    .padding(16)
    .panelGlass(in: .rect(cornerRadius: 14))
    .disabled(ac.online != true)
  }

  private func powerButton(_ ac: ACUnit) -> some View {
    Button {
      withAnimation(.bouncy) { unit.on.wrappedValue.toggle() }
      store.push(ac.id)
    } label: {
      Image(systemName: "power")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(ac.on ? Color.black : .primary)
        .frame(width: 38, height: 38)
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .panelGlass(in: .circle, tint: ac.on ? .white : nil, interactive: true)
  }
}
