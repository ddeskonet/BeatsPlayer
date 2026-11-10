import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var p: Player
    @State private var importing = false
    @State private var scrubbing = false
    @State private var scrub = 0.0

    var body: some View {
        ZStack {
            AnimatedBackground(colors: p.colors).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { importing = true } label: {
                        Image(systemName: "plus").font(.system(size: 17, weight: .semibold))
                            .frame(width: 38, height: 38).background(.ultraThinMaterial, in: Circle())
                    }
                }.frame(height: 44)

                cover
                VStack(spacing: 3) {
                    Text(p.current?.title ?? "Добавь трек").font(.system(size: 21, weight: .bold)).lineLimit(1)
                    Text(p.current?.artist ?? "Нажми + сверху").font(.system(size: 16)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                }.padding(.top, 18)

                Spacer(minLength: 10)
                HStack(spacing: 11) {
                    ForEach(0..<5, id: \.self) { i in
                        Capsule().fill(.white.opacity(0.92)).frame(width: 24)
                            .frame(height: 200 * CGFloat(0.08 + 0.92 * min(1, p.levels[i])))
                            .shadow(color: .white.opacity(0.3), radius: 14)
                    }
                }.frame(height: 200)
                Spacer(minLength: 10)

                VStack(spacing: 4) {
                    Slider(value: Binding(get: { scrubbing ? scrub : p.time }, set: { scrub = $0 }),
                           in: 0...p.duration) { e in
                        scrubbing = e
                        if !e { p.seek(scrub) }
                    }.tint(.white)
                    HStack { Text(fmt(scrubbing ? scrub : p.time)); Spacer(); Text(fmt(p.duration)) }
                        .font(.system(size: 12).monospacedDigit()).foregroundStyle(.white.opacity(0.62))
                }

                HStack(spacing: 14) {
                    ctl("gobackward.10", 24, 0.7) { p.skip(-10) }
                    ctl("backward.fill", 32, 1) { p.prev() }
                    ctl(p.isPlaying ? "pause.fill" : "play.fill", 56, 1) { p.toggle() }
                    ctl("forward.fill", 32, 1) { p.next() }
                    ctl("goforward.10", 24, 0.7) { p.skip(10) }
                }.padding(.vertical, 6)

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.wave.2.fill").frame(width: 24)
                        Slider(value: Binding(get: { Double(p.volume) }, set: { p.volume = Float($0) })).tint(.white)
                    }.frame(height: 46)
                    Divider().overlay(.white.opacity(0.15))
                    HStack(spacing: 12) {
                        Text("808").font(.system(size: 13, weight: .bold)).frame(width: 24)
                        Slider(value: Binding(get: { Double(p.bass) }, set: { p.bass = Float($0) })).tint(.white)
                    }.frame(height: 46)
                }
                .padding(.horizontal, 16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            }
            .padding(.horizontal, 24).padding(.bottom, 8)
            .foregroundStyle(.white)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { p.add(urls) }
        }
    }

    var cover: some View {
        Group {
            if let img = p.current?.cover {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [p.colors[0], p.colors[2]], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: 54)).foregroundStyle(.white.opacity(0.9)))
            }
        }
        .frame(width: 230, height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 54, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 30, y: 14)
        .scaleEffect(1 + CGFloat(p.levels[0]) * 0.04)
    }

    func ctl(_ icon: String, _ size: CGFloat, _ op: Double, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: icon).font(.system(size: size)).opacity(op).frame(width: 60, height: 60)
        }
    }
    func fmt(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}

struct AnimatedBackground: View {
    let colors: [Color]
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                ZStack {
                    colors[1]
                    ForEach(0..<3, id: \.self) { i in
                        let d = Double(i)
                        Circle().fill(colors[i]).frame(width: g.size.width * 1.4)
                            .offset(x: CGFloat(sin(t / (5 + d * 2) + d * 2)) * g.size.width * 0.5,
                                    y: CGFloat(cos(t / (6 + d * 2.5) + d)) * g.size.height * 0.35)
                            .blur(radius: 70)
                    }
                    Color.black.opacity(0.22)
                }.frame(width: g.size.width, height: g.size.height).clipped()
            }
        }
    }
}
