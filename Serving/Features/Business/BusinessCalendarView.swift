import SwiftUI

/// Month view of everything booked: drop-offs coming in and pick-ups due.
struct BusinessCalendarView: View {

    @EnvironmentObject private var orders: OrderStore

    @State private var visibleMonth = Date().startOfMonth
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var dropOffsByDay: [Date: [Order]] { orders.ordersByDropOffDay() }
    private var pickUpsByDay: [Date: [Order]] { orders.ordersByPickUpDay() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    monthHeader
                    weekdayHeader
                    monthGrid
                    dayDetail
                }
                .padding(Theme.Spacing.md)
            }
            .screenBackground()
            .navigationTitle("Calendar")
            .refreshable { await orders.refresh() }
            .task { await orders.refresh() }
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }

            Spacer()

            Text(visibleMonth.monthYearLabel)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)

            Spacer()

            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, Theme.Spacing.sm)
    }

    /// Weekday initials rotated so column 0 matches `Calendar.firstWeekday`.
    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        guard offset > 0, offset < symbols.count else { return symbols }
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 52)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day)
        let dropOffs = dropOffsByDay[day]?.count ?? 0
        let pickUps = pickUpsByDay[day]?.count ?? 0

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : Theme.primaryText)

                HStack(spacing: 3) {
                    if dropOffs > 0 {
                        Circle()
                            .fill(isSelected ? Color.white : Theme.court)
                            .frame(width: 5, height: 5)
                    }
                    if pickUps > 0 {
                        Circle()
                            .fill(isSelected ? Color.white : Theme.accent)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(isSelected ? Theme.accent : (isToday ? Theme.accent.opacity(0.12) : Theme.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .stroke(Theme.separator, lineWidth: isSelected ? 0 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Day detail

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(
                title: selectedDay.dayLabel,
                subtitle: "\(dropOffsForSelectedDay.count) drop-off(s) · \(pickUpsForSelectedDay.count) pick-up(s)"
            )

            legend

            if dropOffsForSelectedDay.isEmpty && pickUpsForSelectedDay.isEmpty {
                Card {
                    Text("Nothing booked for this day.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                ForEach(dropOffsForSelectedDay) { order in
                    NavigationLink {
                        BusinessOrderDetailView(orderID: order.id)
                    } label: {
                        calendarRow(order: order, kind: "Drop off", time: order.dropOffDate, tint: Theme.court)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(pickUpsForSelectedDay) { order in
                    NavigationLink {
                        BusinessOrderDetailView(orderID: order.id)
                    } label: {
                        calendarRow(
                            order: order,
                            kind: "Pick up",
                            time: order.effectivePickUpDate ?? order.dropOffDate,
                            tint: Theme.accent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: 5) {
                Circle().fill(Theme.court).frame(width: 6, height: 6)
                Text("Drop-off").font(.caption2).foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 5) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                Text("Pick-up").font(.caption2).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
    }

    private func calendarRow(order: Order, kind: String, time: Date, tint: Color) -> some View {
        Card(padding: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                VStack(spacing: 2) {
                    Text(time.timeLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                    Text(kind)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(width: 62)

                Rectangle()
                    .fill(tint)
                    .frame(width: 3)
                    .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 2) {
                    Text(order.playerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("\(order.orderNumber) · \(order.racquetCountText)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer(minLength: 0)

                Badge(text: order.status.label, tint: order.status.tint)
            }
        }
    }

    // MARK: - Data

    private var dropOffsForSelectedDay: [Order] {
        (dropOffsByDay[calendar.startOfDay(for: selectedDay)] ?? [])
            .sorted { $0.dropOffDate < $1.dropOffDate }
    }

    private var pickUpsForSelectedDay: [Order] {
        (pickUpsByDay[calendar.startOfDay(for: selectedDay)] ?? [])
            .sorted { ($0.effectivePickUpDate ?? .distantFuture) < ($1.effectivePickUpDate ?? .distantFuture) }
    }

    /// Days of the visible month, padded with `nil` so the first day lands on
    /// the right weekday column.
    private var monthDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: visibleMonth)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: visibleMonth) {
                days.append(calendar.startOfDay(for: date))
            }
        }
        return days
    }

    private func shiftMonth(by months: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: months, to: visibleMonth) else { return }
        visibleMonth = shifted.startOfMonth
    }
}

extension Date {
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }

    var monthYearLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: self)
    }
}

#Preview {
    BusinessCalendarView()
        .environmentObject(OrderStore(backend: AppEnvironment.previewBackend()))
}
