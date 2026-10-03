import SwiftUI

/// Bit asks a setup question. The bubble is the screen's heading, so the screen reads fully without Bit.
struct BitAsks: View {
  let question: String
  var cheers = 0
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      if !typeSize.isAccessibilitySize {
        BitView(cheers: cheers).frame(width: 76, height: 84)
      }
      Text(question)
        .font(.title2.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
          ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12).fill(AppPalette.inset)
            if !typeSize.isAccessibilitySize {
              CalloutPointer().fill(AppPalette.inset)
                .frame(width: 16, height: 8)
                .rotationEffect(.degrees(-90))
                .offset(x: -12)
            }
          }
        }
        .accessibilityAddTraits(.isHeader)
    }
  }
}

/// The small tip on a bubble's edge, drawn pointing up.
private struct CalloutPointer: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.midX - 2, y: rect.minY + 1.5))
    path.addQuadCurve(to: CGPoint(x: rect.midX + 2, y: rect.minY + 1.5), control: CGPoint(x: rect.midX, y: rect.minY - 0.5))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

struct PracticeAreaGroupRow: View {
  let area: PracticeAreaGroup
  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: area.symbol).font(.system(size: 20)).foregroundStyle(AppPalette.accent).frame(width: 24)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(area.title).foregroundStyle(AppPalette.primary)
        Text(area.detail).font(.caption).foregroundStyle(AppPalette.secondary)
      }
      Spacer(minLength: 8)
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppPalette.secondary).accessibilityHidden(true)
    }.frame(minHeight: 64).contentShape(Rectangle())
  }
}
