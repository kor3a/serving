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
    /// Search bar plus filter chips — what stays visible when collapsed.
    @State private var panelHeaderHeight: CGFloat = 0
    /// Top of the open map: below the panel at its half-open height.
    @State private var mapTopInset: CGFloat = 0
    @FocusState private var isSearchFocused: Bool

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
                Annotation(business.name, coordinate: business.coordinate.clCoordinate) {
                    MapPin(business: business, isSelected: discover.selectedBusiness?.id == business.id)
                        .onTapGesture {
                            discover.selectedBusiness = business
                        }
                }
                .annotationTitles(.hidden)
            }
        }
        // The built-in controls sit in the top-trailing corner, which the
        // results panel occupies, so they are placed by hand below it.
        .mapControls { }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            let center = Coordinate(context.region.center)
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
                guard let visibleRegion else { return }
                showSearchThisArea = false
                settledCenter = Coordinate(visibleRegion.center)
                Task { await discover.searchVisibleRegion(visibleRegion) }
            } label: {
                Label("Search this area", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().stroke(Theme.separator, lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
            .foregroundStyle(Theme.primaryText)
            // Sits directly under the results panel in the same stack, so it
            // follows the panel up and down with no inset of its own.
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Results panel

    private func resultsPanel(height: CGFloat, heights: PanelHeights) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                searchBar
                filterChips
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
            UnevenRoundedRectangle(
                bottomLeadingRadius: Theme.Radius.large,
                bottomTrailingRadius: Theme.Radius.large,
                style: .continuous
            )
            .fill(Theme.background)
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            // Runs up behind the status bar, so the panel reads as hanging
            // from the top edge of the screen.
            .ignoresSafeArea(edges: .top)
        )
    }

    @ViewBuilder
    private var results: some View {
        if discover.isLoading && discover.filteredResults.isEmpty {
            ProgressView("Finding stringers…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if discover.filteredResults.isEmpty {
            EmptyStateView(
                iconName: "mappin.slash",
                title: "No stringers here yet",
                message: "Try widening the map or searching a nearby city.",
                actionTitle: "Search this area",
                action: {
                    guard let visibleRegion else { return }
                    Task { await discover.searchVisibleRegion(visibleRegion) }
                }
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                Section {
                    ForEach(discover.filteredResults) { business in
                        Button {
                            discover.selectedBusiness = business
                        } label: {
                            BusinessRow(
                                business: business,
                                distanceText: discover.distanceText(to: business)
                            )
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.surface)
                    }
                } header: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("\(discover.filteredResults.count) nearby · \(discover.claimedCount) on Serving")
                            .font(.caption)
                        // Carries the refresh spinner the sheet header
                        // used to hold.
                        if discover.isLoading {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField("Search stringers or a city", text: $discover.searchText)
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
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(Theme.surfaceAlt)
        )
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                FilterChip(title: "On Serving", isOn: discover.claimedOnly) {
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
        .padding(.bottom, Theme.Spacing.sm)
    }
}

// MARK: - Supporting views

/// Resting heights of the results panel. Unlike a sheet's detents these are
/// measured down from the top of the screen.
private enum PanelDetent: CaseIterable {
    /// Just the search bar and filter chips, leaving the map clear.
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

/// Grabber along the bottom edge of the results panel — the mirror of a
/// sheet's drag indicator. Dragging it is wired up by the panel, which knows
/// the heights; tapping it toggles between collapsed and open.
private struct PanelHandle: View {

    static let height: CGFloat = 28

    @Binding var detent: PanelDetent

    var body: some View {
        Capsule()
            .fill(Theme.secondaryText.opacity(0.4))
            .frame(width: 36, height: 5)
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

private struct MapPin: View {
    let business: StringerBusiness
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(business.isClaimed ? Theme.accent : Theme.surface)
                    .frame(width: isSelected ? 40 : 32, height: isSelected ? 40 : 32)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                Circle()
                    .stroke(business.isClaimed ? Color.white.opacity(0.8) : Theme.separator, lineWidth: 2)
                    .frame(width: isSelected ? 40 : 32, height: isSelected ? 40 : 32)
                Image(systemName: business.isClaimed ? "figure.tennis" : "mappin")
                    .font(.system(size: isSelected ? 17 : 14, weight: .bold))
                    .foregroundStyle(business.isClaimed ? .white : Theme.secondaryText)
            }
            if isSelected {
                Text(business.name)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.surface))
                    .fixedSize()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

struct BusinessRow: View {
    let business: StringerBusiness
    let distanceText: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(business.isClaimed ? Theme.accent.opacity(0.15) : Theme.surfaceAlt)
                    .frame(width: 48, height: 48)
                Image(systemName: business.isClaimed ? "figure.tennis" : "storefront")
                    .font(.title3)
                    .foregroundStyle(business.isClaimed ? Theme.accent : Theme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(business.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    if !business.isClaimed {
                        Badge(text: "Call to book", tint: Theme.secondaryText)
                    }
                }

                Text(business.address.oneLine)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)

                HStack(spacing: Theme.Spacing.sm) {
                    Text(distanceText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)

                    if business.isClaimed {
                        if business.rating != nil {
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.warning)
                                Text("\(business.ratingText) (\(business.ratingCount))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        if let startingPrice = business.startingPrice {
                            Text("from \(startingPrice.currencyString)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.separator)
                .padding(.top, 16)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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
            .foregroundStyle(isOn ? .white : Theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isOn ? Theme.accent : Theme.surfaceAlt)
            )
        }
        .buttonStyle(.plain)
    }
}

extension FilterChip where Icon == EmptyView {
    init(title: String, isOn: Bool, action: @escaping () -> Void) {
        self.init(title: title, isOn: isOn, icon: { EmptyView() }, action: action)
    }
}

#Preview {
    DiscoverView()
        .environmentObject(DiscoverStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(RacquetStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(CartStore())
        .environmentObject(LocationService())
}
