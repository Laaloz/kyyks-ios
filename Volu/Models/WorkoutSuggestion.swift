import Foundation

/// Treeni-välilehden päätökset, jotka eivät ole näkymää: mikä treeni on
/// seuraavana, milloin kukin on tehty ja milloin kuorman nostoa kannattaa
/// ehdottaa. Erillään näkymistä, jotta säännöt ovat yksikkötestattavissa.

// MARK: - Seuraava treeni

enum NextWorkout {
    /// Ohjelman järjestyksessä seuraava treeni viimeksi tehdyn jälkeen.
    ///
    /// A/B/C-jako on yleisin, ja silloin odotus on että kierto jatkuu siitä
    /// mihin jäätiin. Viimeisen jälkeen kierto palaa alkuun. Jos mitään
    /// ohjelman treeniä ei löydy tehtyjen joukosta (uusi ohjelma tai tehdyt
    /// ovat ikkunan ulkopuolella), ehdotetaan ensimmäistä.
    ///
    /// `completed` on `/api/mobile/today`n 14 vuorokauden ikkuna. Pidemmän
    /// tauon jälkeen kierto alkaa alusta, mikä on järkevä oletus eikä väite.
    static func pick(in program: Program, completed: [ScheduledWorkout]) -> ProgramWorkoutSummary? {
        let workouts = program.workouts
        guard !workouts.isEmpty else { return nil }

        let lastDone = completed
            .filter { $0.status == "completed" }
            .compactMap { workout -> (index: Int, date: Date)? in
                guard let index = workouts.firstIndex(where: { matches($0, workout) }),
                      let date = completionDate(workout)
                else { return nil }
                return (index, date)
            }
            .max { $0.date < $1.date }

        guard let lastDone else { return workouts[0] }
        return workouts[(lastDone.index + 1) % workouts.count]
    }

    /// Milloin ohjelman treeni tehtiin viimeksi (vain ikkunan sisällä).
    ///
    /// nil kertoo "ei tiedossa", ei "ei koskaan tehty": ikkuna on 14 päivää,
    /// joten väite tekemättömyydestä olisi usein väärä.
    static func lastDone(of workout: ProgramWorkoutSummary, in completed: [ScheduledWorkout]) -> Date? {
        completed
            .filter { $0.status == "completed" && matches(workout, $0) }
            .compactMap(completionDate)
            .max()
    }

    /// Treeni kuuluu ohjelman treeniin tunnisteella; nimi on varalla vanhalle
    /// välimuistivastaukselle, jossa tunnistetta ei vielä ole.
    private static func matches(_ programWorkout: ProgramWorkoutSummary, _ scheduled: ScheduledWorkout) -> Bool {
        if let id = scheduled.programWorkoutId { return id == programWorkout.id }
        return scheduled.title == programWorkout.name
    }

    private static func completionDate(_ workout: ScheduledWorkout) -> Date? {
        parseAPIDate(workout.completedAt ?? workout.scheduledDate)
    }

    /// "tänään", "eilen", "5 pv sitten".
    static func daysAgoText(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case ..<1: return "tänään"
        case 1: return "eilen"
        default: return "\(days) pv sitten"
        }
    }
}

// MARK: - Kuorman nosto

/// Kehotus nostaa painoa, laskettuna edellisen kerran tuloksista.
///
/// Kaksoisprogressio: kun *kaikki* edellisen kerran sarjat yltivät
/// tavoitealueen yläpäähän, kuorma on käynyt kevyeksi ja seuraava askel on
/// lisätä painoa eikä toistoja. Sääntö on tiukka, koska väärä kehotus johtaa
/// epäonnistuneeseen sarjaan.
///
/// Kehotus kuuluu uuden treenin alkuun. Se laskettiin ennen kuluvan treenin
/// sarjoista ja ilmestyi kesken treenin heti kun viimeinen sarja täyttyi —
/// neuvo ensi kerralle väärällä hetkellä.
struct ProgressionHint: Equatable {
    /// Edellisen kerran kuorma, jos sitä seurattiin.
    let previousLoad: Double?
    /// Ehdotettu kuorma. nil kun kuormaa ei seurattu eikä lukua voi ehdottaa.
    let suggestedLoad: Double?
    /// Pienin edellisen kerran toistomäärä: jokainen sarja yltää vähintään tähän.
    let reps: Int

    /// Oletusaskel. Käyttäjän oma asetus (1 / 2,5 / 5 kg) ei vielä kulje
    /// mobiiliprofiilin mukana; 2,5 on myös sen oletus.
    static let defaultIncrement = 2.5

    /// "Viimeksi 60 kg × 8 · kokeile 62,5 kg". Lyhyt, ja luvut kertovat miksi
    /// nostoa ehdotetaan.
    var text: String {
        guard let previousLoad, let suggestedLoad else {
            return "Viimeksi \(reps) toistoa · kokeile lisätä painoa"
        }
        return "Viimeksi \(WorkoutSetLog.loadText(previousLoad)) × \(reps) · kokeile \(WorkoutSetLog.loadText(suggestedLoad))"
    }

    /// Ehdotus liikkeelle, tai nil kun ehdolle ei ole perusteita.
    ///
    /// - Vain kirjaamaton liike: ensimmäisen sarjan kirjaus on aloittanut
    ///   liikkeen, ja kehotus on silloin joko noudatettu tai ohitettu.
    /// - Kaikilla sarjoilla pitää olla edellisen kerran tulos. Uusi sarja ilman
    ///   vertailua ei kerro mitään, ja kehotus on parempi jättää antamatta kuin
    ///   antaa väärin.
    /// - Vaatii toistohaarukan: ilman ylärajaa ei ole mitään mihin yltää.
    /// - Tavoitekuormaa ei vaadita (ohjelmissa ei aina ole painoja), mutta jos
    ///   se on, edellisen kerran kuorma ei saa jäädä sen alle: täydet toistot
    ///   kevyemmällä painolla eivät kerro että paino on kevyt.
    static func make(
        for group: ExerciseGroup,
        previous: (WorkoutSetLog) -> PreviousSet?,
        increment: Double = defaultIncrement
    ) -> ProgressionHint? {
        let logs = group.logs
        guard !logs.isEmpty,
              logs.allSatisfy({ !$0.isLogged }),
              logs.contains(where: { $0.targetRepsMax != nil })
        else { return nil }

        let results = logs.compactMap { log in previous(log).map { (log: log, previous: $0) } }
        guard results.count == logs.count else { return nil }

        let allAtCeiling = results.allSatisfy { log, previous in
            guard let reps = previous.actualReps else { return false }
            let ceiling = log.targetRepsMax ?? log.targetReps
            let heldLoad: Bool
            if let target = log.targetLoad, target > 0 {
                heldLoad = (previous.actualLoad ?? 0) >= target
            } else {
                heldLoad = true
            }
            return reps >= ceiling && heldLoad
        }
        guard allAtCeiling else { return nil }

        let reps = results.compactMap { $0.previous.actualReps }.min().map { Int($0) } ?? 0
        let loads = results.compactMap { $0.previous.actualLoad }.filter { $0 > 0 }
        guard let base = loads.max() else {
            return ProgressionHint(previousLoad: nil, suggestedLoad: nil, reps: reps)
        }
        return ProgressionHint(previousLoad: base, suggestedLoad: base + increment, reps: reps)
    }
}
