import MapKit
import SwiftUI

/// Map of nearby stringers with a results panel hanging from the top of it.
///
/// Shops that already run on Serving open their storefront; shops discovered
/// from the map that haven't claimed an account show name, address and a call
/// button instead.
///
/// The results live in a panel that drops down from the top rather than a
/// sheet. A sheet is presented on the window and covers the system tab bar,
/// whereas this panel is part of the screen, so Discover keeps the same bottom
/// bar as Orders and Profile.
///
/// The panel wears the brand's court green and optic yellow — the same look as
/// the landing screen — in both light and dark mode, so the player's home tab
/// reads as Serving rather than a stock map.
struct DiscoverView: View {

    @EnvironmentObject private var discover: DiscoverStore
    @EnvironmentObject private var location: LocationService

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationService.fallbackCoordinate.clCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )
    )
    /// Lets the compass and user-location button be positioned by hand,
    /// below the results panel.
    @Namespace private var mapScope

    @State private var visibleRegion: MKCoordinateRegion?
    @State private var showSearchThisArea = false
    /// Where the map came to rest after the app last moved it or searched it.
    /// "Search this area" appears once the player pans well away from here.
    /// Cleared while the app is moving the map, and picked up again from
    /// wherever that move lands.
    @State private var settledCenter: Coordinate?
    @State private var hasCenteredOnUser = false
    @State private var panelDetent: PanelDetent = .medium
    /// How far the panel's handle has been dragged from `panelDetent`. Springs
    /// back to zero as the panel settles on its new detent.
    @GestureState(resetTransaction: Transaction(animation: PanelDetent.animation))
    private var panelDrag: CGFloat = 0
    /// Title, search bar and filter chips — what stays visible when collapsed.
    @State private var panelHeaderHeight: CGFloat = 0
    /// Top of the open map: below the panel at its half-open height.
    @State private var mapTopInset: CGFloat = 0
    @FocusState private var isSearchFocused: Bool
    /// The shop whose pin was tapped. Its card shows along the bottom of the
    /// map, and tapping the card opens the storefront.
    @State private var previewedBusiness: StringerBusiness?
    /// Measured once the card is on screen; starts at a typical height so the
    /// map makes room for it in one move.
    @State private var previewCardHeight: CGFloat = 170
    /// Where the map is looking, so centring on a pin keeps the zoom.
    @State private var currentCamera: MapCamera?
    /// Until this time, camera moves are the app's own — centring on a pin,
    /// then the map shifting as the card takes or gives back its space —
    /// and only update where the map counts as settled.
    @State private var appMoveEnds: Date?

    var body: some View {
        NavigationStack {
            mapScreen
                // The storefront pushes onto this stack rather than inside the
                // panel, so it gets the full screen and survives tab switches.
                .navigationDestination(item: $discover.selectedBusiness) { business in
                    if business.isClaimed {
                        StorefrontView(business: business)
                    } else {
                        UnclaimedBusinessView(business: business)
                    }
                }
        }
    }

    private var mapScreen: some View {
        // Sized to the space between the status bar and the tab bar (and the
        // keyboard, so the expanded list stays above it).
        GeometryReader { proxy in
            let heights = PanelHeights(
                available: proxy.size.height,
                collapsed: panelHeaderHeight + PanelHandle.height
            )
            let panelHeight = heights.clamped(heights[panelDetent] + panelDrag)

            ZStack(alignment: .top) {
                map
                    // The map runs under the panel, but treats only the part
                    // below it as visible, so framing the results centres
                    // them in the open map rather than behind the panel.
                    // Pinned to the half-open height rather than following
                    // the panel — MapKit recentres whenever the inset
                    // changes, which would shift the map on every drag.
                    .safeAreaPadding(.top, mapTopInset)
                    // Likewise the pin card: the tapped pin is centred above
                    // it, and Apple's Maps and Legal labels move up clear of it.
                    .safeAreaPadding(
                        .bottom,
                        previewedBusiness == nil ? 0 : previewCardHeight + Theme.Spacing.sm
                    )
                    .ignoresSafeArea(edges: .top)
                    .ignoresSafeArea(.keyboard)

                VStack(spacing: Theme.Spacing.sm) {
                    resultsPanel(height: panelHeight, heights: heights)

                    ZStack(alignment: .top) {
                        mapControls
                        searchThisAreaButton
                    }
                    // Nothing of the map is left to control once the panel is
                    // most of the way down.
                    .opacity(heights.expanded - panelHeight > 120 ? 1 : 0)
                }

                // Hidden once the panel covers most of the map, and while
                // typing, when the keyboard would push it up into the panel.
                let showsPreview = heights.expanded - panelHeight > 260 && !isSearchFocused
                pinPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
                    .opacity(showsPreview ? 1 : 0)
                    .allowsHitTesting(showsPreview)
            }
            .onChange(of: heights[.medium], initial: true) { _, medium in
                // Held while typing, so the keyboard squeezing the space
                // doesn't move the map underneath it.
                guard !isSearchFocused else { return }
                mapTopInset = proxy.safeAreaInsets.top + medium
            }
        }
        .mapScope(mapScope)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        // The panel behind the status bar is always court green, so the
        // clock and battery stay light even in light mode.
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            location.requestPermissionIfNeeded()
            if discover.results.isEmpty {
                await discover.search(near: location.effectiveCoordinate)
                frameResults()
            }
        }
        .onChange(of: location.coordinate) { _, newValue in
            guard let newValue, !hasCenteredOnUser else { return }
            hasCenteredOnUser = true
            Task {
                await discover.search(near: newValue)
                frameResults()
            }
        }
        .onChange(of: isSearchFocused) { _, isFocused in
            // Typing into a collapsed panel would leave the results hidden.
            guard isFocused, panelDetent == .collapsed else { return }
            withAnimation(PanelDetent.animation) { panelDetent = .medium }
        }
        .onChange(of: discover.filteredResults) { _, results in
            // A new search or filter can drop the shop being previewed, or
            // bring back fresher details for it.
            guard let previewed = previewedBusiness else { return }
            if let fresh = results.first(where: { $0.id == previewed.id }) {
                previewedBusiness = fresh
            } else {
                closePreview()
            }
        }
        .errorAlert(message: $discover.errorMessage)
    }

    /// Fits the player and the results into the part of the map below the
    /// panel, or just centres on the player when nothing was found.
    private func frameResults() {
        let center = discover.searchCenter
        let points = discover.filteredResults.map(\.coordinate) + [center]
        let latitudes = points.map(\.latitude)
        let longitudes = points.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }

        // Padded so the outermost pins and their labels aren't on the edge,
        // and floored so a single nearby shop doesn't zoom to street level.
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.04),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.04)
            )
        )
        settledCenter = nil
        withAnimation { cameraPosition = .region(region) }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $cameraPosition, scope: mapScope) {
            UserAnnotation()

            ForEach(discover.filteredResults) { business in
                // Anchored at the bottom, where a price tag's point is.
                Annotation(business.name, coordinate: business.coordinate.clCoordinate, anchor: .bottom) {
                    MapPin(
                        business: business,
                        isSelected: previewedBusiness?.id == business.id
                            || discover.selectedBusiness?.id == business.id
                    )
                    .onTapGesture {
                        // A pin opens the shop's card first; the card is
                        // what navigates. Tapping the same pin again closes it.
                        if previewedBusiness?.id == business.id {
                            closePreview()
                        } else {
                            preview(business)
                        }
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        // Muted, with Apple's points of interest left out, so the ball pins
        // are the brightest things on the map.
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        // The built-in controls sit in the top-trailing corner, which the
        // results panel occupies, so they are placed by hand below it.
        .mapControls { }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            currentCamera = context.camera
            let center = Coordinate(context.region.center)
            if let appMoveEnds, Date() < appMoveEnds {
                settledCenter = center
                return
            }
            guard let settledCenter else {
                settledCenter = center
                return
            }
            showSearchThisArea = settledCenter.distanceMeters(to: center) > 1_500
        }
    }

    private var mapControls: some View {
        VStack(spacing: Theme.Spacing.sm) {
            MapUserLocationButton(scope: mapScope)
            MapCompass(scope: mapScope)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, Theme.Spacing.md)
    }

    @ViewBuilder
    private var searchThisAreaButton: some View {
        if showSearchThisArea {
            Button {
                searchVisibleRegion()
            } label: {
                Label("Search this area", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .labelStyle(OpticIconLabelStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(DiscoverPalette.panelBottom))
                    .overlay(Capsule().stroke(DiscoverPalette.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
            }
            .buttonStyle(PressableButtonStyle())
            // Sits directly under the results panel in the same stack, so it
            // follows the panel up and down with no inset of its own.
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var pinPreview: some View {
        if let business = previewedBusiness {
            PinPreviewCard(
                business: business,
                distanceText: discover.distanceText(to: business),
                onOpen: { discover.selectedBusiness = business },
                onClose: closePreview
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                previewCardHeight = $0
            }
            // Switching pins swaps the card rather than morphing it.
            .id(business.id)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Shows the shop's card and brings its pin to the middle of the open map
    /// above it, at the current zoom.
    private func preview(_ business: StringerBusiness) {
        // The app is moving the map, so this isn't a reason to offer
        // "Search this area".
        settledCenter = nil
        appMoveEnds = .now + 1.5
        withAnimation(PinPreviewCard.animation) {
            previewedBusiness = business
            cameraPosition = .camera(
                MapCamera(
                    centerCoordinate: business.coordinate.clCoordinate,
                    distance: currentCamera?.distance ?? 20_000,
                    heading: currentCamera?.heading ?? 0,
                    pitch: currentCamera?.pitch ?? 0
                )
            )
        }
    }

    private func closePreview() {
        // Giving the card's space back shifts the map a little.
        settledCenter = nil
        appMoveEnds = .now + 1.5
        withAnimation(PinPreviewCard.animation) { previewedBusiness = nil }
    }

    private func searchVisibleRegion() {
        guard let visibleRegion else { return }
        showSearchThisArea = false
        settledCenter = Coordinate(visibleRegion.center)
        Task { await discover.searchVisibleRegion(visibleRegion) }
    }

    // MARK: - Results panel

    private func resultsPanel(height: CGFloat, heights: PanelHeights) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                panelTitle
                searchBar
                filterChips
            }
            // Always at its natural height, so the title doesn't squash while
            // the panel springs between detents.
            .fixedSize(horizontal: false, vertical: true)
            .background(alignment: .top) {
                CourtLines()
                    .stroke(.white.opacity(0.045), lineWidth: 1.5)
                    .padding(.horizontal, Theme.Spacing.md)
                    .allowsHitTesting(false)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                panelHeaderHeight = $0
            }

            results
                // Squeezes down to nothing as the panel collapses onto the
                // search bar, instead of pushing the handle out of the panel.
                .frame(minHeight: 0, maxHeight: .infinity)
                .clipped()
                .opacity(height > heights.collapsed + 1 ? 1 : 0)

            PanelHandle(detent: $panelDetent)
                .gesture(
                    DragGesture()
                        .updating($panelDrag) { value, drag, _ in
                            drag = value.translation.height
                        }
                        .onEnded { value in
                            let projected = heights[panelDetent] + value.predictedEndTranslation.height
                            withAnimation(PanelDetent.animation) {
                                panelDetent = heights.nearest(to: projected)
                            }
                        }
                )
        }
        .frame(height: height, alignment: .top)
        .background(
            PanelBackground()
                // Runs up behind the status bar, so the panel reads as hanging
                // from the top edge of the screen.
                .ignoresSafeArea(edges: .top)
        )
        // The panel is always dark, so text fields, spinners and the keyboard
        // take their dark-mode look inside it.
        .environment(\.colorScheme, .dark)
    }

    private var panelTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Find your \(Text("stringer").foregroundStyle(Theme.optic))")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.optic)
                    .frame(width: 6, height: 6)
                Text(resultsSummary)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .contentTransition(.numericText())
                    .animation(.default, value: resultsSummary)
                // A refresh over results already on screen; an empty list
                // shows its own spinner instead.
                if discover.isLoading && !discover.filteredResults.isEmpty {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.65))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md + 2)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var resultsSummary: String {
        if discover.isLoading && discover.filteredResults.isEmpty {
            return "Looking around you…"
        }
        let count = discover.filteredResults.count
        guard count > 0 else { return "Nobody in this area yet" }
        return "\(count) nearby"
    }

    @ViewBuilder
    private var results: some View {
        if discover.isLoading && discover.filteredResults.isEmpty {
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .tint(Theme.optic)
                    .controlSize(.large)
                Text("Finding stringers…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if discover.filteredResults.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(discover.filteredResults) { business in
                        Button {
                            discover.selectedBusiness = business
                        } label: {
                            ResultCard(
                                business: business,
                                distanceText: discover.distanceText(to: business)
                            )
                        }
                        .buttonStyle(PressableButtonStyle())
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, 2)
                .padding(.bottom, Theme.Spacing.sm)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: discover.filteredResults.map(\.id))
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.optic)
                .frame(width: 60, height: 60)
                .background(Circle().fill(DiscoverPalette.glass))
                .overlay(Circle().stroke(DiscoverPalette.hairline, lineWidth: 1))

            VStack(spacing: 4) {
                Text("No stringers here yet")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Try widening the map or searching a nearby city.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Button {
                guard let visibleRegion else { return }
                Task { await discover.searchVisibleRegion(visibleRegion) }
            } label: {
                Label("Search this area", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DiscoverPalette.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(Capsule().fill(Theme.optic))
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.optic)
            TextField(
                "Search stringers or a city",
                text: $discover.searchText,
                prompt: Text("Search stringers or a city").foregroundStyle(.white.opacity(0.45))
            )
            .foregroundStyle(.white)
            .tint(Theme.optic)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .focused($isSearchFocused)
            .onSubmit { Task { await discover.runSearch() } }
            .onChange(of: discover.searchText) { _, _ in
                discover.searchTextChanged()
            }
            if !discover.searchText.isEmpty {
                Button {
                    discover.searchText = ""
                    Task { await discover.runSearch() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(.white.opacity(isSearchFocused ? 0.12 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .stroke(isSearchFocused ? Theme.optic.opacity(0.7) : DiscoverPalette.hairline, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: isSearchFocused)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm + 2)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                FilterChip(
                    title: "Storefronts",
                    isOn: discover.claimedOnly,
                    icon: { Image(systemName: "storefront.fill").font(.caption) }
                ) {
                    discover.claimedOnly.toggle()
                }
                ForEach(RacquetSport.allCases) { sport in
                    FilterChip(
                        title: sport.label,
                        isOn: discover.sportFilter == sport,
                        icon: { RacquetGlyph(sport: sport) }
                    ) {
                        discover.sportFilter = discover.sportFilter == sport ? nil : sport
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .padding(.bottom, Theme.Spacing.md)
    }
}

// MARK: - Palette

/// The panel's colours: solid court colours from the court style, not
/// adapted to the appearance — the panel looks the same in light and dark
/// mode.
private enum DiscoverPalette {
    /// Behind the results panel and the pin card.
    static var panel: Color { Theme.courtTop }
    /// The darker court colour, for small pieces sitting on the map.
    static var panelBottom: Color { Theme.courtBottom }
    /// Near-black of the court's hue for text and icons on optic yellow.
    static var ink: Color { Theme.ink }
    static let glass = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.1)
}

// MARK: - Supporting views

/// Resting heights of the results panel. Unlike a sheet's detents these are
/// measured down from the top of the screen.
private enum PanelDetent: CaseIterable {
    /// Just the title, search bar and filter chips, leaving the map clear.
    case collapsed
    case medium
    /// Down to the tab bar.
    case expanded

    static let animation = Animation.spring(response: 0.35, dampingFraction: 0.85)
}

private struct PanelHeights {
    /// Between the status bar and the tab bar (or keyboard).
    let available: CGFloat
    let collapsed: CGFloat

    var expanded: CGFloat { max(available, collapsed) }

    subscript(detent: PanelDetent) -> CGFloat {
        switch detent {
        case .collapsed: collapsed
        case .medium: min(max(available * 0.5, collapsed), expanded)
        case .expanded: expanded
        }
    }

    func clamped(_ height: CGFloat) -> CGFloat {
        min(max(height, collapsed), expanded)
    }

    func nearest(to height: CGFloat) -> PanelDetent {
        PanelDetent.allCases.min { abs(self[$0] - height) < abs(self[$1] - height) } ?? .medium
    }
}

/// The court colour, solid, rounded along the bottom edge.
private struct PanelBackground: View {
    var body: some View {
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: Theme.Radius.large + 4,
            bottomTrailingRadius: Theme.Radius.large + 4,
            style: .continuous
        )

        shape
            .fill(DiscoverPalette.panel)
            .overlay(
                shape.stroke(Theme.optic.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }
}

/// One half of a tennis court seen from above — baseline, singles sidelines,
/// service line and centre service line — drawn faintly behind the panel's
/// header.
private struct CourtLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.08
        let left = rect.minX + inset
        let right = rect.maxX - inset
        let serviceLine = rect.minY + rect.height * 0.62

        // Sidelines running off the bottom, as if the court carries on.
        path.move(to: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY))
        path.move(to: CGPoint(x: right, y: rect.minY))
        path.addLine(to: CGPoint(x: right, y: rect.maxY))
        // Service line and the centre line down to the net.
        path.move(to: CGPoint(x: left, y: serviceLine))
        path.addLine(to: CGPoint(x: right, y: serviceLine))
        path.move(to: CGPoint(x: rect.midX, y: serviceLine))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// Grabber along the bottom edge of the results panel — the mirror of a
/// sheet's drag indicator. Dragging it is wired up by the panel, which knows
/// the heights; tapping it toggles between collapsed and open.
private struct PanelHandle: View {

    static let height: CGFloat = 28

    @Binding var detent: PanelDetent

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.35))
            .frame(width: 40, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(PanelDetent.animation) {
                    detent = detent == .collapsed ? .medium : .collapsed
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Results")
            .accessibilityValue(accessibilityValue)
            .accessibilityAdjustableAction { direction in
                withAnimation(PanelDetent.animation) {
                    switch (direction, detent) {
                    case (.increment, .collapsed): detent = .medium
                    case (.increment, _): detent = .expanded
                    case (.decrement, .expanded): detent = .medium
                    case (.decrement, _): detent = .collapsed
                    @unknown default: break
                    }
                }
            }
    }

    private var accessibilityValue: String {
        switch detent {
        case .collapsed: "Collapsed"
        case .medium: "Half open"
        case .expanded: "Fully open"
        }
    }
}

/// Shops on Serving are price tags — their racquet and starting price on a
/// court-green tag pointing at the spot, turning optic yellow when tapped.
/// Shops found through Apple Maps are small, quiet phone markers, so the
/// bookable shops stand out.
private struct MapPin: View {
    let business: StringerBusiness
    let isSelected: Bool

    var body: some View {
        Group {
            if business.isClaimed {
                priceTag
            } else {
                storefrontMarker
            }
        }
        // Grows from the point, so the tip stays on the shop's location.
        .scaleEffect(isSelected ? 1.18 : 1, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
        .accessibilityElement()
        .accessibilityLabel(business.name)
        .accessibilityAddTraits(.isButton)
    }

    private var priceTag: some View {
        let fill = isSelected ? Theme.optic : DiscoverPalette.ink

        return VStack(spacing: -1) {
            HStack(spacing: 5) {
                RacquetGlyph(sport: sport, height: 13)
                    .foregroundStyle(isSelected ? DiscoverPalette.ink : Theme.optic)
                if let priceText {
                    Text(priceText)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? DiscoverPalette.ink : .white)
                }
            }
            .padding(.horizontal, priceText == nil ? 8 : 10)
            .frame(height: 28)
            .background(Capsule().fill(fill))
            .overlay(
                Capsule().stroke(isSelected ? DiscoverPalette.ink.opacity(0.25) : Theme.optic.opacity(0.45), lineWidth: 1)
            )

            PinPointer()
                .fill(fill)
                .frame(width: 10, height: 6)
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
    }

    /// A phone, since these shops are booked by calling — the storefront
    /// icon is kept for shops with a storefront on Serving.
    private var storefrontMarker: some View {
        Image(systemName: "phone.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isSelected ? DiscoverPalette.ink : DiscoverPalette.panel)
            .frame(width: 24, height: 24)
            .background(Circle().fill(isSelected ? Theme.optic : .white))
            .overlay(Circle().stroke(DiscoverPalette.panel.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 3, y: 1.5)
    }

    /// Badminton only when that's all the shop strings; tennis otherwise.
    private var sport: RacquetSport {
        let sports = Set(business.inventory.map(\.sport))
        return sports == [.badminton] ? .badminton : .tennis
    }

    private var priceText: String? { business.shortStartingPrice }
}

private extension StringerBusiness {
    /// Starting price in whole dollars where the price is whole — "$22"
    /// rather than "$22.00" — for the compact places Discover shows it.
    var shortStartingPrice: String? {
        startingPrice?.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    /// Today's opening hours, when the shop has published them.
    var todayHours: OpenHours? {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return openHours.first { $0.weekday == weekday }
    }
}

/// The small triangle under a price tag that points at the shop.
private struct PinPointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX + 1, y: rect.maxY - 0.5),
            control: CGPoint(x: rect.midX + 2, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX - 1, y: rect.maxY - 0.5),
            control: CGPoint(x: rect.midX, y: rect.maxY + 0.5)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.midX - 2, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

/// A shop in the results list, as a glass card on the court-green panel.
///
/// Shops have no logo or photo, so the card leads with words and numbers
/// rather than a placeholder: the name and address up top with the starting
/// price opposite, then a row of facts to compare shops by.
private struct ResultCard: View {
    let business: StringerBusiness
    let distanceText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(business.name)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(business.isClaimed ? 1 : 0.85))
                            .lineLimit(1)
                        if business.isClaimed {
                            // Marks a shop with its storefront set up on
                            // Serving, so it can be booked in the app.
                            Image(systemName: "storefront.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.optic)
                                .accessibilityLabel("Storefront on Serving")
                        }
                    }

                    Text(business.address.oneLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: Theme.Spacing.sm)

                if business.isClaimed, let price = business.shortStartingPrice {
                    VStack(alignment: .trailing, spacing: -1) {
                        Text("from")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(price)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.optic)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Rectangle()
                .fill(DiscoverPalette.hairline)
                .frame(height: 1)

            HStack(spacing: 6) {
                // Drops today's hours first when the row runs out of room.
                ViewThatFits(in: .horizontal) {
                    facts(includingHours: true)
                    facts(includingHours: false)
                }

                Spacer(minLength: 0)

                Image(systemName: business.isClaimed ? "arrow.up.right" : "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(business.isClaimed ? DiscoverPalette.ink : .white.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(business.isClaimed ? AnyShapeStyle(Theme.optic) : AnyShapeStyle(DiscoverPalette.glass))
                    )
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium + 2, style: .continuous)
                .fill(.white.opacity(business.isClaimed ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium + 2, style: .continuous)
                .stroke(DiscoverPalette.hairline, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func facts(includingHours: Bool) -> some View {
        HStack(spacing: 6) {
            InfoPill(systemImage: "location.fill", text: distanceText)

            if business.isClaimed {
                if business.rating != nil {
                    InfoPill(
                        systemImage: "star.fill",
                        text: "\(business.ratingText) (\(business.ratingCount))",
                        iconTint: Theme.warning
                    )
                }
                if includingHours, let today = business.todayHours {
                    InfoPill(
                        systemImage: "clock.fill",
                        text: today.isClosed ? "Closed today" : today.displayRange
                    )
                }
            } else {
                InfoPill(systemImage: "phone.fill", text: "Call to book")
            }
        }
    }
}

/// The card a map pin opens along the bottom of the map: enough about the
/// shop to decide whether to look closer, and a tap anywhere on it opens the
/// storefront. Swipe it down, or tap the close button, to put it away.
private struct PinPreviewCard: View {
    let business: StringerBusiness
    let distanceText: String
    let onOpen: () -> Void
    let onClose: () -> Void

    static let animation = Animation.spring(response: 0.38, dampingFraction: 0.82)

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md - 2) {
                header
                details
                callToAction
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(business.isClaimed ? "Opens the storefront" : "Shows how to book")
        .overlay(alignment: .topTrailing) { closeButton }
        .offset(y: dragOffset)
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    // Follows a downward drag; resists an upward one.
                    let height = value.translation.height
                    dragOffset = height > 0 ? height : height / 6
                }
                .onEnded { value in
                    if value.predictedEndTranslation.height > 80 {
                        onClose()
                    } else {
                        withAnimation(Self.animation) { dragOffset = 0 }
                    }
                }
        )
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(business.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if business.isClaimed {
                    Image(systemName: "storefront.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.optic)
                        .accessibilityLabel("Storefront on Serving")
                }
            }
            // Clears the close button in the corner.
            .padding(.trailing, 36)

            Text(business.address.oneLine)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var details: some View {
        HStack(spacing: 6) {
            InfoPill(systemImage: "location.fill", text: distanceText)

            if business.isClaimed {
                if business.rating != nil {
                    InfoPill(
                        systemImage: "star.fill",
                        text: "\(business.ratingText) (\(business.ratingCount))",
                        iconTint: Theme.warning
                    )
                }
                if let today = business.todayHours {
                    InfoPill(
                        systemImage: "clock.fill",
                        text: today.isClosed ? "Closed today" : today.displayRange
                    )
                } else {
                    InfoPill(systemImage: "clock.fill", text: business.turnaroundText)
                }
            } else {
                InfoPill(systemImage: "phone.fill", text: "Call to book")
            }
        }
    }

    private var callToAction: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if business.isClaimed, let startingPrice = business.shortStartingPrice {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Stringing from")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(startingPrice)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.optic)
                }
            } else if !business.isClaimed {
                Text("Not on Serving yet")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text(business.isClaimed ? "View storefront" : "View details")
                Image(systemName: "arrow.right")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(business.isClaimed ? DiscoverPalette.ink : .white)
            .padding(.horizontal, 16)
            .frame(height: 42)
            .background(
                Capsule().fill(business.isClaimed ? AnyShapeStyle(Theme.optic) : AnyShapeStyle(.white.opacity(0.12)))
            )
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.12)))
                // A full-size tap target around the small circle.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityLabel("Close")
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
        return shape
            .fill(DiscoverPalette.panel)
            .overlay(shape.stroke(Theme.optic.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

}

private struct InfoPill: View {
    let systemImage: String
    let text: String
    var iconTint: Color = .white.opacity(0.7)

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(iconTint)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}

struct FilterChip<Icon: View>: View {
    let title: String
    let isOn: Bool
    /// The sport chips draw their racquet, so this takes a view rather than
    /// an SF Symbol name.
    @ViewBuilder var icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                icon
                Text(title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(isOn ? DiscoverPalette.ink : .white.opacity(0.85))
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isOn ? AnyShapeStyle(Theme.optic) : AnyShapeStyle(DiscoverPalette.glass))
            )
            .overlay(
                Capsule().stroke(isOn ? .clear : DiscoverPalette.hairline, lineWidth: 1)
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isOn)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension FilterChip where Icon == EmptyView {
    init(title: String, isOn: Bool, action: @escaping () -> Void) {
        self.init(title: title, isOn: isOn, icon: { EmptyView() }, action: action)
    }
}

/// Shrinks a touch while pressed.
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A label whose icon is optic yellow and whose title keeps the text colour.
private struct OpticIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Theme.optic)
            configuration.title
        }
    }
}

#Preview {
    DiscoverView()
        .environmentObject(DiscoverStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(RacquetStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(CartStore())
        .environmentObject(LocationService())
}
