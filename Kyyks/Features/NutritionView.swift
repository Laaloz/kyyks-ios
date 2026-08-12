import SwiftUI

/// Ravinto-välilehti: päivän makrotilanne tavoitteeseen verrattuna ja
/// ateriat ateriapaikoittain. Päivää voi selata eteen ja taakse.
struct NutritionView: View {
    let auth: AuthManager

    @State private var model = NutritionModel()

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    macroSummary
                }

                ForEach(MealTag.allCases, id: \.self) { tag in
                    let entries = model.entries(for: tag)
                    if !entries.isEmpty {
                        Section {
                            ForEach(entries) { entry in
                                NutritionRow(entry: entry)
                            }
                        } header: {
                            HStack {
                                Text(tag.label)
                                Spacer()
                                Text("\(Int(entries.reduce(0) { $0 + $1.macros.kcal })) kcal")
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                if model.day?.entries.isEmpty ?? false {
                    Section {
                        Text("Ei kirjauksia tälle päivälle.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Ravinto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { dateToolbar }
            .overlay { if model.isLoading && model.day == nil { ProgressView() } }
            .refreshable { await model.refresh() }
        }
        .task {
            model.configure(auth: auth)
            await model.load()
        }
    }

    @ToolbarContentBuilder
    private var dateToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await model.shiftDay(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Edellinen päivä")
        }
        ToolbarItem(placement: .principal) {
            Text(model.dateLabel)
                .font(.headline)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await model.shiftDay(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(model.isToday)
            .accessibilityLabel("Seuraava päivä")
        }
    }

    private var macroSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(model.totals.kcal))")
                    .font(.largeTitle.bold())
                    .monospacedDigit()
                if let target = model.day?.target {
                    Text("/ \(Int(target.kcal)) kcal")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("kcal").foregroundStyle(.secondary)
                }
                Spacer()
                if let remaining = model.remainingKcal {
                    Text(remaining >= 0 ? "\(remaining) jäljellä" : "\(-remaining) yli")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(remaining >= 0 ? Color.secondary : Color.orange)
                        .monospacedDigit()
                }
            }

            if let target = model.day?.target {
                ProgressView(value: min(model.totals.kcal, target.kcal), total: max(target.kcal, 1))
                    .tint(model.totals.kcal > target.kcal ? .orange : .accentColor)

                HStack(spacing: 12) {
                    macroBar("Proteiini", model.totals.proteinG, target.proteinG, .blue)
                    macroBar("Hiilihydraatit", model.totals.carbsG, target.carbsG, .green)
                    macroBar("Rasva", model.totals.fatG, target.fatG, .purple)
                }
            } else {
                Text("Aseta ravintotavoitteet webissä, niin näet edistymisen tässä.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func macroBar(_ title: String, _ value: Double, _ target: Double, _ color: Color) -> some View {
        // Tavoitteen ylitys näkyy samalla varoitusvärillä kuin kaloreissa,
        // jotta täysi palkki ei tarkoita kahta eri asiaa.
        let isOver = value > target
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            ProgressView(value: min(value, target), total: max(target, 1))
                .tint(isOver ? Color.orange : color)
            Text("\(Int(value)) / \(Int(target)) g")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(isOver ? Color.orange : Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(Int(value)) grammaa tavoitteesta \(Int(target))\(isOver ? ", tavoite ylittyy" : "")")
    }
}

private struct NutritionRow: View {
    let entry: NutritionEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                // Ei syöty-merkkiä: lisätty ateria on määritelmällisesti syöty
                // (myös illalla kirjattu koko päivä), joten merkki olisi kohinaa.
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(entry.isFailedEstimate ? .red : .secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if entry.isPendingEstimate {
                ProgressView()
            } else {
                Text("\(Int(entry.macros.kcal)) kcal")
                    .font(.subheadline)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if entry.isPendingEstimate { return "Arvioidaan…" }
        if entry.isFailedEstimate { return "Arvio ei onnistunut" }
        var parts: [String] = []
        if entry.kind == "food", let grams = entry.grams, grams > 0 {
            parts.append("\(Int(grams)) g")
        } else if entry.kind == "recipe" {
            let servings = entry.servings
            let text = servings.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(servings)) : String(format: "%.1f", servings)
            parts.append("\(text) annosta")
        }
        parts.append("P \(Int(entry.macros.proteinG)) · H \(Int(entry.macros.carbsG)) · R \(Int(entry.macros.fatG))")
        return parts.joined(separator: " · ")
    }
}

@Observable
@MainActor
final class NutritionModel {
    private(set) var day: NutritionDay?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var selectedDate = Date.now

    private var api: APIClient?

    var totals: MacroValues { day?.totals ?? MacroValues(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0) }

    var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }

    var dateLabel: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Tänään" }
        if Calendar.current.isDateInYesterday(selectedDate) { return "Eilen" }
        return selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month())
    }

    var remainingKcal: Int? {
        guard let target = day?.target else { return nil }
        return Int((target.kcal - totals.kcal).rounded())
    }

    private var dateKey: String {
        // Paikallinen päiväavain — sama muoto kuin webin plan_date.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        return formatter.string(from: selectedDate)
    }

    private var cacheKey: String { "nutrition-\(dateKey)" }

    func configure(auth: AuthManager) {
        api = APIClient(auth: auth)
    }

    func entries(for tag: MealTag) -> [NutritionEntry] {
        (day?.entries ?? []).filter { $0.mealTag == tag.rawValue }.sorted { $0.position < $1.position }
    }

    func load() async {
        if let cached = await ResponseCache.shared.read(cacheKey) {
            apply(cached)
        } else {
            isLoading = true
        }
        await refresh()
        isLoading = false
    }

    func shiftDay(by days: Int) async {
        guard let shifted = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        if days > 0 && shifted > Date.now { return }
        selectedDate = shifted
        day = nil
        await load()
    }

    func refresh() async {
        guard let api else { return }
        do {
            let data = try await api.get("/api/mobile/nutrition?date=\(dateKey)")
            await ResponseCache.shared.write(cacheKey, data: data)
            apply(data)
            errorMessage = nil
        } catch {
            if day == nil {
                errorMessage = "Ravintotietojen haku epäonnistui."
            }
        }
    }

    private func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(NutritionDay.self, from: data), decoded.date == dateKey else { return }
        day = decoded
    }
}
