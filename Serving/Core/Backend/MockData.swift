import Foundation

/// Seed data for previews and for running the app without a backend.
enum MockData {

    static let playerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let businessOwnerID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    static let baseCoordinate = Coordinate(latitude: 37.3688, longitude: -122.0363) // Sunnyvale, CA

    // MARK: - Users

    static let player = AppUser(
        id: playerID,
        email: "player@serving.app",
        accountType: .player,
        displayName: "Alex Rivera",
        phone: "(408) 555-0134",
        phoneVerified: true
    )

    static var businessOwner: AppUser {
        AppUser(
            id: businessOwnerID,
            email: "shop@serving.app",
            accountType: .business,
            displayName: "Baseline String Lab",
            ownerName: "Jordan Kim",
            phone: "(408) 555-0110",
            phoneVerified: true,
            businessID: claimedBusinessID
        )
    }

    // MARK: - Businesses

    static let claimedBusinessID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    static func makeBusinesses() -> [StringerBusiness] {
        [
            baselineStringLab(),
            garageStringer(),
            smashBadmintonWorks(),
            .unclaimed(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                name: "Courtside Racquet Sports",
                phone: "(408) 555-0182",
                address: PostalAddress(
                    line1: "1201 W El Camino Real",
                    city: "Mountain View",
                    state: "CA",
                    postalCode: "94040"
                ),
                coordinate: Coordinate(latitude: 37.3835, longitude: -122.0961)
            ),
            .unclaimed(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                name: "Peninsula Tennis Shop",
                phone: "(650) 555-0117",
                address: PostalAddress(
                    line1: "455 Ramona St",
                    city: "Palo Alto",
                    state: "CA",
                    postalCode: "94301"
                ),
                coordinate: Coordinate(latitude: 37.4443, longitude: -122.1610)
            )
        ]
    }

    static func baselineStringLab() -> StringerBusiness {
        StringerBusiness(
            id: claimedBusinessID,
            name: "Baseline String Lab",
            ownerName: "Jordan Kim",
            phone: "(408) 555-0110",
            address: PostalAddress(
                line1: "845 E Duane Ave",
                line2: "Suite B",
                city: "Sunnyvale",
                state: "CA",
                postalCode: "94085"
            ),
            coordinate: Coordinate(latitude: 37.3760, longitude: -122.0210),
            locationKind: .storefront,
            isClaimed: true,
            about: "USRSA certified stringer. Wilson Baiardo machine, two-piece jobs on request. Same-day service available if dropped off before noon.",
            rating: 4.9,
            ratingCount: 213,
            typicalTurnaroundHours: 24,
            acceptsBringYourOwnString: true,
            bringYourOwnStringFee: 22,
            dropOffInstructions: "Ring the bell at the side entrance of Suite B. Racquet bin is inside the door.",
            services: [
                StringingService(
                    id: UUID(uuidString: "aaaaaaa1-0000-0000-0000-000000000001")!,
                    name: "Standard Stringing",
                    details: "One-piece install, logo stencil on request.",
                    laborPrice: 22,
                    turnaroundHours: 24
                ),
                StringingService(
                    id: UUID(uuidString: "aaaaaaa1-0000-0000-0000-000000000002")!,
                    name: "Rush (Same Day)",
                    details: "Dropped off before noon, ready by 6 PM.",
                    laborPrice: 35,
                    turnaroundHours: 8
                ),
                StringingService(
                    id: UUID(uuidString: "aaaaaaa1-0000-0000-0000-000000000003")!,
                    name: "Hybrid Setup",
                    details: "Two-piece, different string in mains and crosses.",
                    laborPrice: 28,
                    turnaroundHours: 24
                )
            ],
            inventory: [
                StringProduct(
                    id: UUID(uuidString: "bbbbbbb1-0000-0000-0000-000000000001")!,
                    brand: "Luxilon",
                    name: "ALU Power",
                    category: .polyester,
                    gauge: "16L / 1.25mm",
                    price: 24,
                    stockCount: 14,
                    details: "The control benchmark. Crisp, low powered, holds tension well."
                ),
                StringProduct(
                    id: UUID(uuidString: "bbbbbbb1-0000-0000-0000-000000000002")!,
                    brand: "Babolat",
                    name: "RPM Blast",
                    category: .polyester,
                    gauge: "17 / 1.25mm",
                    price: 21,
                    stockCount: 9,
                    details: "Octagonal shape for extra bite and spin."
                ),
                StringProduct(
                    id: UUID(uuidString: "bbbbbbb1-0000-0000-0000-000000000003")!,
                    brand: "Wilson",
                    name: "NXT Comfort",
                    category: .multifilament,
                    gauge: "16 / 1.30mm",
                    price: 19,
                    stockCount: 22,
                    details: "Soft multifilament, easy on the arm."
                ),
                StringProduct(
                    id: UUID(uuidString: "bbbbbbb1-0000-0000-0000-000000000004")!,
                    brand: "Wilson",
                    name: "Natural Gut 16",
                    category: .naturalGut,
                    gauge: "16 / 1.30mm",
                    price: 48,
                    stockCount: 4,
                    details: "Premium feel and tension maintenance."
                ),
                StringProduct(
                    id: UUID(uuidString: "bbbbbbb1-0000-0000-0000-000000000005")!,
                    brand: "Prince",
                    name: "Synthetic Gut Duraflex",
                    category: .syntheticGut,
                    gauge: "16 / 1.30mm",
                    price: 12,
                    stockCount: 30,
                    details: "Reliable all-round string at a friendly price."
                )
            ],
            openHours: standardHours()
        )
    }

    static func garageStringer() -> StringerBusiness {
        StringerBusiness(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            name: "Cross & Main Stringing",
            ownerName: "Priya Nair",
            phone: "(408) 555-0166",
            address: PostalAddress(
                line1: "Las Palmas Park — Parking Lot A",
                city: "Sunnyvale",
                state: "CA",
                postalCode: "94086"
            ),
            coordinate: Coordinate(latitude: 37.3542, longitude: -122.0198),
            locationKind: .publicMeetingSpot,
            isClaimed: true,
            about: "Home-based stringer, 10 years on tour vans. Meet-ups at Las Palmas Park courts most evenings.",
            rating: 4.8,
            ratingCount: 87,
            typicalTurnaroundHours: 48,
            acceptsBringYourOwnString: true,
            bringYourOwnStringFee: 18,
            dropOffInstructions: "Meet at the bench by court 3. Text when you're 5 minutes out.",
            services: [
                StringingService(
                    id: UUID(uuidString: "aaaaaaa2-0000-0000-0000-000000000001")!,
                    name: "Standard Stringing",
                    details: "One-piece install.",
                    laborPrice: 18,
                    turnaroundHours: 48
                ),
                StringingService(
                    id: UUID(uuidString: "aaaaaaa2-0000-0000-0000-000000000002")!,
                    name: "Badminton Restring",
                    details: "Up to 30 lbs, four-knot method.",
                    laborPrice: 16,
                    turnaroundHours: 48
                )
            ],
            inventory: [
                StringProduct(
                    id: UUID(uuidString: "bbbbbbb2-0000-0000-0000-000000000001")!,
                    brand: "Solinco",
                    name: "Hyper-G",
                    category: .polyester,
                    gauge: "17 / 1.20mm",
                    price: 20,
                    stockCount: 11,
                    details: "Square profile, big spin, popular with juniors."
                ),
                StringProduct(
                    id: UUID(uuidString: "bbbbbbb2-0000-0000-0000-000000000002")!,
                    brand: "Yonex",
                    name: "BG-65",
                    category: .badminton,
                    sport: .badminton,
                    gauge: "0.70mm",
                    price: 14,
                    stockCount: 25,
                    details: "Durable badminton string, the club standard."
                )
            ],
            openHours: eveningHours()
        )
    }

    static func smashBadmintonWorks() -> StringerBusiness {
        StringerBusiness(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            name: "Smash Badminton Works",
            ownerName: "Wei Chen",
            phone: "(408) 555-0193",
            address: PostalAddress(
                line1: "2190 S Bascom Ave",
                city: "Campbell",
                state: "CA",
                postalCode: "95008"
            ),
            coordinate: Coordinate(latitude: 37.2872, longitude: -121.9320),
            locationKind: .storefront,
            isClaimed: true,
            about: "Badminton specialists. Constant-pull machine, tensions up to 35 lbs.",
            rating: 4.7,
            ratingCount: 141,
            typicalTurnaroundHours: 36,
            acceptsBringYourOwnString: true,
            bringYourOwnStringFee: 15,
            dropOffInstructions: "Front counter, ask for the stringing desk.",
            services: [
                StringingService(
                    id: UUID(uuidString: "aaaaaaa3-0000-0000-0000-000000000001")!,
                    name: "Badminton Restring",
                    details: "Four-knot, pre-stretch included.",
                    laborPrice: 15,
                    turnaroundHours: 36
                )
            ],
            inventory: [
                StringProduct(
                    id: UUID(uuidString: "bbbbbbb3-0000-0000-0000-000000000001")!,
                    brand: "Yonex",
                    name: "Aerobite",
                    category: .badminton,
                    sport: .badminton,
                    gauge: "0.67mm",
                    price: 22,
                    stockCount: 18,
                    details: "Hybrid feel, extra shuttle grip for spin."
                ),
                StringProduct(
                    id: UUID(uuidString: "bbbbbbb3-0000-0000-0000-000000000002")!,
                    brand: "Li-Ning",
                    name: "No.1 Boost",
                    category: .badminton,
                    sport: .badminton,
                    gauge: "0.68mm",
                    price: 16,
                    stockCount: 12,
                    details: "Loud, crisp response."
                )
            ],
            openHours: standardHours()
        )
    }

    static func standardHours() -> [OpenHours] {
        (1...7).map { weekday in
            OpenHours(
                weekday: weekday,
                opensAtMinutes: 10 * 60,
                closesAtMinutes: 19 * 60,
                isClosed: weekday == 1
            )
        }
    }

    static func eveningHours() -> [OpenHours] {
        (1...7).map { weekday in
            OpenHours(
                weekday: weekday,
                opensAtMinutes: 17 * 60,
                closesAtMinutes: 21 * 60,
                isClosed: weekday == 1 || weekday == 7
            )
        }
    }

    // MARK: - Orders

    static func makeOrders() -> [Order] {
        let shop = baselineStringLab()
        let alu = shop.inventory[0]
        let nxt = shop.inventory[2]
        let calendar = Calendar.current
        let now = Date()

        let confirmed = Order(
            id: UUID(uuidString: "99999999-0000-0000-0000-000000000001")!,
            orderNumber: "TN-4821",
            businessID: shop.id,
            businessName: shop.name,
            businessPhone: shop.phone,
            playerID: playerID,
            playerName: player.displayName,
            playerPhone: player.phone,
            racquets: [
                RacquetItem(
                    sport: .tennis,
                    model: "Babolat Pure Aero 98",
                    stringSelection: .fromStorefront(productID: alu.id, productName: alu.displayName, price: alu.price),
                    mainTension: 52,
                    crossTension: 50,
                    notes: "Logo stencil please."
                )
            ],
            serviceID: shop.services[0].id,
            serviceName: shop.services[0].name,
            dropOffDate: calendar.date(byAdding: .hour, value: 20, to: now) ?? now,
            dropOffAddress: shop.address,
            dropOffInstructions: shop.dropOffInstructions,
            proposedPickUpDate: calendar.date(byAdding: .hour, value: 44, to: now),
            confirmedPickUpDate: calendar.date(byAdding: .hour, value: 44, to: now),
            businessNote: "Got you covered — ready the next evening.",
            pricing: PriceBreakdown(
                stringsSubtotal: alu.price,
                laborSubtotal: shop.services[0].laborPrice,
                bringYourOwnStringFee: 0,
                serviceFee: PricingEngine.playerServiceFee,
                stringerCommission: PricingEngine.stringerCommission(on: alu.price + shop.services[0].laborPrice),
                tax: 4.24
            ),
            payment: PaymentRecord(
                method: .applePay,
                state: .succeeded,
                paymentIntentID: "pi_mock_4821",
                chargedAt: calendar.date(byAdding: .hour, value: -3, to: now),
                last4: "4242"
            ),
            status: .confirmed,
            createdAt: calendar.date(byAdding: .hour, value: -4, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .hour, value: -3, to: now) ?? now
        )

        let awaitingBusiness = Order(
            id: UUID(uuidString: "99999999-0000-0000-0000-000000000002")!,
            orderNumber: "TN-4830",
            businessID: shop.id,
            businessName: shop.name,
            businessPhone: shop.phone,
            playerID: playerID,
            playerName: player.displayName,
            playerPhone: player.phone,
            racquets: [
                RacquetItem(
                    sport: .tennis,
                    model: "Yonex EZONE 100",
                    stringSelection: .bringYourOwn(description: "Solinco Tour Bite 17"),
                    mainTension: 48,
                    crossTension: 48,
                    notes: ""
                ),
                RacquetItem(
                    sport: .tennis,
                    model: "Yonex EZONE 100",
                    stringSelection: .fromStorefront(productID: nxt.id, productName: nxt.displayName, price: nxt.price),
                    mainTension: 54,
                    crossTension: 54,
                    notes: ""
                )
            ],
            serviceID: shop.services[0].id,
            serviceName: shop.services[0].name,
            dropOffDate: calendar.date(byAdding: .day, value: 2, to: now) ?? now,
            dropOffAddress: shop.address,
            dropOffInstructions: shop.dropOffInstructions,
            proposedPickUpDate: nil,
            confirmedPickUpDate: nil,
            businessNote: nil,
            pricing: PriceBreakdown(
                stringsSubtotal: nxt.price,
                laborSubtotal: shop.services[0].laborPrice * 2,
                bringYourOwnStringFee: shop.bringYourOwnStringFee,
                serviceFee: PricingEngine.playerServiceFee,
                stringerCommission: PricingEngine.stringerCommission(
                    on: nxt.price + shop.services[0].laborPrice * 2 + shop.bringYourOwnStringFee
                ),
                tax: 7.31
            ),
            payment: .unpaid(method: .applePay),
            status: .awaitingBusiness,
            createdAt: calendar.date(byAdding: .minute, value: -35, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .minute, value: -35, to: now) ?? now
        )

        let pickedUp = Order(
            id: UUID(uuidString: "99999999-0000-0000-0000-000000000003")!,
            orderNumber: "TN-4699",
            businessID: shop.id,
            businessName: shop.name,
            businessPhone: shop.phone,
            playerID: playerID,
            playerName: player.displayName,
            playerPhone: player.phone,
            racquets: [
                RacquetItem(
                    sport: .tennis,
                    model: "Babolat Pure Aero 98",
                    stringSelection: .fromStorefront(productID: alu.id, productName: alu.displayName, price: alu.price),
                    mainTension: 52,
                    crossTension: 50,
                    notes: ""
                )
            ],
            serviceID: shop.services[0].id,
            serviceName: shop.services[0].name,
            dropOffDate: calendar.date(byAdding: .day, value: -9, to: now) ?? now,
            dropOffAddress: shop.address,
            dropOffInstructions: shop.dropOffInstructions,
            proposedPickUpDate: calendar.date(byAdding: .day, value: -8, to: now),
            confirmedPickUpDate: calendar.date(byAdding: .day, value: -8, to: now),
            businessNote: nil,
            pricing: confirmed.pricing,
            payment: PaymentRecord(
                method: .card,
                state: .succeeded,
                paymentIntentID: "pi_mock_4699",
                chargedAt: calendar.date(byAdding: .day, value: -9, to: now),
                last4: "4242"
            ),
            status: .pickedUp,
            createdAt: calendar.date(byAdding: .day, value: -10, to: now) ?? now,
            updatedAt: calendar.date(byAdding: .day, value: -8, to: now) ?? now
        )

        return [awaitingBusiness, confirmed, pickedUp]
    }

    static func makeEarnings() -> EarningsSnapshot {
        EarningsSnapshot(
            pendingPayout: 184.50,
            paidOutThisMonth: 1_260.75,
            grossThisWeek: 412.00,
            completedOrdersThisMonth: 38,
            nextPayoutDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
            payoutStatus: .active
        )
    }
}
