import SwiftUI

/// Geometry shared by sidebar screens and collection details (including Downloads).
/// Keep poster sizing in OrzenLayout; these values describe the screen, not its cards.
enum OrzenScreenLayout {
    static let horizontalPadding: CGFloat = 16
    static let topPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 20
    static let contentSpacing: CGFloat = 20

    static var titleFont: Font {
        #if os(macOS)
        .title
        #else
        .title2
        #endif
    }
}

/// A fixed heading above the content. NavigationStack ownership stays with the caller.
struct OrzenScreen<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: OrzenScreenLayout.contentSpacing) {
                header
                content
            }
            #if os(macOS)
            .padding(.horizontal, OrzenScreenLayout.horizontalPadding)
            .padding(.top, OrzenScreenLayout.topPadding)
            #endif
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension OrzenScreen where Header == OrzenScreenHeading<EmptyView> {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(header: { OrzenScreenHeading(title: title) }, content: content)
    }
}

/// Accessories are overlaid so buttons and loading indicators cannot move the title.
struct OrzenScreenHeading<Accessories: View>: View {
    let title: String
    private let accessories: Accessories

    init(title: String, @ViewBuilder accessories: () -> Accessories) {
        self.title = title
        self.accessories = accessories()
    }

    var body: some View {
        Text(title)
            .font(OrzenScreenLayout.titleFont)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) { accessories }
            .orzenScreenContentInset()
            #if os(iOS)
            .padding(.top, OrzenScreenLayout.topPadding)
            #endif
    }
}

extension OrzenScreenHeading where Accessories == EmptyView {
    init(title: String) {
        self.init(title: title, accessories: { EmptyView() })
    }
}

/// Vertical scrolling uses the same edge treatment and insets on every screen.
/// macOS insets belong to OrzenScreen; iOS insets belong to the scroll content.
struct OrzenScreenScrollView<Content: View>: View {
    private let topPadding: CGFloat
    private let content: Content

    init(topPadding: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.topPadding = topPadding
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .orzenScreenContentInset()
            .padding(.top, topPadding)
            .padding(.bottom, OrzenScreenLayout.bottomPadding)
        }
        .orzenTopScrollEdgeEffect()
    }
}

/// The poster grid geometry is shared; each screen supplies its own actions and routes.
struct OrzenPosterGrid<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: OrzenLayout.posterGridColumns,
            alignment: .leading,
            spacing: OrzenLayout.current.gridVerticalSpacing
        ) {
            content
        }
    }
}

/// The collection detail shell follows Dropped's fixed macOS heading and inline iOS title.
struct OrzenCollectionScreen<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        OrzenScreen {
            #if os(macOS)
            OrzenScreenHeading(title: title)
            #endif
        } content: {
            content
        }
        .navigationTitle(title)
        .escapeKeyDismissShortcut()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .interactivePopGestureEnabled()
        #endif
    }
}

extension View {
    @ViewBuilder
    func orzenScreenContentInset() -> some View {
        #if os(iOS)
        padding(.horizontal, OrzenScreenLayout.horizontalPadding)
        #else
        self
        #endif
    }
}

/// A section label with optional leading and trailing controls kept on one row.
struct OrzenSectionHeading<Leading: View, Trailing: View>: View {
    let title: String
    var font: Font = .headline
    var leadingPadding: CGFloat = 0
    var trailingPadding: CGFloat = 0
    private let leading: Leading
    private let trailing: Trailing

    init(
        title: String,
        font: Font = .headline,
        leadingPadding: CGFloat = 0,
        trailingPadding: CGFloat = 0,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.font = font
        self.leadingPadding = leadingPadding
        self.trailingPadding = trailingPadding
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading

            Text(title)
                .font(font)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Spacer(minLength: 8)
            trailing
        }
        .padding(.leading, leadingPadding)
        .padding(.trailing, trailingPadding)
        .accessibilityElement(children: .contain)
    }
}

extension OrzenSectionHeading where Leading == EmptyView, Trailing == EmptyView {
    init(
        title: String,
        font: Font = .headline,
        leadingPadding: CGFloat = 0,
        trailingPadding: CGFloat = 0
    ) {
        self.init(
            title: title,
            font: font,
            leadingPadding: leadingPadding,
            trailingPadding: trailingPadding,
            leading: { EmptyView() },
            trailing: { EmptyView() }
        )
    }
}

extension OrzenSectionHeading where Leading == EmptyView {
    init(
        title: String,
        font: Font = .headline,
        leadingPadding: CGFloat = 0,
        trailingPadding: CGFloat = 0,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            title: title,
            font: font,
            leadingPadding: leadingPadding,
            trailingPadding: trailingPadding,
            leading: { EmptyView() },
            trailing: trailing
        )
    }
}
