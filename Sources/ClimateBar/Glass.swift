import SwiftUI

// Liquid Glass is macOS 26 only. These shims use it when present and fall back
// to a frosted `.regularMaterial` below it, so the app runs on macOS 15+.

extension View {
  /// Glass on 26+, frosted material (plus an optional colour wash) below it.
  @ViewBuilder
  func panelGlass(in shape: some Shape, tint: Color? = nil, interactive: Bool = false) -> some View {
    if #available(macOS 26, *) {
      glassEffect(glassStyle(tint: tint, interactive: interactive), in: shape)
    } else {
      background {
        ZStack {
          shape.fill(.regularMaterial)
          if let tint { shape.fill(tint.opacity(0.22)) }
        }
      }
    }
  }

  /// The morphing selection pill in a segmented control; the morph is 26-only.
  @ViewBuilder
  func pillGlass(id: String, in namespace: Namespace.ID) -> some View {
    if #available(macOS 26, *) {
      glassEffect(.clear.interactive(), in: .capsule).glassEffectID(id, in: namespace)
    } else {
      background(.regularMaterial, in: .capsule)
    }
  }
}

@available(macOS 26, *)
private func glassStyle(tint: Color?, interactive: Bool) -> Glass {
  var g: Glass = .clear
  if let tint { g = g.tint(tint) }
  if interactive { g = g.interactive() }
  return g
}

/// `GlassEffectContainer` on 26+, a plain pass-through below it.
struct GlassBox<Content: View>: View {
  @ViewBuilder var content: () -> Content
  var body: some View {
    if #available(macOS 26, *) { GlassEffectContainer(content: content) }
    else { content() }
  }
}
