import SwiftUI

public struct TruffloSegmentedControl<T: Hashable>: View {
    private let items: [T]
    @Binding private var selection: T
    private let titleKeyPath: KeyPath<T, String>

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        items: [T],
        selection: Binding<T>,
        titleKeyPath: KeyPath<T, String>
    ) {
        self.items = items
        self._selection = selection
        self.titleKeyPath = titleKeyPath
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(TruffloTheme.Motion.selection(reduceMotion: reduceMotion)) {
                        selection = item
                    }
                } label: {
                    Text(item[keyPath: titleKeyPath])
                        .font(.truffloSubheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.white : Color.truffloForest)
                        .padding(.vertical, TruffloTheme.Spacing.small)
                        .frame(maxWidth: .infinity)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.truffloForest)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .clipShape(Capsule())
                }
            }
        }
        .padding(4)
        .background(Color.truffloSand)
        .clipShape(Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}
