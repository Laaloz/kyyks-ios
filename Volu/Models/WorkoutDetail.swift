import Foundation

/// /api/mobile/workouts/{id} -vastaus: treeni + sessio + sarjalokit + muistiinpano.
struct WorkoutDetail: Decodable {
    let workout: ScheduledWorkout
    let session: WorkoutSession?
    let setLogs: [WorkoutSetLog]
    let note: WorkoutNote?
    /// Edellisen kerran tulokset samoille liikkeille.
    ///
    /// Valinnainen tarkoituksella: levyllä oleva välimuistivastaus on
    /// tallennettu ennen tätä kenttää, eikä Swift käytä oletusarvoa puuttuvalle
    /// avaimelle vaan heittää. Pakollisena koko treeni jäisi dekoodaamatta ja
    /// näkymä tyhjäksi ensimmäisellä avauksella päivityksen jälkeen — hiljaa,
    /// koska apply nielee dekoodausvirheen.
    let previousSets: [PreviousSet]?
}

/// Yksi sarja edelliseltä kerralta. Liike ja sarjan numero yhdistävät sen
/// nykyiseen riviin.
struct PreviousSet: Decodable {
    let exerciseId: String
    let setLabel: String
    let actualReps: Double?
    let actualLoad: Double?
    let performedAt: String

    /// "9 × 23 kg" tai pelkkä toistomäärä, jos kuormaa ei ole.
    var summary: String? {
        guard let reps = actualReps else {
            return actualLoad.map { WorkoutSetLog.loadText($0) }
        }
        guard let load = actualLoad, load > 0 else { return "\(Int(reps))" }
        return "\(Int(reps)) × \(WorkoutSetLog.loadText(load))"
    }
}

struct WorkoutNote: Decodable {
    let body: String
    let updatedAt: String
}

/// /api/mobile/programs -vastaus: sama data sekä treenin aloitukseen että
/// ohjelman muokkaukseen — liikkeet tulevat samasta JSONB-sarakkeesta.
struct ProgramsResponse: Decodable {
    let programs: [Program]
    /// Saako käyttäjä luoda ja muokata ohjelmia. Valmennettavalla ohjelmat
    /// tekee valmentaja. Valinnainen, koska levyllä oleva vanha
    /// välimuistivastaus ei sisällä kenttää.
    let canManagePrograms: Bool?
}

struct Program: Decodable, Identifiable {
    let id: String
    let title: String
    /// "active" | "archived" — poistetut eivät tule reitiltä lainkaan.
    let status: String?
    let updatedAt: String?
    let workouts: [ProgramWorkoutSummary]
    /// Onko ohjelma käyttäjän itsensä tekemä. Valmentajan tekemää palvelin ei
    /// anna treenaajan muokata.
    let isOwn: Bool?

    var isActive: Bool { status != "archived" }
    /// Muokattavissa vain jos se on oma. Tuntematon (vanha vastaus) tulkitaan
    /// omaksi, jotta itsenäisen treenaajan muokkaus ei katoa päivityksessä.
    var isEditable: Bool { isOwn ?? true }

    /// Milloin ohjelma oli viimeksi käytössä — erottaa samannimiset versiot.
    var updatedDate: Date? { updatedAt.flatMap { parseAPIDate($0) } }
    var workoutNames: String { workouts.map(\.name).joined(separator: " · ") }
}

struct ProgramWorkoutSummary: Decodable, Identifiable {
    let id: String
    let name: String
    let splitType: String?
    let exerciseCount: Int
    /// Vain muokkaus tarvitsee; aloitus pärjää liikemäärällä.
    let exercises: [ProgramTemplate.TemplateExercise]?
}

/// /api/workouts/start -vastaus.
struct StartWorkoutResponse: Decodable {
    let scheduledWorkoutId: String
    /// Palvelin peruu käynnissä olevan treenin, jos uusi aloitetaan.
    let autoCancelledWorkoutTitle: String?
}

/// /api/exercises/search -vastaus liikevalitsimeen.
struct ExerciseSearchResponse: Decodable {
    let exercises: [ExerciseSearchResult]
}

struct ExerciseSearchResult: Decodable, Identifiable {
    let id: String
    let name: String
    let category: String?
    let equipment: String?
}

struct WorkoutSession: Decodable {
    let id: String
    let startedAt: String
    let completedAt: String?
    /// Tauon alku ja kertynyt taukoaika. Valinnaisia, koska vanha
    /// välimuistivastaus levyllä ei sisällä niitä.
    let pausedAt: String?
    let pausedDurationSeconds: Double?
    let updatedAt: String?

    /// Treenin kesto sekunteina. Sama sääntö kuin webissä
    /// (`calculateSessionDurationSeconds`): loppuhetki on valmistuminen, tauko
    /// tai viimeisin muutos, ja kertynyt taukoaika vähennetään.
    ///
    /// Käynnissä olevalle treenille annetaan `now`, jolloin luku kasvaa
    /// ruudulla. Kahtena toteutuksena web ja natiivi voisivat näyttää saman
    /// treenin eri pituisena.
    func durationSeconds(now: Date = .now) -> Int {
        guard let start = parseAPIDate(startedAt) else { return 0 }
        let endIso = completedAt ?? pausedAt ?? updatedAt
        let end = completedAt != nil || pausedAt != nil
            ? endIso.flatMap { parseAPIDate($0) }
            : now
        guard let end, end >= start else { return 0 }
        return max(0, Int((end.timeIntervalSince(start)).rounded()) - Int(pausedDurationSeconds ?? 0))
    }
}

/// Equatable, jotta kesken olevan tallennuksen voi tunnistaa vanhentuneeksi:
/// nopea peräkkäinen kirjaus korvaa arvon kesken pyynnön.
struct WorkoutSetLog: Decodable, Identifiable, Equatable {
    let id: String
    let templateExerciseId: String
    let setId: String
    let exerciseId: String
    let exerciseName: String
    let supersetGroup: String?
    let setLabel: String
    let targetReps: Double
    let targetRepsMin: Double?
    let targetRepsMax: Double?
    let targetLoad: Double?
    let targetRestSeconds: Double?
    var actualReps: Double?
    var actualLoad: Double?
    var done: Bool

    /// "8–10" jos ohjelmassa on toistohaarukka, muuten "8".
    var targetRepsLabel: String {
        if let min = targetRepsMin, let max = targetRepsMax, min != max {
            return "\(Int(min))–\(Int(max))"
        }
        return "\(Int(targetReps))"
    }

    /// Kuorma tekstinä, esim. "23 kg". Jaettu, koska sekä rivi että liikkeen
    /// otsikko näyttävät sen ja kahtena toteutuksena ne ehtisivät erota.
    static func loadText(_ load: Double) -> String {
        let text = load.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(load))
            : String(format: "%.1f", load).replacingOccurrences(of: ".", with: ",")
        return "\(text) kg"
    }

    /// Onko sarja tehty. Kirjattu arvo riittää — erillinen kuittaus on
    /// virhelähde, ei tieto.
    ///
    /// Ilman tätä vanhat rivit näkyivät tyhjinä ympyröinä vaikka toistot ja
    /// kuorma olivat tallessa: valmiiksi merkitty treeni ilmoitti "0/16
    /// sarjaa" ja arvot olivat haaleina kuin niitä ei olisi kirjattu.
    var isLogged: Bool {
        done || actualReps != nil || actualLoad != nil
    }

    /// Miten sarja suhteutuu ohjelman tavoitteeseen.
    ///
    /// `onTarget` on tarkoituksella myös "ei tiedossa": kirjaamaton sarja ei
    /// ole poikkeus, ja merkki kuuluu vain poikkeukselle. Jos tavoitteessa
    /// pysyminen merkittäisiin, merkki olisi lähes joka rivillä eikä kertoisi
    /// enää mitään.
    enum Outcome {
        case onTarget
        case below
        case above
    }

    /// Toistot suhteessa tavoitealueeseen — mutta vain silloin kun kuorma ei
    /// selitä eroa.
    ///
    /// Tämä on koko arvion ydin: 6 toistoa tavoitteen 8–10 sijaan **suuremmalla
    /// kuormalla** ei ole alisuoritus vaan tavallinen vaihtokauppa. Jos sen
    /// merkitsisi punaisella, käyttäjä oppisi olemaan uskomatta merkkiä — ja
    /// silloin se ei auta myöskään silloin kun se on oikeassa.
    var outcome: Outcome {
        guard let actual = actualReps else { return .onTarget }

        let low = targetRepsMin ?? targetReps
        let high = targetRepsMax ?? targetReps

        // Kuormaa verrataan vain kun molemmat on tiedossa; kehonpainoliikkeillä
        // tavoitekuormaa ei ole, jolloin toistot ratkaisevat yksin.
        let heavier: Bool
        let lighter: Bool
        if let target = targetLoad, target > 0, let done = actualLoad, done > 0 {
            heavier = done > target
            lighter = done < target
        } else {
            heavier = false
            lighter = false
        }

        if actual < low, !heavier { return .below }
        if actual > high, !lighter { return .above }
        return .onTarget
    }
}
