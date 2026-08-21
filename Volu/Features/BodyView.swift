import Charts
import SwiftUI

/// Keho-välilehti: viimeisimmät mitat, painon kehitys ja uuden mittauksen
/// kirjaus. Kirjaus päivittää palvelimella myös profiilin, jotta makrolaskenta
/// käyttää tuoreinta painoa.
struct BodyView: View {
    let auth: AuthManager

    @Environment(NotificationRouter.self) private var router
    @State private var model = BodyModel()
    @State private var showAdd = false
    @State private var selectedDate: Date?

    @Environment(RestTimerManager.self) private var restTimer

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                if !model.measurements.isEmpty {
                    Section("Viimeisin") {
                        metricRow("Paino", model.latestWeight, "kg", change: model.weightChange)
                        metricRow("Vyötärö", model.latestWaist, "cm", change: model.waistChange)
                        metricRow("Pituus", model.heightCm, "cm", change: nil)
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
                            // Pisteet näyttävät missä mittaus on oikeasti tehty
                            // — pehmennetty viiva niiden välissä on tulkintaa —
                            // ja kertovat mistä kohtaa kannattaa napauttaa.
                            PointMark(x: .value("Päivä", point.date), y: .value("Paino", point.value))
                                .symbolSize(28)

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
                                // y: .fit pitää kuplan kaavion sisällä — .disabled
                                // leikkasi lukeman pois käyrän huipulla.
                                .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit, y: .fit)) {
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
                    if model.trackedMeasurements.isEmpty && !model.isLoading {
                        Text("Ei mittauksia vielä.").foregroundStyle(.secondary)
                    }
                    ForEach(model.trackedMeasurements) { entry in
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
            .restTimerBar(restTimer)
            .sheet(isPresented: $showAdd) {
                AddMeasurementSheet(auth: auth, latest: model.measurements.first) {
                    Task { await model.refreshAfterChange() }
                }
            }
        }
        // Molemmat polut tarvitaan: onChange kattaa jo näkyvän välilehden, task
        // sen että ilmoitus vaihtoi välilehteä eikä näkymää ollut vielä olemassa
        // silloin kun kohde asetettiin.
        .task {
            model.configure(auth: auth)
            openMeasurementIfRequested()
            await model.load()
        }
        .onChange(of: router.target) { openMeasurementIfRequested() }
    }

    /// Muistutuksen napautus avaa suoraan lomakkeen: kehotus kirjata mittaus ja
    /// sen kirjaaminen kuuluvat samaan hetkeen.
    private func openMeasurementIfRequested() {
        if router.consume("measurement") { showAdd = true }
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

    private func format(_ value: Double) -> String { formatDecimal(value) }
}

struct BodyMeasurement: Decodable, Identifiable {
    let id: String
    let weightKg: Double?
    let waistCm: Double?
    let measuredAt: String

    var measuredDate: Date {
        parseAPIDate(measuredAt) ?? .distantPast
    }

    /// Onko rivillä seurattavaa mittaa. Pelkän pituuden rivit ovat
    /// profiilipäivityksiä, ei mittauksia — ne näkyivät historiassa tyhjinä.
    var hasTrackedMetric: Bool { weightKg != nil || waistCm != nil }

    var summary: String {
        // Sama muotoilu kuin ruudun yläreunan lukemissa: rivi ja otsikko eivät
        // saa kertoa samasta mittauksesta eri lukua.
        var parts: [String] = []
        if let weightKg { parts.append("\(formatDecimal(weightKg)) kg") }
        if let waistCm { parts.append("\(formatDecimal(waistCm)) cm") }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

struct WeightPoint: Identifiable {
    let id: String
    let date: Date
    let value: Double
}

private struct MeasurementsResponse: Decodable {
    /// Profiilista, ei mittausriviltä — ks. BodyModel.heightCm.
    let heightCm: Double?
    let measurements: [BodyMeasurement]
}

@Observable
@MainActor
final class BodyModel: CachedModel {
    private(set) var measurements: [BodyMeasurement] = []
    /// Pituus tulee profiilista eikä mittausriviltä: se kirjataan kerran, joten
    /// tuoreimmalla mittausrivillä sitä ei ole ja näkymä näytti viivaa vaikka
    /// arvo oli tallessa.
    private(set) var heightCm: Double?
    var isLoading = false
    var errorMessage: String?

    var api: APIClient?
    let cacheKey = "mobile-measurements"
    let resourcePath = "/api/mobile/measurements"
    let loadFailureMessage = "Mittausten haku epäonnistui."
    let analyticsArea: FunnelEvent.Source? = .body
    var hasContent: Bool { !measurements.isEmpty }

    /// Kunkin mitan tuorein kirjattu arvo, ei tuoreimman rivin arvo.
    ///
    /// Rivi kantaa vain sen mitä silloin kirjattiin: Healthista tuotu paino ei
    /// sisällä vyötäröä, joten uusin rivi näytti vyötäröksi viivaa vaikka arvo
    /// oli tallessa muutaman päivän takaa. Sama vika oli pituudessa, ja sielläkin
    /// syy oli se että arvoa haettiin väärältä riviltä.
    /// Vain testeille: mittausten asetus ilman verkkoa.
    func setMeasurementsForTesting(_ rows: [BodyMeasurement]) {
        measurements = rows
    }

    var latestWeight: Double? { measurements.compactMap(\.weightKg).first }
    var latestWaist: Double? { measurements.compactMap(\.waistCm).first }

    /// Historiaan vain rivit joilla on painoa tai vyötäröä.
    var trackedMeasurements: [BodyMeasurement] {
        measurements.filter(\.hasTrackedMetric)
    }

    /// Uusin ensin -järjestyksessä; kaavio tarvitsee aikajärjestyksen.
    var weightSeries: [WeightPoint] {
        Self.dailySeries(
            measurements.compactMap { entry in
                entry.weightKg.map { WeightPoint(id: entry.id, date: entry.measuredDate, value: $0) }
            }
        )
    }

    /// Päivältä vain viimeisin punnitus, aikajärjestyksessä.
    ///
    /// Samalle päivälle voi kertyä useita punnituksia — Healthista tuotu ja
    /// käsin kirjattu, tai kaksi punnitusta samana aamuna. Kaaviossa ne
    /// näkyivät pystysuorana hyppynä, joka kertoo vaa'an heitosta eikä painon
    /// kehityksestä. Seuraamme viikkojen trendiä, joten päivän sisäinen
    /// vaihtelu on kohinaa.
    static func dailySeries(_ points: [WeightPoint], calendar: Calendar = .current) -> [WeightPoint] {
        var latestByDay: [Date: WeightPoint] = [:]
        for point in points {
            let day = calendar.startOfDay(for: point.date)
            if let existing = latestByDay[day], existing.date >= point.date { continue }
            latestByDay[day] = point
        }
        return latestByDay.values.sorted { $0.date < $1.date }
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

    func apply(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(MeasurementsResponse.self, from: data) else { return }
        measurements = decoded.measurements
        heightCm = decoded.heightCm
    }
}
