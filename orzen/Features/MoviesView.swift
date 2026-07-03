import SwiftUI

struct MoviesView: View {
    var scrollToTopRequest = 0

    var body: some View {
        CinemetaCatalogView(
            title: "Movies",
            type: .movie,
            filters: CinemetaCatalogPresets.movieFilters,
            fallbackItems: movies,
            scrollToTopRequest: scrollToTopRequest
        )
    }
}

#Preview {
    MoviesView()
}
