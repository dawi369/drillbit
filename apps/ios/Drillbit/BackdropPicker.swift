import SwiftUI

/// Settings → Background: each backdrop as a little phone, two to a row, the active one outlined in gold.
struct BackdropPickerView: View {
  @AppStorage(Backdrop.storageKey) private var stored = Backdrop.rails.rawValue
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 20) {
        ForEach(Backdrop.allCases) { backdrop in tile(backdrop) }
      }
      .padding(20)
      .frame(maxWidth: 520).frame(maxWidth: .infinity)
    }
    .background(AppPalette.background)
    .containerBackground(AppPalette.background, for: .navigation)
    .navigationTitle("Background")
    .navigationBarTitleDisplayMode(.inline)
    .sensoryFeedback(.selection, trigger: stored)
  }

  private func tile(_ backdrop: Backdrop) -> some View {
    let chosen = (Backdrop(rawValue: stored) ?? .rails) == backdrop
    return Button {
      withAnimation(reduceMotion ? nil : .snappy) { stored = backdrop.rawValue }
    } label: {
      VStack(spacing: 8) {
        BackdropArt(backdrop: backdrop, strength: 2.5)
          .aspectRatio(0.6, contentMode: .fit)
          .clipShape(.rect(cornerRadius: 12))
          .overlay {
            RoundedRectangle(cornerRadius: 12)
              .strokeBorder(chosen ? AppPalette.accent : AppPalette.primary.opacity(0.12), lineWidth: chosen ? 2 : 1)
          }
          .overlay(alignment: .topTrailing) {
            if chosen {
              Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(AppPalette.background, AppPalette.accent)
                .padding(8)
                .transition(.scale.combined(with: .opacity))
            }
          }
          .shadow(color: AppPalette.accent.opacity(chosen ? 0.18 : 0), radius: 12)
        Text(backdrop.title).font(.subheadline.weight(.semibold))
          .foregroundStyle(chosen ? AppPalette.accent : AppPalette.primary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(backdrop.title)
    .accessibilityValue(chosen ? "Selected" : "")
    .accessibilityAddTraits(chosen ? .isSelected : [])
    .accessibilityIdentifier("backdrop-\(backdrop.rawValue)")
  }
}
