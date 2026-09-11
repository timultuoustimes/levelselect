import SwiftUI

/// Tap a cover on the game page to blow it up into a glossy 3D object you can
/// spin with a finger — it springs back with a wobble on release. Tap the dim
/// backdrop to close.
struct CoverShowcase: View {
    let urlString: String?
    @Binding var isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appear = false
    @State private var drag: CGSize = .zero

    private let size = CGSize(width: 264, height: 350)
    private var yaw: Double { Double(drag.width) / 6 }
    private var pitch: Double { Double(-drag.height) / 6 }

    var body: some View {
        ZStack {
            Color.black.opacity(appear ? 0.72 : 0)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { close() }

            cover
                .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                .rotation3DEffect(.degrees(pitch), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
                // Fades rather than grows. A card that still travels from 35%
                // to full size is the motion, whatever the animation curve.
                .scaleEffect(reduceMotion ? 1 : (appear ? 1 : 0.35))
                .opacity(appear ? 1 : 0)
                .shadow(color: .black.opacity(0.55), radius: 26, x: CGFloat(-yaw) * 0.7, y: 24)
                .gesture(
                    DragGesture()
                        .onChanged { drag = $0.translation }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.75,
                                                  dampingFraction: reduceMotion ? 0.9 : 0.32)) {
                                drag = .zero
                            }
                        }
                )

            VStack {
                Spacer()
                Text("Drag to spin · tap to close")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.bottom, 54)
                    .opacity(appear ? 1 : 0)
            }
        }
        .onAppear {
            // The flag was read at the top of this file and then spent only
            // on drag damping, while the 0.35 → 1 entrance — the largest
            // movement in the app — always ran. Reduce Motion means the
            // spatial change, not the springiness of it.
            if reduceMotion {
                appear = true
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { appear = true }
            }
        }
    }

    private var cover: some View {
        Group {
            if let s = urlString, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: 14))
        .coverGloss(cornerRadius: 14)
        // A specular hotspot that slides with the tilt — the "wet glossy" cue.
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(EllipticalGradient(
                    colors: [.white.opacity(0.4), .clear],
                    center: .init(x: 0.5 - yaw / 55, y: 0.4 + pitch / 55),
                    startRadiusFraction: 0, endRadiusFraction: 0.5))
                .blendMode(.softLight)
                .allowsHitTesting(false)
        }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.14)))
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "gamecontroller.fill").font(.largeTitle).foregroundStyle(.secondary)
        }
    }

    private func close() {
        if reduceMotion {
            appear = false
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { appear = false }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            isPresented = false
        }
    }
}

/// **The showcase's spin, in place.**
///
/// Tim, 2026-09-11: *"can we let them spin the art or logo in place on the mac
/// without opening them up bigger? … having it only hidden through a tap to
/// make it bigger feels like a bummer."* Same tilt and the same springy
/// release as `CoverShowcase`, on the hero's cover and logo where they sit.
///
/// On the Mac a drag has nothing else to do, so it tilts both ways. On a phone
/// or iPad the art sits in the page's scroll, so only a SIDEWAYS drag spins
/// and a vertical one stays the scroll's — the gesture runs alongside the
/// scroll rather than taking it over. A tap still opens the showcase: the
/// drag needs a few points of travel before it begins.
struct SpinInPlace: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(Double(drag.width) / 5),
                              axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .rotation3DEffect(.degrees(Double(-drag.height) / 5),
                              axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            #if os(macOS)
            .gesture(spin)
            #else
            .simultaneousGesture(spin)
            #endif
    }

    private var spin: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let t = value.translation
                #if os(macOS)
                drag = t
                #else
                drag = CGSize(width: abs(t.width) > abs(t.height) ? t.width : 0, height: 0)
                #endif
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.75,
                                      dampingFraction: reduceMotion ? 0.9 : 0.32)) {
                    drag = .zero
                }
            }
    }
}

extension View {
    /// Drag to spin, springing back on release. See `SpinInPlace`.
    func lsSpinInPlace() -> some View { modifier(SpinInPlace()) }
}
