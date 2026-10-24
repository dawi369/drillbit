import ClerkKit
import SwiftUI

/// The first screen, two pages: why this round matters, then Bit and a 20-second taste of the product.
/// Sign-in waits until the first question.
struct WelcomeView: View {
  @Bindable var model: AppModel
  var start: () -> Void
  @State private var page = 0
  @State private var storyDone = false
  @State private var exampleDone = false
  @State private var glow = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    // Hand-built pager: the page turns only from its own arrow, and nothing clips a page's top edge.
    ZStack {
      if page == 0 {
        SeparatorSlide(active: true, done: { storyDone = true }, next: { withAnimation(DrillbitMotion.page) { page = 1 } })
          .transition(.asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .leading).combined(with: .opacity)))
      } else {
        TasteSlide(active: true) { exampleDone = true }
          .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .trailing)))
      }
    }
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
    // Bit's glow is drawn over the pager, not inside a page, so neither the page nor the top edge can clip it.
    .overlayPreferenceValue(BitGlowKey.self) { anchor in
      GeometryReader { proxy in
        if let anchor, page == 1 {
          let frame = proxy[anchor]
          BitGlow(color: AppPalette.action, opacity: 0.22)
            .frame(width: frame.width * 2.2, height: frame.width * 2.2)
            .scaleEffect(glow ? 1.25 : 0.9)
            .opacity(glow ? 1 : 0.55)
            .position(x: frame.midX, y: frame.midY)
            .allowsHitTesting(false)
        }
      }
      .ignoresSafeArea()
    }
    .onAppear {
      guard !reduceMotion else { glow = true; return }
      withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) { glow = true }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      // The way in fades up once the example has made its point.
      if page == 1, exampleDone {
        VStack(spacing: 0) {
          AppPalette.hairline.frame(height: 1)
          Button("Get started", action: start)
            .buttonStyle(PracticeButtonStyle())
            .frame(maxWidth: 560).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("getStarted")
        }
        .background(AppPalette.background)
        .transition(.opacity)
      }
    }
    .animation(reduceMotion ? nil : DrillbitMotion.page, value: exampleDone)
    .animation(reduceMotion ? nil : DrillbitMotion.page, value: page)
  }
}

/// Page one: the round that separates the candidates who get the offer, shown as the loop itself.
/// Bit arrives at the end with the pitch; tapping him is the way forward.
private struct SeparatorSlide: View {
  var active: Bool
  var done: () -> Void
  var next: () -> Void
  @State private var headlineDone = false
  @State private var lit = 0
  @State private var railDrawn = false
  @State private var bitIn = false
  @State private var cheers = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private static let rounds = ["Screen", "Coding", "System design", "Behavioral"]
  private static let spotlight = 2
  /// Half the widest label, so "Behavioral" can centre under the last stop without leaving the page.
  private static let railInset: CGFloat = 36

  /// Sans for the setup, the serif wordmark face in amber for the word that matters. One entry per row, so the
  /// serif's taller line box can't open a gap above the last line.
  private static var headlineLines: [AttributedString] {
    var last = AttributedString("gets you ")
    var offer = AttributedString("hired.")
    offer.font = .custom("Literata", fixedSize: 36).weight(.medium)
    offer.foregroundColor = AppPalette.accent
    last.append(offer)
    return [AttributedString("The coding round"), AttributedString("gets you a callback."), AttributedString("The design round"), last]
  }
  /// The serif's ascender is taller than SF's, which would drop the last row's baseline; lift it back by the difference.
  private static var serifLift: CGFloat {
    let serif = UIFont(name: "Literata-Regular", size: 36)?.ascender ?? 0
    let sans = UIFont.systemFont(ofSize: 38, weight: .semibold).ascender
    return max(0, serif - sans)
  }

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        // Three beats, top to bottom: the claim, the loop, then Bit with the pitch. Each keeps its place from the start.
        VStack(alignment: .leading, spacing: 0) {
          RevealText(text: Self.headlineLines.map { String($0.characters) }.joined(separator: "\n"), lines: Self.headlineLines, lineHeight: 46, lineLifts: [0, 0, 0, Self.serifLift],
                     font: .system(size: 38, weight: .semibold), tracking: -1.1, active: active, delay: 0.5, rate: 33) { headlineDone = true }
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("separatorHeadline")
          Spacer(minLength: 36)
          loop.opacity(headlineDone ? 1 : 0)
          Spacer(minLength: 36)
          pitch.opacity(bitIn ? 1 : 0).offset(y: bitIn ? 0 : 10)
          HStack {
            Spacer()
            Button(action: next) {
              HStack(spacing: 4) {
                Text("Next").font(.subheadline.weight(.medium))
                Image(systemName: "arrow.right").font(.caption.weight(.bold))
              }
              .foregroundStyle(AppPalette.secondary)
              .padding(.vertical, 8).padding(.leading, 8)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcomeNext")
          }
          .padding(.top, 12)
          .opacity(headlineDone ? 1 : 0)
        }
        .frame(maxWidth: 560, alignment: .topLeading)
        .padding(.horizontal, 24).padding(.top, 48).padding(.bottom, 72)
        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .animation(reduceMotion ? nil : DrillbitMotion.page, value: headlineDone)
    .animation(reduceMotion ? nil : DrillbitMotion.page, value: bitIn)
    .task(id: headlineDone) {
      guard headlineDone else { return }
      if reduceMotion { railDrawn = true; lit = Self.rounds.count + 1; bitIn = true; done(); return }
      withAnimation(.easeInOut(duration: 0.9)) { railDrawn = true }
      for step in 1...(Self.rounds.count + 1) {
        // The rail draws itself first; the stops light along it, then the design round takes the spotlight.
        try? await Task.sleep(for: .milliseconds(step == 1 ? 1000 : step == Self.rounds.count + 1 ? 600 : 380))
        guard !Task.isCancelled else { return }
        withAnimation(.smooth(duration: 0.45)) { lit = step }
      }
      try? await Task.sleep(for: .milliseconds(700))
      guard !Task.isCancelled else { return }
      bitIn = true
      done()
      // Bit lands, takes a beat and cheers; the arrow at the foot is the way on.
      try? await Task.sleep(for: .milliseconds(1400))
      guard !Task.isCancelled else { return }
      cheers += 1
    }
  }

  /// The loop as a pipeline: a rail draws itself left to right, the four rounds light along it, and the design
  /// round swells into the spotlight with its line underneath.
  private var loop: some View {
    let count = Self.rounds.count
    let spotOn = lit > count
    return VStack(alignment: .leading, spacing: 18) {
      GeometryReader { proxy in
        let width = proxy.size.width - 2 * Self.railInset
        let step = width / CGFloat(count - 1)
        ZStack(alignment: .leading) {
          Capsule().fill(AppPalette.hairline).frame(width: width, height: 2)
          Capsule().fill(AppPalette.primary.opacity(0.4))
            .frame(width: railDrawn ? width : 0, height: 2)
          // Lit portion of the rail follows the stops.
          Capsule().fill(AppPalette.primary.opacity(0.7))
            .frame(width: min(CGFloat(max(lit - 1, 0)), CGFloat(count - 1)) * step, height: 2)
          ForEach(0..<count, id: \.self) { index in
            let on = lit > index
            let spot = index == Self.spotlight && spotOn
            Circle()
              .fill(spot ? AppPalette.action : on ? AppPalette.primary : AppPalette.inset)
              .overlay { Circle().strokeBorder(on ? Color.clear : AppPalette.hairline, lineWidth: 1) }
              .frame(width: spot ? 18 : 12, height: spot ? 18 : 12)
              .shadow(color: AppPalette.action.opacity(spot ? 0.6 : 0), radius: 12)
              .scaleEffect(on ? 1 : 0.6)
              .opacity(railDrawn ? 1 : 0)
              .position(x: CGFloat(index) * step, y: proxy.size.height / 2)
          }
        }
        .padding(.horizontal, Self.railInset)
      }
      .frame(height: 24)
      // Each label is centred on its stop; the rail is inset so the end labels have room to centre too.
      GeometryReader { proxy in
        let step = (proxy.size.width - 2 * Self.railInset) / CGFloat(count - 1)
        ForEach(0..<count, id: \.self) { index in
          let on = lit > index
          let spot = index == Self.spotlight && spotOn
          Text(Self.rounds[index])
            .font(.caption.weight(spot ? .semibold : .medium))
            .foregroundStyle(spot ? AppPalette.accent : on ? AppPalette.primary.opacity(0.85) : AppPalette.secondary)
            .lineLimit(1).fixedSize()
            .opacity(on ? 1 : 0.5)
            .position(x: Self.railInset + CGFloat(index) * step, y: proxy.size.height / 2)
        }
      }
      .frame(height: 18)
      VStack(spacing: 4) {
        Text("System design")
          .font(.title3.weight(.semibold)).foregroundStyle(AppPalette.primary)
        Text("The one most people walk into cold.")
          .font(.subheadline).foregroundStyle(AppPalette.accent)
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .opacity(spotOn ? 1 : 0)
      .offset(y: spotOn ? 0 : 6)
      .padding(.top, 4)
    }
    .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: lit)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: railDrawn)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("A typical interview loop: phone screen, coding, system design, behavioral. System design is the one most people walk into cold.")
  }

  /// Bit shows up with the pitch, cheers, and takes you through.
  private var pitch: some View {
    HStack(alignment: .center, spacing: 16) {
      BitView(mood: .content, greets: true, cheers: cheers)
        .frame(width: 72, height: 80)
        .background { BitGlow(color: AppPalette.action, opacity: 0.2).scaleEffect(1.7) }
      Text("Drillbit is the complete package for that round.")
        .font(.title3.weight(.semibold)).foregroundStyle(AppPalette.primary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.top, 8)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("separatorBit")
  }
}

/// Page two: Bit, the promise, and the example that plays itself.
private struct TasteSlide: View {
  var active: Bool
  var finished: () -> Void
  @State private var mood = BitMood.idle
  @State private var cheers = 0
  @State private var headlineDone = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          // Bit first; his glow is drawn by the pager above every page. The words arrive a beat after.
          BitView(mood: mood, greets: true, cheers: cheers)
            .frame(width: 92, height: 104)
            .anchorPreference(key: BitGlowKey.self, value: .bounds) { $0 }
          RevealText(text: "Grills you like\nthe real one.\nWants you to pass.", font: .system(size: 40, weight: .semibold),
                     tracking: -1.2, lineSpacing: -2, active: active, delay: 0.4, rate: 29) { headlineDone = true }
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("welcomeHeadline")
          if headlineDone {
            GrillExample(mood: $mood, cheers: $cheers, finished: finished)
              .transition(.opacity)
          }
        }
        .frame(maxWidth: 560, alignment: .topLeading)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 72)
        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
      }
      // Bit sits in the top corner and hops when he greets; the scroll view must not clip the hop.
      .scrollClipDisabled()
      .scrollBounceBehavior(.basedOnSize)
    }
    .animation(reduceMotion ? nil : DrillbitMotion.page, value: headlineDone)
  }
}

/// Sign in, then the invite. Shown once, after setup, right before the first question.
struct SignInView: View {
  @Bindable var model: AppModel
  @State private var invite = ""
  @State private var signingIn = false
  @FocusState private var inviteFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let inviting = model.bootstrap != nil
    let code = invite.trimmingCharacters(in: .whitespacesAndNewlines)
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 16) {
          BitView(mood: .content).frame(width: 76, height: 84).signalEntrance(0)
          VStack(spacing: 8) {
            Text(inviting ? "One last step." : "Your question’s ready.")
              .font(.title2.weight(.semibold))
            Text(inviting ? "Enter your invite code to open it." : "Sign in so your reps and feedback are kept.")
              .font(.subheadline).foregroundStyle(AppPalette.secondary)
          }
          .multilineTextAlignment(.center)
          .id(inviting)
          .transition(.opacity)
          .signalEntrance(1)
        }
        .animation(reduceMotion ? nil : DrillbitMotion.reveal, value: inviteFocused)
        .frame(maxWidth: 400).padding(24).frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }
      .scrollBounceBehavior(.basedOnSize)
    }
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
    // Pinned so the field and its action always sit above the keyboard.
    .safeAreaInset(edge: .bottom, spacing: 0) {
      VStack(spacing: 16) {
        if inviting {
          TextField("Invite code", text: $invite)
            .font(.body.monospaced())
            .keyboardType(.asciiCapable)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .submitLabel(.go).focused($inviteFocused)
            .onSubmit { if !code.isEmpty { redeem(code) } }
            .signalInset(padding: 16)
          Button { redeem(code) } label: {
            HStack(spacing: 8) {
              if signingIn { ProgressView().controlSize(.small).tint(AppPalette.actionInk).transition(.iconPop) }
              Text("Open my question")
            }
          }
          .buttonStyle(PracticeButtonStyle()).disabled(code.isEmpty || signingIn)
          .accessibilityLabel(signingIn ? "Checking invite" : "Open my question")
        } else {
          VStack(spacing: 12) {
            Button { authenticate { await model.signIn() } } label: { Label("Sign in with Apple", systemImage: AppIcon.apple.rawValue) }.buttonStyle(PracticeButtonStyle())
            Button("Continue with Google") { authenticate { await model.signIn(provider: .google) } }.buttonStyle(PracticeButtonStyle(secondary: true))
            Button("Continue with GitHub") { authenticate { await model.signIn(provider: .github) } }.buttonStyle(PracticeButtonStyle(secondary: true))
          }
          // Reserve the row so buttons never shift when work starts.
          ProgressView("Signing in…")
            .opacity(signingIn ? 1 : 0)
            .accessibilityHidden(!signingIn)
        }
      }
      .disabled(signingIn)
      .transition(.opacity)
      .animation(DrillbitMotion.page, value: inviting)
      .animation(DrillbitMotion.fast, value: signingIn)
      .frame(maxWidth: 400).padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 16)
      .frame(maxWidth: .infinity)
      .background(AppPalette.background)
    }
    .task(id: inviting) { if inviting { inviteFocused = true } }
  }

  private func redeem(_ code: String) {
    inviteFocused = false
    authenticate { await model.redeem(code) }
  }
  private func authenticate(_ operation: @escaping @MainActor () async -> Void) {
    guard !signingIn else { return }; signingIn = true
    Task { defer { signingIn = false }; await operation() }
  }
}

/// Writes fixed copy out glyph by glyph on the finished text's layout, so a line never reflows as it fills.
struct RevealText: View {
  let text: String
  /// The same characters with per-run styling, when one word wants a different face.
  var styled: AttributedString? = nil
  /// Rows laid out one per line at a fixed height, sharing one cursor; `text` must be these joined by "\n".
  var lines: [AttributedString]? = nil
  var lineHeight: CGFloat? = nil
  /// Per-row upward nudge, for a row whose font has a taller ascender than the others.
  var lineLifts: [CGFloat] = []
  var font: Font
  var tracking: CGFloat = 0
  var lineSpacing: CGFloat = 0
  var color: Color = AppPalette.primary
  var caret = false
  /// Off-screen pages wait; the clock starts when the page is in view.
  var active = true
  var delay: TimeInterval = 0
  /// Characters per second.
  var rate: Double = 32
  var done: () -> Void = {}
  @State private var start = Date()
  @State private var finished = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// A beat at the end of each sentence, so the lines read as spoken rather than typed.
  private static let sentencePause = 0.25
  /// Where each new sentence starts, as glyph indices: the renderer never sees newlines.
  private var breaks: [Int] {
    var stops: [Int] = [], newlines = 0
    for (offset, character) in text.enumerated() {
      if character == "\n" { newlines += 1 }
      if ".?!".contains(character), offset < text.count - 1 { stops.append(offset + 1 - newlines) }
    }
    return stops
  }
  private var glyphCount: Int { text.count { $0 != "\n" } }
  /// The cursor runs in renderer units: every sentence is its glyphs plus one fade edge, so a rest never lands
  /// with glyphs half-faded.
  private func position(at seconds: TimeInterval) -> Double {
    var remaining = seconds, cursor = 0.0
    for (sentence, stop) in breaks.enumerated() {
      let rest = Double(stop) + Double(sentence + 1) * RevealRenderer.edge
      let run = (rest - cursor) / rate
      if remaining <= run { return cursor + remaining * rate }
      remaining -= run; cursor = rest
      if remaining <= Self.sentencePause { return cursor }
      remaining -= Self.sentencePause
    }
    return cursor + remaining * rate
  }
  var body: some View {
    let breaks = breaks
    let target = Double(glyphCount) + Double(breaks.count + 1) * RevealRenderer.edge
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: finished)) { timeline in
      let elapsed = max(0, timeline.date.timeIntervalSince(start) - delay)
      let shown = reduceMotion ? target : !active ? 0 : min(target, position(at: elapsed))
      // Between sentences the cursor rests; the caret blinks so the rest reads as a breath, not a stall.
      let resting = active && shown < target && position(at: elapsed + 0.05) == shown
      let caretLevel: Double = !caret || shown >= target ? 0 : resting ? (sin(elapsed * 2 * .pi / 0.9) > 0 ? 1 : 0.2) : 1
      Group {
        if let lines {
          // Each row's glyph start, plus one edge per sentence that ended before it, in the shared cursor's units.
          let starts = lines.indices.map { index in lines[..<index].reduce(0) { $0 + $1.characters.count } }
          VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.indices, id: \.self) { index in
              let start = starts[index], length = lines[index].characters.count
              let origin = Double(start) + Double(breaks.count { $0 <= start }) * RevealRenderer.edge
              Text(lines[index])
                .font(font).tracking(tracking)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .textRenderer(RevealRenderer(shown: shown - origin, caret: 0, caretColor: AppPalette.accent, motion: !reduceMotion,
                                             breaks: breaks.filter { $0 > start && $0 < start + length }.map { $0 - start }))
                .offset(y: -(index < lineLifts.count ? lineLifts[index] : 0))
                .frame(height: lineHeight, alignment: .topLeading)
            }
          }
        } else {
          Text(styled ?? AttributedString(text))
            .font(font).tracking(tracking).lineSpacing(lineSpacing)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .textRenderer(RevealRenderer(shown: shown, caret: caretLevel, caretColor: AppPalette.accent, motion: !reduceMotion, breaks: breaks))
        }
      }
        .onChange(of: shown >= target, initial: true) { _, complete in
          guard complete, !finished else { return }
          finished = true
          done()
        }
    }
    .accessibilityLabel(text)
    .onChange(of: active) { _, now in if now { start = .now } }
  }
}


/// Welcome's example: one short grilling that plays itself, laid out the way a rep reads inside the app.
/// Scripted and local; no model call, no score. Bit above reacts to the exchange.
struct GrillExample: View {
  @Binding var mood: BitMood
  @Binding var cheers: Int
  var finished: () -> Void = {}
  @State private var shown = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private struct Turn { var you: Bool; var text: String; var mood: BitMood }
  private static let turns: [Turn] = [
    Turn(you: false, text: "Your push to their phone timed out. Now what?", mood: .idle),
    Turn(you: true, text: "Retry it.", mood: .thinking),
    Turn(you: false, text: "It went out the first time. Their phone just buzzed twice. How do you stop that?", mood: .concerned),
    Turn(you: true, text: "Send it with the same request ID. The server skips the duplicate.", mood: .thinking),
    Turn(you: false, text: "Yep. That’s an idempotency key. See, you knew that.", mood: .content),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(Array(Self.turns.enumerated().prefix(shown)), id: \.offset) { index, turn in
        row(index, turn)
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel((turn.you ? "You: " : "Interviewer: ") + turn.text)
          .accessibilityIdentifier("exampleTurn-\(index)")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(minHeight: 240, alignment: .top)
    .accessibilityElement(children: .contain)
    .sensoryFeedback(trigger: shown) { _, new in new == 3 ? .warning : new == Self.turns.count ? .success : nil }
    .task { await show(0, after: 400) }
  }

  /// The same two-line shape as a turn in a rep: who spoke, then what they said.
  private func row(_ index: Int, _ turn: Turn) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      InterviewRowLabel(text: turn.you ? "You" : "Interviewer")
      RevealText(text: turn.text, font: .body, caret: !turn.you, rate: turn.you ? 48 : 33) {
        guard index == shown - 1 else { return }
        if index == Self.turns.count - 1 { cheers += 1; finished() }
        else { Task { await show(index + 1, after: turn.you ? 700 : 900) } }
      }
    }
  }

  private func show(_ index: Int, after milliseconds: Int) async {
    guard index < Self.turns.count, shown == index else { return }
    if !reduceMotion { try? await Task.sleep(for: .milliseconds(milliseconds)) }
    guard !Task.isCancelled, shown == index else { return }
    withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0)) { shown = index + 1 }
    mood = Self.turns[index].mood
  }
}

/// Where Bit sits on the taste page, so the pager can draw his glow above everything.
struct BitGlowKey: PreferenceKey {
  static let defaultValue: Anchor<CGRect>? = nil
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

/// The soft light behind Bit. A radial falloff shaped like a blurred disc, without the per-frame blur pass a
/// `.blur` would cost while it pulses.
struct BitGlow: View {
  let color: Color
  var opacity: Double
  var body: some View {
    GeometryReader { proxy in
      Circle().fill(RadialGradient(stops: [
        .init(color: color.opacity(opacity), location: 0),
        .init(color: color.opacity(opacity * 0.92), location: 0.38),
        .init(color: color.opacity(opacity * 0.55), location: 0.58),
        .init(color: color.opacity(opacity * 0.2), location: 0.78),
        .init(color: color.opacity(0), location: 1),
      ], center: .center, startRadius: 0, endRadius: min(proxy.size.width, proxy.size.height) / 2))
    }
    .aspectRatio(1, contentMode: .fit)
  }
}
