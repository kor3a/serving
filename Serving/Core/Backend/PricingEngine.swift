import Foundation

/// Order math, shared by the checkout preview and the backend mock so the
/// number the player sees before submitting matches the order they get back.
///
/// The live backend is the source of truth — `LiveBackend` returns a server
/// computed `PriceBreakdown` and the app displays that, using this engine only
/// for the pre-submit estimate.
enum PricingEngine {

    /// Serving's cut, added on top of the stringer's prices.
    static let platformFeeRate: Decimal = 0.06
    static let platformFeeMinimum: Decimal = 1.49
    /// Placeholder rate — the live backend resolves tax by the drop-off address.
    static let estimatedTaxRate: Decimal = 0.0913

    static func breakdown(
        racquets: [RacquetItem],
        service: StringingService?,
        business: StringerBusiness
    ) -> PriceBreakdown {
        let stringsSubtotal = racquets.reduce(Decimal(0)) { $0 + $1.stringSelection.price }

        let laborPrice = service?.laborPrice ?? 0
        let laborSubtotal = laborPrice * Decimal(racquets.count)

        let byosCount = racquets.filter(\.stringSelection.isBringYourOwn).count
        // A stringer can set a flat BYOS labor fee that replaces nothing —
        // it is charged per racquet where the player supplies the string.
        let byosFee = business.bringYourOwnStringFee * Decimal(byosCount)

        let merchandise = stringsSubtotal + laborSubtotal + byosFee
        let serviceFee = max(platformFeeMinimum, merchandise * platformFeeRate)
        let tax = (stringsSubtotal + byosFee) * estimatedTaxRate

        return PriceBreakdown(
            stringsSubtotal: stringsSubtotal.roundedToCents,
            laborSubtotal: laborSubtotal.roundedToCents,
            bringYourOwnStringFee: byosFee.roundedToCents,
            serviceFee: serviceFee.roundedToCents,
            tax: tax.roundedToCents
        )
    }
}
