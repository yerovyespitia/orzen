import SwiftUI

struct DetailUnavailableView: View {
    enum Style {
        case card
        case centered
    }

    let systemImage: String
    let title: String
    let message: String
    var style: Style = .card
    var retryTitle: String?
    var retryAction: (() -> Void)?

    init(
        systemImage: String,
        title: String,
        message: String,
        style: Style = .card,
        retryTitle: String? = nil,
        retryAction: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.style = style
        self.retryTitle = retryTitle
        self.retryAction = retryAction
    }

    var body: some View {
        Group {
            switch style {
            case .card:
                card
            case .centered:
                centered
            }
        }
    }

    private var card: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(.white.opacity(0.64))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(message)
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.68))

                retryButton
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var centered: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(.gray)

            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text(message)
                .foregroundStyle(.gray.opacity(0.75))
                .multilineTextAlignment(.center)

            retryButton
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var retryButton: some View {
        if let retryTitle, let retryAction {
            Button(retryTitle, action: retryAction)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .padding(.top, 8)
        }
    }
}
