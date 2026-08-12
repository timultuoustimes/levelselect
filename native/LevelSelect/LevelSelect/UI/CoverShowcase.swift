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
                .scaleEffect(appear ? 1 : 0.35)
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
            withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { appear = true }
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
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { appear = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            isPresented = false
        }
    }
}
