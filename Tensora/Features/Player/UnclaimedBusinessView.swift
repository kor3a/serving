import MapKit
import SwiftUI

/// Shown for shops that appear on the map but have no Tensora account yet.
/// There is nothing to book here — just the details needed to call them.
struct UnclaimedBusinessView: View {

    let business: StringerBusiness
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header

                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        contactRow(
                            icon: "phone.fill",
                            title: "Phone",
                            value: business.phone.isEmpty ? "Not listed" : business.phone
                        )
                        Divider().overlay(Theme.separator)
                        contactRow(
                            icon: "mappin.and.ellipse",
                            title: "Address",
                            value: business.address.multiLine
                        )
                    }
                }

                VStack(spacing: Theme.Spacing.sm) {
                    Button {
                        callBusiness()
                    } label: {
                        Label("Call to schedule", systemImage: "phone.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(business.phone.isEmpty)

                    Button {
                        openInMaps()
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }

                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Not on Tensora yet", systemImage: "info.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.court)
                        Text("This shop hasn't set up a Tensora storefront, so ordering, string selection and scheduling aren't available. Call them directly to book a stringing.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Button("Invite them to Tensora") {
                            inviteBusiness()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 4)
                    }
                }

                miniMap
            }
            .padding(Theme.Spacing.lg)
        }
        .screenBackground()
        .navigationTitle(business.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(business.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            Text(business.address.oneLine)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func contactRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var miniMap: some View {
        Map(initialPosition: .region(
            MKCoordinateRegion(
                center: business.coordinate.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        )) {
            Marker(business.name, systemImage: "mappin", coordinate: business.coordinate.clCoordinate)
                .tint(Theme.secondaryText)
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .allowsHitTesting(false)
    }

    // MARK: - Actions

    private func callBusiness() {
        let digits = business.phone.phoneDigits
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        openURL(url)
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: business.coordinate.clCoordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = business.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func inviteBusiness() {
        let subject = "Set up your stringing shop on Tensora"
        let body = "Hi \(business.name),\n\nI use Tensora to book racquet stringing. Setting up a storefront would let players order and schedule drop-offs with you directly."
        var components = URLComponents(string: "mailto:")
        components?.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components?.url { openURL(url) }
    }
}

#Preview {
    NavigationStack {
        UnclaimedBusinessView(
            business: .unclaimed(
                name: "Courtside Racquet Sports",
                phone: "(408) 555-0182",
                address: PostalAddress(line1: "1201 W El Camino Real", city: "Mountain View", state: "CA", postalCode: "94040"),
                coordinate: Coordinate(latitude: 37.3835, longitude: -122.0961)
            )
        )
    }
}
