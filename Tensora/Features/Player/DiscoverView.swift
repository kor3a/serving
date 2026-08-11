import MapKit
import SwiftUI

/// Map of nearby stringers with a results sheet layered over it.
///
/// Shops that already run on Tensora open their storefront; shops discovered
/// from the map that haven't claimed an account show name, address and a call
/// button instead.
///
/// The sheet is up the whole time this screen is on, and a sheet covers the
/// system tab bar, so this is the one screen that hides the bottom bar and
/// draws `PlayerTopTabBar` above the map instead.
struct DiscoverView: View {

    /// Drives the tab bar this screen draws at the top of itself, in place of
    /// the system one at the bottom.
    @Binding var selectedTab: PlayerRootView.Tab

    @EnvironmentObject private var discover: DiscoverStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var orders: OrderStore

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: LocationService.fallbackCoordinate.clCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.18, longitudeDelta: 0.18)
        )
    )
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var showSearchThisArea = false
    @State private var isSheetPresented = true
    @State private var hasCenteredOnUser = false
    @State private var sheetDetent: PresentationDetent = .medium

    var body: some View {
        NavigationStack {
            mapScreen
                // The storefront pushes onto this stack rather than inside the
                // sheet, so it gets the full screen and survives tab switches.
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
        VStack(spacing: 0) {
            PlayerTopTabBar(
                selection: $selectedTab,
                ordersBadge: orders.awaitingPlayerApproval.count
            )
            map
                .overlay(alignment: .top) { searchThisAreaButton }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        // The bottom bar would sit under the results sheet, so this screen
        // hides it and carries its own tabs at the top instead. It comes back
        // on the storefront, which has no sheet over it.
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $isSheetPresented) {
            resultsSheet
                .presentationDetents(
                    [.height(140), .medium, .custom(BelowTopTabsDetent.self)],
                    selection: $sheetDetent
                )
                // Enabled at every detent, otherwise the top tabs stop
                // responding once the sheet is above `.medium`.
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .task {
            location.requestPermissionIfNeeded()
            if discover.results.isEmpty {
                await discover.search(near: location.effectiveCoordinate)
            }
        }
        .onChange(of: location.coordinate) { _, newValue in
            guard let newValue, !hasCenteredOnUser else { return }
            hasCenteredOnUser = true
            withAnimation {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: newValue.clCoordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                    )
                )
            }
            Task { await discover.search(near: newValue) }
        }
        .onChange(of: discover.selectedBusiness) { _, _ in
            // Hide the results sheet while a storefront is pushed, and
            // bring it back when the player navigates away from it.
            syncSheetPresentation()
        }
        .onChange(of: selectedTab) { _, _ in
            // The sheet is presented on the window, so it would stay up over
            // Orders and Profile if it were left presented on a tab switch.
            syncSheetPresentation()
        }
        .errorAlert(message: $discover.errorMessage)
    }

    private func syncSheetPresentation() {
        isSheetPresented = selectedTab == .discover && discover.selectedBusiness == nil
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $cameraPosition) {
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
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            let moved = discover.searchCenter.distanceMeters(to: Coordinate(context.region.center))
            showSearchThisArea = moved > 1_500
        }
    }

    @ViewBuilder
    private var searchThisAreaButton: some View {
        if showSearchThisArea {
            Button {
                guard let visibleRegion else { return }
                showSearchThisArea = false
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
            // Measured from the top of the map, which now starts under the
            // tab bar rather than under the status bar.
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Results sheet

    private var resultsSheet: some View {
        VStack(spacing: 0) {
            sheetHeader
            searchBar
            filterChips

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
                        Text("\(discover.filteredResults.count) nearby · \(discover.claimedCount) on Tensora")
                            .font(.caption)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
    }

    private var sheetHeader: some View {
        HStack {
            Text("Discover")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Spacer()
            if discover.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
            TextField("Search stringers or a city", text: $discover.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
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
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                FilterChip(title: "On Tensora", isOn: discover.claimedOnly) {
                    discover.claimedOnly.toggle()
                }
                ForEach(RacquetSport.allCases) { sport in
                    FilterChip(
                        title: sport.label,
                        systemImage: sport.iconName,
                        isOn: discover.sportFilter == sport
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

/// Tallest detent for the results sheet: `.large` would slide up over the top
/// tab bar, so stop the sheet just below it.
private struct BelowTopTabsDetent: CustomPresentationDetent {
    static func height(in context: Context) -> CGFloat? {
        max(context.maxDetentValue - PlayerTopTabBar.barHeight, 0)
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

struct FilterChip: View {
    let title: String
    var systemImage: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption)
                }
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

#Preview {
    DiscoverView(selectedTab: .constant(.discover))
        .environmentObject(DiscoverStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(LocationService())
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
}
