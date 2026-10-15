import SwiftUI

// First-launch onboarding: sign in to the Midea cloud once, discover the ACs on
// the LAN, fetch + verify each one's token/key, and save them for the app. After
// this the app never touches the cloud again.

@MainActor @Observable
final class OnboardingModel {
  enum Phase: Equatable { case form, working(String), failed(String) }

  var email = ""
  var password = ""
  var phase: Phase = .form

  /// Called with the saved configs when onboarding succeeds, so the Store reloads.
  let onDone: ([DeviceConfig]) -> Void
  init(onDone: @escaping ([DeviceConfig]) -> Void) { self.onDone = onDone }

  var busy: Bool { if case .working = phase { return true } else { return false } }

  func start() {
    let (account, password) = (email.trimmingCharacters(in: .whitespaces), password)
    guard !account.isEmpty, !password.isEmpty else {
      phase = .failed("Enter your Midea e-mail and password.")
      return
    }
    phase = .working("Signing in…")
    Task { await run(account: account, password: password) }
  }

  private func run(account: String, password: String) async {
    do {
      let cloud = MideaCloudClient(account: account, password: password)
      try await cloud.login()

      phase = .working("Looking for ACs on your network…")
      let found = await Task.detached { Discovery.scan() }.value
      if found.isEmpty {
        phase = .failed("No ACs found. Make sure they're on the same Wi-Fi as this Mac.")
        return
      }

      var saved: [DeviceConfig] = []
      for ac in found {
        phase = .working("Setting up \(ac.ip)…")
        for cand in try await cloud.token(for: ac.deviceID) {
          let cfg = DeviceConfig(
            name: "AC @ \(ac.ip)", ip: ac.ip, device_id: ac.deviceID,
            token: cand.token, key: cand.key)
          // The right key is the one the AC actually accepts over the LAN.
          if (try? await MideaAC(cfg).status()) != nil {
            saved.append(cfg)
            break
          }
        }
      }

      guard !saved.isEmpty else {
        phase = .failed("Signed in, but none of the ACs accepted a key from this "
          + "account. Use the account that added them in the Midea app.")
        return
      }
      try Devices.save(saved)
      onDone(saved)
    } catch {
      phase = .failed((error as? CloudError)?.errorDescription ?? "\(error)")
    }
  }
}

struct OnboardingView: View {
  @Bindable var model: OnboardingModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Connect your ACs").font(.headline)
      Text("Sign in with your Midea account once. ClimateBar fetches your ACs' "
        + "keys and then talks to them only over your local network.")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

      TextField("Midea e-mail", text: $model.email)
        .textContentType(.username).disableAutocorrection(true)
      SecureField("Password", text: $model.password)
        .textContentType(.password).onSubmit { model.start() }

      if case .working(let message) = model.phase {
        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(message).font(.caption) }
      } else if case .failed(let message) = model.phase {
        Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }

      Button(action: model.start) {
        Text(model.busy ? "Working…" : "Find my ACs").frame(maxWidth: .infinity).padding(.vertical, 6)
      }
      .buttonStyle(.borderedProminent)
      .disabled(model.busy)
    }
    .textFieldStyle(.roundedBorder)
    .padding(16)
    .frame(width: 340)
    .glassEffect(.clear, in: .rect(cornerRadius: 14))
  }
}
