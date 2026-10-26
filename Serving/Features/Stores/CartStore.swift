import Foundation
import SwiftUI

/// The order the player has taken to checkout but not submitted yet, shown in
/// the Cart tab.
///
/// The cart holds one stringer's order at a time: continuing to checkout at
/// another storefront replaces it. It shares the storefront's builder, so
/// changes made on either screen show up on both.
@MainActor
final class CartStore: ObservableObject {

    @Published private(set) var builder: OrderBuilder?

    var isEmpty: Bool { builder == nil }

    /// Puts an order in the cart once the player reaches checkout with it.
    func hold(_ builder: OrderBuilder) {
        guard !builder.isSubmitted, self.builder !== builder else { return }
        self.builder = builder
    }

    /// Takes the order out of the cart, if it's still the one in there.
    func clear(_ builder: OrderBuilder) {
        guard self.builder === builder else { return }
        self.builder = nil
    }
}
