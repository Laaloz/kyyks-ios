import Charts
import SwiftUI

/// Keho-välilehti: viimeisimmät mitat, painon kehitys ja uuden mittauksen
/// kirjaus. Kirjaus päivittää palvelimella myös profiilin, jotta makrolaskenta
/// käyttää tuoreinta painoa.
struct BodyView: View {
    let auth: AuthManager

    @State private var model = BodyModel()
    @State private var showAdd = false
    @State private var selectedDate: Date?

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                if let latest = model.measurements.first {
                    Section("Viimeisin") {
                        metricRow("Paino", latest.weightKg, "kg", change: model.weightChange)
                        metricRow("Vyötärö", latest.waistCm, "cm", change: model.waistChange)
                        metricRow("Pituus", latest.heightCm, "cm", change: nil)
                    }
                }

                if model.weightSeries.count >= 2 {
                    Section("Painon kehitys") {
                        Chart(model.weightSeries) { point in
                            // AreaMark ankkuroituu oletuksena nollaan, mikä
                            // litistäisi 80 kg:n käyrän tunnistamattomaksi.
                            // yStart sitoo täytön akselin alarajaan.
                            AreaMark(
                                x: .value("Päivä", point.date),
                                yStart: .value("Alaraja", model.weightDomain.lowerBound),
                                yEnd: .value("Paino", point.value)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(.linearGradient(
                                colors: [.accentColor.opacity(0.28), .accentColor.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            LineMark(x: .value("Päivä", point.date), y: .value("Paino", point.value))
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: 2))

                            // Valittu kohta: pystyviiva, korostettu piste ja
                            // lukema — muuten käyrästä ei näe mikä paino oli milloin.
                            if let selected = model.point(nearest: selectedDate) {
                                RuleMark(x: .value("Valittu", selected.date))
                                    .foregroundStyle(.secondary.opacity(0.4))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                PointMark(
                                    x: .value("Valittu", selected.date),
                                    y: .value("Paino", selected.value)
                                )
                                .symbolSize(90)
                                .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit, y: .disabled)) {
                                    VStack(spacing: 1) {
                                        Text(selected.value, format: .number.precision(.fractionLength(1)))
                                            .font(.subheadline.weight(.semibold))
                                            .monospacedDigit()
                                        Text(selected.date, format: .dateTime.day().month())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        // chartXSelection ei saa kosketusta Listin sisällä, koska
                        // listan vieritysele vie sen. Oma ele plot-alueen päällä
                        // toimii sekä napautuksella että vetämällä.
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
                        .chartYScale(domain: model.weightDomain)
                        .frame(height: 180)
                        .padding(.vertical, 4)
                    }
                }

                Section("Historia") {
                    if model.measurements.isEmpty && !model.isLoading {
                        Text("Ei mittauksia vielä.").foregroundStyle(.secondary)
                    }
                    ForEach(model.measurements) { entry in
                        HStack {
                            Text(entry.measuredDate, format: .dateTime.day().month().year())
                                .font(.subheadline)
                            Spacer()
                            Text(entry.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Keho")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Label("Kirjaa mittaus", systemImage: "plus")
                    }
                }
            }
            .overlay { if model.isLoading && model.measurements.isEmpty { ProgressView() } }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showAdd) {
                AddMeasurementSheet(auth: auth, latest: model.measurements.first) {
                    Task { await model.refresh() }
                }
            }
        }
        .task {
            model.configure(auth: auth)
            await model.load()
        }
    }

    private func metricRow(_ title: String, _ value: Double?, _ unit: String, change: Double?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let value {
                if let change, abs(change) >= 0.05 {
                    // Suunta ilman arvottamista: nouseva/laskeva paino ei ole
                    // itsessään hyvä tai huono, se riippuu tavoitteesta.
                    Text(change > 0 ? "+\(format(change))" : format(change))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text("\(format(value)) \(unit)")
                    .monospacedDigit()
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}

struct BodyMeasurement: Decodable, Identifiable {
    let id: String
    let heightCm: Double?
    let weightKg: Double?
    let waistCm: Double?
    let measuredAt: String

    var measuredDate: Date {
        ISO8601DateFormatter.flexible.date(from: measuredAt) ?? .now
    }

    /// Pituus näkyy vain kun se on rivin ainoa mitta — muuten se toistuisi
    /// joka rivillä turhaan, koska pituus ei käytännössä muutu. Ilman tätä
    /// pelkän pituuden rivit näyttivät tyhjiltä.
    var summary: String {
        var parts: [String] = []
        if let weightKg { parts.append("\(String(format: "%.1f", weightKg).replacingOccurrences(of: ".", with: ",")) kg") }
        if let waistCm { parts.append("\(Int(waistCm)) cm") }
        if parts.isEmpty, let heightCm { parts.append("Pituus \(Int(heightCm)) cm") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

struct WeightPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
}

private struct MeasurementsResponse: Decodable {
    let measurements: [BodyMeasurement]
}

@Observable
@MainActor
final class BodyModel {
    private(set) var measurements: [BodyMeasurement] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var api: APIClient?
    private let cacheKey = "mobile-measurements"

    /// Uusin ensin -järjestyksessä; kaavio tarvitsee aikajärjestyksen.
    var weightSeries: [WeightPoint] {
        measurements
            .compactMap { entry in
                entry.weightKg.map { WeightPoint(id: entry.id, date: entry.measuredDate, value: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    /// Akselin rajat datasta pienellä marginaalilla: kiinteä 0-alku
    /// piilottaisi painon vaihtelun kokonaan.
    var weightDomain: ClosedRange<Double> {
        let values = weightSeries.map(\.value)
        guard let min = values.min(), let max = values.max() else { return 0 ... 1 }
        let padding = Swift.max((max - min) * 0.25, 0.5)
        return (min - padding) ... (max + padding)
    }

    /// Lähin mittaus valittuun kohtaan. Kaaviossa on harvoja pisteitä, joten
    /// kosketus osuu harvoin tarkalleen mittauspäivään.
    func point(nearest date: Date?) -> WeightPoint? {
        guard let date else { return nil }
        return weightSeries.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    var weightChange: Double? { change(\.weightKg) }
    var waistChange: Double? { change(\.waistCm) }

    /// Muutos edelliseen mittaukseen, jossa arvo on kirjattu.
    private func change(_ key: KeyPath<BodyMeasurement, Double?>) -> Double? {
        let values = measurements.compactMap { $0[keyPath: key] }
        guard values.count >= 2 else { return nil }
        return values[0] - values[1]
    }

    func configure(auth: AuthManager) {
        api = APIClient(auth: auth)
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
            let data = try await api.get("/api/mobile/measurements")
            await ResponseCache.shared.write(cacheKey, data: data)
            apply(data)
            errorMessage = nil
        } catch {
            if measurements.isEmpty {
                errorMessage = "Mittausten haku epäonnistui."
            }
        }
    }

    private func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(MeasurementsResponse.self, from: data) else { return }
        measurements = decoded.measurements
    }
}

extension ISO8601DateFormatter {
    /// Postgres-aikaleimoissa on murto-osasekunnit, joita oletusmuotoilija ei syö.
    static let flexible: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
