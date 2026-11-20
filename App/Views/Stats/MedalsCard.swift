import SwiftUI

/// Medal history: totals, a six-week calendar and the latest sessions.
struct MedalsCard: View {
    let stats: MedalStats
    let lessons: [Lesson]

    private static let weekdays = [String(localized: "Пн"), String(localized: "Вт"), String(localized: "Ср"), String(localized: "Чт"), String(localized: "Пт"), String(localized: "Сб"), String(localized: "Вс")]

    var body: some View {
        Card {
            HStack {
                CardLabel(text: String(localized: "Медали дня"))
                Spacer()
                Image(systemName: "medal.fill").foregroundStyle(Theme.accent)
            }

            HStack(spacing: 0) {
                number("\(stats.total)", String(localized: "всего"))
                Divider().frame(height: 36)
                number("\(stats.thisWeek)", String(localized: "на этой неделе"))
                Divider().frame(height: 36)
                number("\(stats.streak)", dayWord(stats.streak) + inARowWord(stats.streak))
                Divider().frame(height: 36)
                number(stats.bestMinutes.map { "\($0)" } ?? "—", String(localized: "лучшее время, мин"))
            }

            // Calendar: a column per weekday, a row per week, oldest on top.
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    ForEach(Self.weekdays, id: \.self) { d in
                        Text(d).font(.s(.caption2)).foregroundStyle(Theme.secondaryText)
                    }
                }
                ForEach(0..<(stats.days.count / 7), id: \.self) { week in
                    GridRow {
                        ForEach(stats.days[(week * 7)..<(week * 7 + 7)]) { day in DayCell(day: day) }
                    }
                }
            }
            .frame(maxWidth: 420)

            HStack(spacing: 14) {
                legend(Theme.accent, String(localized: "медаль"))
                legend(Theme.accentRamp[0], String(localized: "сессия без медали"))
                legend(Theme.tile, String(localized: "без сессии"))
            }

            if stats.recent.isEmpty {
                Text(String(localized: "Пройди учебную сессию в верхней панели: все 4 шага за 40 минут — медаль дня."))
                    .font(.s(.subheadline))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(stats.recent) { s in
                        Divider()
                        HStack(spacing: 10) {
                            Image(systemName: s.medal ? "medal.fill" : "checkmark.circle")
                                .foregroundStyle(s.medal ? Theme.accent : Theme.secondaryText)
                            Text(s.finishedAt.formatted(.dateTime.day().month(.wide).locale(AppLanguage.locale)))
                                .font(.s(.subheadline).weight(.semibold))
                            Text(lessons.first { $0.id == s.lessonID }?.title ?? "")
                                .font(.s(.subheadline))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(String(localized: "\(s.minutes) мин")).font(.s(.subheadline).monospacedDigit())
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
    }

    private func number(_ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.s(.title2).weight(.bold).monospacedDigit())
            Text(title).font(.s(.caption)).foregroundStyle(Theme.secondaryText).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(title).font(.s(.caption)).foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct DayCell: View {
    let day: MedalStats.Day

    var body: some View {
        let future = day.date > .now
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(fill.opacity(future ? 0.4 : 1))
            if day.kind == .medal {
                Image(systemName: "medal.fill").font(.s(.caption)).foregroundStyle(Theme.onAccent)
            } else {
                Text(day.date.formatted(.dateTime.day())).font(.s(.caption2))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(height: 30)
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(day.isToday ? Theme.accent : .clear, lineWidth: 1.5))
        .accessibilityLabel(day.date.formatted(date: .long, time: .omitted) + ": "
                            + (day.kind == .medal ? String(localized: "медаль") : day.kind == .session ? String(localized: "сессия") : String(localized: "нет")))
    }

    private var fill: Color {
        switch day.kind {
        case .medal: Theme.accent
        case .session: Theme.accentRamp[0]
        case .none: Theme.tile
        }
    }
}
