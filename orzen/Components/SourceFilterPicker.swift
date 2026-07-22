import SwiftUI

enum SourceFilter: Hashable {
    case all
    case category(StreamSourceCategory)

    var title: String {
        switch self {
        case .all:
            return "All"
        case .category(let category):
            return category.filterTitle ?? category.rawValue.capitalized
        }
    }
}

struct SourceFilterPicker: View {
    @Binding var selection: SourceFilter
    let categories: [StreamSourceCategory]

    private var filters: [SourceFilter] {
        [.all] + categories.map(SourceFilter.category)
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(filters, id: \.self) { filter in
                SourceFilterButton(
                    title: filter.title,
                    isSelected: selection == filter,
                    action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selection = filter
                        }
                    }
                )
            }
        }
    }
}

private struct SourceFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        if #available(macOS 26, iOS 26, *) {
            Button(action: action) {
                if isSelected {
                    label
                        .background(Color.white, in: Capsule())
                        .selectedSourceFilterHighlight(isSelected: isSelected, isHovered: isHovered)
                } else {
                    label
                        .background(filterButtonBackground)
                        .glassEffect(.clear.interactive(), in: Capsule())
                        .selectedSourceFilterHighlight(isSelected: isSelected, isHovered: isHovered)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        } else {
            Button(action: action) {
                label
                    .background(isSelected ? Color.white : Color.clear, in: Capsule())
                    .background(filterButtonBackground)
                    .selectedSourceFilterHighlight(isSelected: isSelected, isHovered: isHovered)
            }
            .buttonStyle(.plain)
            .contentShape(Capsule())
            .onHover { hovering in
                isHovered = hovering
            }
            .animation(.easeInOut(duration: 0.12), value: isHovered)
        }
    }

    private var filterButtonBackground: some View {
        Capsule()
            .fill(Color.white.opacity(isHovered && !isSelected ? 0.16 : 0.08))
            .opacity(isSelected ? 0 : 1)
    }

    private var label: some View {
        Text(title)
            .font(.callout)
            .fontWeight(.medium)
            .foregroundColor(isSelected ? .black.opacity(0.86) : .white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
    }
}

private extension View {
    func selectedSourceFilterHighlight(isSelected: Bool, isHovered: Bool) -> some View {
        self
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(isSelected ? 0.72 : (isHovered ? 0.14 : 0.06)), lineWidth: 1)
            }
            .shadow(color: .black.opacity(isSelected ? 0.18 : 0), radius: 8, y: 3)
    }
}
