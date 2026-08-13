import Charts
import SwiftUI

/// Liikekohtainen kehitys: liikelista e1RM-nykytasolla ja liikkeen oma
/// historianäkymä. Palvelin laskee yhteenvedot valmiiksi
/// (`/api/mobile/exercise-progress`) — clientille lähetettävä vaihtoehto olisi
/// koko sarjaloki.
struct ExerciseProgressListView: View {
    let auth: AuthManager

    @State private var model = ExerciseProgressModel()
    @State private var query = ""

    private var filtered: [ExerciseProgress] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return model.exercises }
        return model.exercises.filter { $0.exerciseName.lowercased().contains(needle) }
    }

    var body: some View {
        List {
            if let error = model.errorMessage {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }

            if model.exercises.isEmpty && !model.isLoading {
                Section {
                    Text("Kehitys näkyy tässä, kun olet kirjannut kuormallisia sarjoja valmiiksi merkityissä treeneissä.")
                        .foregroundStyle(.secondary)
                }
            } else if filtered.isEmpty && !query.isEmpty {
                Section {
                    Text("Ei liikkeitä tällä haulla.").foregroundStyle(.secondary)
                }
            }

            ForEach(filtered) { exercise in
                NavigationLink {
                    ExerciseProgressDetailView(exercise: exercise)
                } label: {
                    row(exercise)
                }
            }
        }
        .navigationTitle("Kehitys")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Hae liikettä")
        .overlay { if model.isLoading && model.exercises.isEmpty { ProgressView() } }
        .refreshable { await model.refresh() }
        .task {
            model.configure(auth: auth)
            await model.load()
        }
    }

    private func row(_ exercise: ExerciseProgress) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.exerciseName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let latest = exercise.latestSet {
                    Text(latest.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 4)

            Sparkline(points: exercise.trend)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(formatKg(exercise.currentE1rm ?? 0)) kg")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let delta = exercise.displayDelta {
                    Text(formatPercent(delta))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(exercise.accessibilityLabel)
    }
}

/// Rivinsisäinen trendiviiva. Ei akseleita eikä kosketusta — tarkat luvut
/// ovat liikkeen omassa näkymässä.
private struct Sparkline: View {
    let points: [ExerciseProgress.TrendPoint]

    var body: some View {
        if points.count >= 2 {
            Chart(points) { point in
                LineMark(x: .value("Päivä", point.day), y: .value("e1RM", point.value))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: ExerciseProgress.domain(for: points))
            .frame(width: 56, height: 24)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Yhden liikkeen historia: e1RM-käyrä, ennätykset ja viimeisimmät toteutukset.
struct ExerciseProgressDetailView: View {
    let exercise: ExerciseProgress

    @State private var selectedDate: Date?

    var body: some View {
        List {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formatKg(exercise.currentE1rm ?? 0))
                        .font(.system(size: 44, weight: .bold))
                        .monospacedDigit()
                    Text("kg e1RM")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let delta = exercise.displayDelta {
                        Text(formatPercent(delta))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)

                if exercise.trend.count >= 2 {
                    chart
                }

                Text("e1RM = arvioitu yhden toiston maksimi sarjan painosta ja toistoista. Kaavio näyttää kunkin treenikerran parhaan arvion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ennätykset") {
                if let best = exercise.bestSet {
                    LabeledContent("Raskain sarja") {
                        Text(best.summary).monospacedDigit()
                    }
                }
                LabeledContent("Paras e1RM") {
                    Text("\(formatKg(exercise.bestE1rm ?? 0)) kg").monospacedDigit()
                }
                LabeledContent("Kuitattuja sarjoja") {
                    Text("\(exercise.completedSetCount)").monospacedDigit()
                }
            }

            if !exercise.repRecords.isEmpty {
                Section("Toistoennätykset") {
                    ForEach(exercise.repRecords) { record in
                        recordRow(
                            title: "\(formatReps(record.reps)) \(record.reps == 1 ? "toisto" : "toistoa")",
                            value: "\(formatKg(record.weight)) kg",
                            date: record.completedAt
                        )
                    }
                }
            }

            if !exercise.weightRecords.isEmpty {
                Section("Painoennätykset") {
                    ForEach(exercise.weightRecords) { record in
                        recordRow(
                            title: "\(formatKg(record.weight)) kg",
                            value: "\(formatReps(record.reps)) \(record.reps == 1 ? "toisto" : "toistoa")",
                            date: record.completedAt
                        )
                    }
                }
            }

            Section("Viimeisimmät toteutukset") {
                ForEach(exercise.recentPoints) { point in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(formatKg(point.load)) kg × \(formatReps(point.reps))")
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                            Text(point.day, format: .dateTime.day().month().year())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("e1RM \(formatKg(point.value)) kg")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle(exercise.exerciseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chart: some View {
        Chart(exercise.trend) { point in
            AreaMark(
                x: .value("Päivä", point.day),
                yStart: .value("Alaraja", ExerciseProgress.domain(for: exercise.trend).lowerBound),
                yEnd: .value("e1RM", point.value)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.linearGradient(
                colors: [.accentColor.opacity(0.28), .accentColor.opacity(0.03)],
                startPoint: .top,
                endPoint: .bottom
            ))
            LineMark(x: .value("Päivä", point.day), y: .value("e1RM", point.value))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2))
            // Treenikertoja on harvassa, ja pehmennetty viiva niiden välissä
            // näyttäisi jatkuvalta kehitykseltä. Pisteet kertovat missä
            // todellinen mittaus on.
            PointMark(x: .value("Päivä", point.day), y: .value("e1RM", point.value))
                .symbolSize(28)

            if let selected = exercise.point(nearest: selectedDate) {
                RuleMark(x: .value("Valittu", selected.day))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                PointMark(x: .value("Valittu", selected.day), y: .value("e1RM", selected.value))
                    .symbolSize(90)
                    // y: .fit pitää kuplan kaavion sisällä — .disabled leikkasi
                    // lukeman pois, kun valittu piste oli käyrän huipulla.
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit, y: .fit)) {
                        VStack(spacing: 1) {
                            Text("\(formatKg(selected.value)) kg")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Text("\(formatKg(selected.load)) kg × \(formatReps(selected.reps))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(selected.day, format: .dateTime.day().month())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
            }
        }
        // chartXSelection ei saa kosketusta Listin sisällä (listan vieritysele
        // vie sen) — oma ele plot-alueen päällä toimii napautuksella ja vedolla.
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plotFrame = proxy.plotFrame else { return }
                                let x = value.location.x - geometry[plotFrame].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    selectedDate = date
                                }
                            }
                    )
            }
        }
        .chartYScale(domain: ExerciseProgress.domain(for: exercise.trend))
        .frame(height: 180)
        .padding(.vertical, 4)
    }

    private func recordRow(title: String, value: String, date: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
            Spacer()
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
            if let parsed = ExerciseProgress.parseDate(date) {
                Text(parsed, format: .dateTime.day().month())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
    }
}

// MARK: - Malli

struct ExerciseProgress: Decodable, Identifiable {
    let key: String
    let exerciseName: String
    let completedSetCount: Int
    let currentE1rm: Double?
    let bestE1rm: Double?
    let deltaPercent: Double?
    let latestSet: SetSummary?
    let bestSet: SetSummary?
    let trend: [TrendPoint]
    let repRecords: [RepRecord]
    let weightRecords: [WeightRecord]

    var id: String { key }

    /// Muutos näytetään vain kun se on todellinen: pyöristyksen jälkeen
    /// "+0,0 %" olisi merkki normaalitilalle, ei poikkeukselle.
    var displayDelta: Double? {
        guard let deltaPercent, abs(deltaPercent) >= 0.05 else { return nil }
        return deltaPercent
    }

    /// Uusin ensin — kaavio kulkee aikajärjestyksessä, lista päinvastoin.
    var recentPoints: [TrendPoint] { trend.reversed().prefix(6).map { $0 } }

    var accessibilityLabel: String {
        var parts = [exerciseName, "e1RM \(formatKg(currentE1rm ?? 0)) kilogrammaa"]
        if let displayDelta {
            parts.append("muutos \(formatPercent(displayDelta))")
        }
        return parts.joined(separator: ", ")
    }

    /// Lähin treenikerta valittuun kohtaan: pisteitä on harvassa, joten
    /// kosketus osuu harvoin tarkalleen treenipäivään.
    func point(nearest date: Date?) -> TrendPoint? {
        guard let date else { return nil }
        return trend.min { abs($0.day.timeIntervalSince(date)) < abs($1.day.timeIntervalSince(date)) }
    }

    /// Akselin rajat datasta: kiinteä 0-alku litistäisi käyrän, koska e1RM
    /// liikkuu kymmenien kilojen alueella.
    static func domain(for points: [TrendPoint]) -> ClosedRange<Double> {
        let values = points.map(\.value)
        guard let min = values.min(), let max = values.max() else { return 0 ... 1 }
        let padding = Swift.max((max - min) * 0.25, 1)
        return (min - padding) ... (max + padding)
    }

    /// Aikaleima on joko täysi ISO-leima (treenin valmistuminen) tai pelkkä
    /// päivä (suunniteltu päivä, jos valmistumisaika puuttuu).
    static func parseDate(_ value: String) -> Date? {
        ISO8601DateFormatter.flexible.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
            ?? ISO8601DateFormatter.dateOnly.date(from: String(value.prefix(10)))
    }

    struct SetSummary: Decodable {
        let load: Double
        let reps: Double
        let completedAt: String

        var summary: String { "\(formatKg(load)) kg × \(formatReps(reps))" }
    }

    struct TrendPoint: Decodable, Identifiable {
        let date: String
        let value: Double
        let load: Double
        let reps: Double

        var id: String { "\(date)-\(load)-\(reps)" }
        var day: Date { ExerciseProgress.parseDate(date) ?? .now }
    }

    struct RepRecord: Decodable, Identifiable {
        let reps: Double
        let weight: Double
        let completedAt: String

        var id: Double { reps }
    }

    struct WeightRecord: Decodable, Identifiable {
        let weight: Double
        let reps: Double
        let completedAt: String

        var id: Double { weight }
    }
}

private struct ExerciseProgressResponse: Decodable {
    let exercises: [ExerciseProgress]
}

@Observable
@MainActor
final class ExerciseProgressModel {
    private(set) var exercises: [ExerciseProgress] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var api: APIClient?
    private let cacheKey = "mobile-exercise-progress"

    func configure(auth: AuthManager) {
        if api == nil { api = APIClient(auth: auth) }
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

    func refresh() async {
        guard let api else { return }
        do {
            let data = try await api.get("/api/mobile/exercise-progress")
            await ResponseCache.shared.write(cacheKey, data: data)
            apply(data)
            errorMessage = nil
        } catch {
            if exercises.isEmpty {
                errorMessage = "Kehitystietojen haku epäonnistui."
            }
        }
    }

    private func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(ExerciseProgressResponse.self, from: data) else { return }
        exercises = decoded.exercises
    }
}

// MARK: - Muotoilu

/// Kilot ilman turhaa desimaalia; pilkku desimaalierottimena kuten muualla apissa.
func formatKg(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    return rounded.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(rounded))
        : String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
}

func formatReps(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
}

/// Suunta merkkinä, ei värinä: nousu ei ole aina hyvä eikä lasku aina huono.
func formatPercent(_ value: Double) -> String {
    let sign = value >= 0 ? "+" : "−"
    return "\(sign)\(String(format: "%.1f", abs(value)).replacingOccurrences(of: ".", with: ",")) %"
}
