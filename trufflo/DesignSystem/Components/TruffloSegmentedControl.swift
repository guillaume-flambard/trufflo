import SwiftUI

public struct TruffloSegmentedControl<T: Hashable>: View {
    private let items: [T]
    @Binding private var selection: T
    private let titleKeyPath: KeyPath<T, String>

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
                    withAnimation(.snappy(duration: 0.2)) {
                        selection = item
                    }
                } label: {
                    Text(item[keyPath: titleKeyPath])
                        .font(.truffloSubheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.white : Color.truffloForest)
                        .padding(.vertical, TruffloTheme.Spacing.small)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? Color.truffloForest : Color.clear)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(4)
        .background(Color.truffloSand)
        .clipShape(Capsule())
    }
}
