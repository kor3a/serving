import SwiftUI

/// Horizontal three-step progress bar:
/// `Order Confirmed → Order In Progress → Order Complete`.
///
/// Sits at the top of the order confirmation / detail screens.
struct OrderTrackerView: View {

    let currentStep: OrderTrackerStep?
    /// When the order was declined or cancelled the tracker is shown greyed
    /// out with a note instead of a step highlighted.
    var isCancelled: Bool = false
    /// Once the racquet is back with the player every step reads as done.
    var isFinished: Bool = false

    private let steps = OrderTrackerStep.allCases
    private let dotSize: CGFloat = 34

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(steps) { step in
                    stepColumn(for: step)
                }
            }
            // Connecting bars are drawn behind the columns so the circles stay
            // evenly spaced no matter how long the labels wrap.
            .background(connectors)

            if isCancelled {
                Text("This order was cancelled.")
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Pieces

    private func stepColumn(for step: OrderTrackerStep) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(fillColor(for: step))
                    .frame(width: dotSize, height: dotSize)

                Circle()
                    .stroke(strokeColor(for: step), lineWidth: 2)
                    .frame(width: dotSize, height: dotSize)

                Image(systemName: state(of: step) == .done ? "checkmark" : step.iconName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(iconColor(for: step))
            }
            .overlay(
                Circle()
                    .stroke(Theme.accent.opacity(0.25), lineWidth: 6)
                    .frame(width: dotSize + 8, height: dotSize + 8)
                    .opacity(state(of: step) == .current ? 1 : 0)
            )

            Text(step.title)
                .font(.caption.weight(state(of: step) == .current ? .bold : .regular))
                .foregroundStyle(state(of: step) == .upcoming ? Theme.secondaryText : Theme.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var connectors: some View {
        GeometryReader { proxy in
            let columnWidth = proxy.size.width / CGFloat(steps.count)
            let barWidth = max(0, columnWidth - dotSize - 12)

            ForEach(0..<(steps.count - 1), id: \.self) { index in
                Capsule()
                    .fill(state(of: steps[index]) == .done ? Theme.accent : Theme.separator)
                    .frame(width: barWidth, height: 3)
                    .position(x: columnWidth * CGFloat(index + 1), y: dotSize / 2)
            }
        }
    }

    // MARK: - State

    private enum StepState {
        case done
        case current
        case upcoming
    }

    private func state(of step: OrderTrackerStep) -> StepState {
        guard !isCancelled, let currentStep else { return .upcoming }
        if isFinished { return .done }
        if step.rawValue < currentStep.rawValue { return .done }
        if step.rawValue == currentStep.rawValue { return .current }
        return .upcoming
    }

    private func fillColor(for step: OrderTrackerStep) -> Color {
        switch state(of: step) {
        case .done, .current: return Theme.accent
        case .upcoming: return Theme.surfaceAlt
        }
    }

    private func strokeColor(for step: OrderTrackerStep) -> Color {
        switch state(of: step) {
        case .done, .current: return Theme.accent
        case .upcoming: return Theme.separator
        }
    }

    private func iconColor(for step: OrderTrackerStep) -> Color {
        switch state(of: step) {
        case .done, .current: return .white
        case .upcoming: return Theme.secondaryText
        }
    }

    private var accessibilityDescription: String {
        guard !isCancelled else { return "Order cancelled" }
        guard let currentStep else { return "Order not yet confirmed" }
        if isFinished { return "Order picked up" }
        return "Order progress: \(currentStep.title), step \(currentStep.rawValue + 1) of \(steps.count)"
    }
}

extension OrderTrackerView {
    /// The tracker for wherever `order` currently is.
    init(order: Order) {
        self.init(
            currentStep: order.trackerStep,
            isCancelled: order.status == .cancelled || order.status == .declined,
            isFinished: order.status == .pickedUp
        )
    }
}

#Preview("Tracker states") {
    VStack(spacing: 32) {
        OrderTrackerView(currentStep: .confirmed)
        OrderTrackerView(currentStep: .inProgress)
        OrderTrackerView(currentStep: .complete)
        OrderTrackerView(currentStep: .complete, isFinished: true)
        OrderTrackerView(currentStep: nil, isCancelled: true)
    }
    .padding()
    .screenBackground()
}
