import SwiftUI

/// The order the player last continued to checkout with, waiting to be
/// submitted, or an empty cart if there isn't one.
struct CartView: View {

    /// Sends the player to Discover to pick a stringer.
    var onFindStringer: () -> Void

    @EnvironmentObject private var cart: CartStore
    @State private var submittedOrder: Order?

    var body: some View {
        NavigationStack {
            Group {
                if let builder = cart.builder {
                    CheckoutView(builder: builder) { order in
                        submittedOrder = order
                    }
                } else {
                    EmptyStateView(
                        iconName: "cart",
                        title: "Your cart is empty",
                        message: "Choose a stringer and continue to checkout. Your order waits here until you submit it.",
                        actionTitle: "Find a stringer",
                        action: onFindStringer
                    )
                    .frame(maxHeight: .infinity)
                    .screenBackground()
                    .navigationTitle("Cart")
                }
            }
            // On the stack's root rather than the checkout, which leaves the
            // cart as soon as the order is submitted.
            .navigationDestination(item: $submittedOrder) { order in
                OrderDetailView(orderID: order.id)
            }
        }
    }
}

#Preview {
    CartView(onFindStringer: {})
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
        .environmentObject(CartStore())
}
