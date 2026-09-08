# Volu iOS

Natiivi SwiftUI-sovellus Volu-palveluun: treenipäiväkirja ja ravintokirjaus samassa
sovelluksessa (App Storessa nimellä *Volu – treeni ja ravinto*). Sovellus on ohut
clientti web-Volulle: kirjautuminen kulkee Supabase Authin kautta ja kaikki data
haetaan ja kirjoitetaan Next.js-API:n kautta (`Authorization: Bearer <jwt>`).
Käyttöliittymä on suomeksi, ja sovellus on iPhone-only (iOS 17+).

Versionumero ylläpidetään tiedostossa `project.yml` (`MARKETING_VERSION`, molemmissa
kohteissa). Versio 1.0.0 julkaistiin App Storeen 21.8.2026.

## Sisältö

- [Ominaisuudet](#ominaisuudet)
- [Arkkitehtuuri ja periaatteet](#arkkitehtuuri-ja-periaatteet)
- [Vaatimukset](#vaatimukset)
- [Käynnistys](#käynnistys)
- [Konfiguraatio](#konfiguraatio)
- [Testit](#testit)
- [Rakenne](#rakenne)
- [API-reitit](#api-reitit)
- [Julkaisu](#julkaisu)
- [Tiedossa](#tiedossa)

## Ominaisuudet

Neljä välilehteä ja profiili:

- **Tänään**: tervehdys, päivän treeni, viimeisimmät oheissuoritukset ja Apple
  Health -kortti (askeleet, yöunen keskiarvo). Profiili avataan oikean yläkulman
  kuvakkeesta.
- **Treeni**: käynnissä oleva, tulevat ja tehdyt treenit sekä treenin aloitus
  ohjelmasta. Sarjat kirjataan suoraan riviltä (toistot, kuormat, kuittaus) ja
  edellisen kerran arvot näkyvät vieressä. Lepoajastin näkyy Live Activityna
  Dynamic Islandissa ja lukitusnäytöllä. Liikkeen vaihto, lisäys ja poisto kesken
  treenin, keston korjaus ja muistiinpano. Oma ohjelma tehdään pohjasta tai
  tyhjästä; valmentaja ja admin hallitsevat ohjelmiaan ja kohdistavat ne
  treenaajille. Kehitys liikkeittäin (e1RM, käyrä, muutosprosentti).
- **Ravinto**: päivän energia ja makrot tavoitteeseen verrattuna, ateriat
  ateriapaikoittain ja päivän selaus. Ateria kirjataan tekstinä, kuvana tai
  reseptistä; tekoälyarvio tehdään palvelimella. Reseptikirjasto annosmäärän
  skaalauksella ja ainesvaihdoilla on Pro-sisältöä, näytereseptit ja omat
  reseptit ilmaisia.
- **Keho**: paino, vyötärö ja muut mitat, painon kehitys käyränä sekä
  punnitusten tuonti Apple Healthista.
- **Profiili**: makrolaskennan pohjatiedot, ulkoasu (järjestelmä, vaalea, tumma),
  korostusväri, näytön sammumisen esto reseptissä ja treenissä, viikkomuistutus
  (push), Apple Health -asetukset (salitreenien vienti Healthiin, oletuksena pois),
  tilauksen hallinta ja ostojen palautus, uloskirjautuminen ja tilin poisto.

Lisäksi:

- **Kirjautuminen** sähköpostilla ja salasanalla (myös rekisteröityminen ja
  salasanan palautus), Sign in with Applella ja Googlella (selainvuo, paluu
  URL-skeemalla `fi.volu.app://login-callback`).
- **Aloituskysely** uudelle käyttäjälle, kun makrolaskennan tiedot puuttuvat.
- **Volu Pro** -tilaus StoreKit 2:lla (`fi.volu.app.pro.monthly`,
  `fi.volu.app.pro.yearly`). Laite lähettää transaktion palvelimelle, joka
  varmentaa sen ja päättää käyttöoikeuden (`free`, `pro`, `coached`). API:n
  402-vastaus on todellinen portti; paikallinen tila on vain käyttöliittymän lukko.
- **Push-ilmoitukset** (APNs): laitetunniste välitetään palvelimelle, joka
  päättää mitä ja milloin lähetetään. Ilmoituksen napautus ohjataan oikeaan
  näkymään (`NotificationRouter`). Lupa kysytään vasta Profiilin
  muistutusasetuksesta.
- **Apple Health**: luetaan askeleet, uni, paino ja muissa sovelluksissa tehdyt
  suoritukset. Suoritukset tuodaan oheissuorituksiksi ja punnitukset
  mittaushistoriaan; duplikaatit estetään palvelimella. Healthiin kirjoitetaan
  vain jos käyttäjä kytkee viennin päälle.
- **Maksupolun seuranta** (`FunnelEvent`): maksumuurin ja oston vaiheet kirjataan
  reitille `/api/mobile/events`. Virheet niellään, eikä seuranta koskaan estä tai
  hidasta mitattavaa toimintoa.

## Arkkitehtuuri ja periaatteet

- **Nopea käynnistys ilman verkkoa.** supabase-swift säilöö istunnon Keychainiin,
  ja `AuthManager.bootstrap()` lukee sen synkronisesti. Token uusitaan taustalla
  vasta kun API-kutsu sitä tarvitsee.
- **Stale-while-revalidate.** Näkymämallit toteuttavat `CachedModel`-protokollan:
  levyvälimuistin (`ResponseCache`, Caches-hakemisto) sisältö näytetään heti ja
  tuore data haetaan taustalla. Verkkovirhe näytetään vain, jos ruudulla ei ole
  mitään.
- **Optimistiset kirjaukset.** Sarjat, ateriat ja mittaukset päivittyvät ruudulle
  heti. Lähettämättömät sarjakirjaukset säilyvät levyllä (`PendingSetStore`,
  Application Support) sovelluksen sulkemisen tai kaatumisen yli.
- **Palvelin laskee, laite näyttää.** Makrot, e1RM-yhteenvedot, MET-pohjaiset
  kalorit ja käyttöoikeus tulevat valmiina API:sta, jotta samaa logiikkaa ei
  ylläpidetä kahdessa paikassa.
- **Jaetut mallit juuressa.** `VoluApp` omistaa auth-, tilaus-, push-, Health- ja
  lepoajastintilan ja jakaa ne ympäristönä. Tänään ja Treeni jakavat saman
  `TodayModel`in (yksi haku, kirjaus näkyy heti molemmissa).
- **Kaikki mitataan lokiin.** Jokaisen API-kutsun vasteaika kirjataan OSLogiin.
  Subsystem on `fi.volu.app`, kategoriat `api`, `funnel`, `health`,
  `health-export`, `push` ja `store` (Console.app tai Xcoden konsoli).
- **Terveysdata suojataan.** Välimuistin ja lähettämättömien kirjausten tiedostot
  kirjoitetaan `completeFileProtectionUnlessOpen`-suojauksella ja tyhjennetään
  uloskirjautuessa. `PrivacyInfo.xcprivacy` kuvaa kerätyt tiedot; seurantaa ei ole.

## Vaatimukset

- macOS ja Xcode 16 tai uudempi
  (`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Swift 5.10, deployment target iOS 17.0
- Kehityksessä web-Volun (`kyyks`-repo) dev-palvelin ajossa portissa 3300.
  Simulaattori kutsuu osoitetta `http://localhost:3300`; laitteelle käännettäessä
  Debug-konfiguraatio puhuu tuotantoon, koska puhelimen localhost on puhelin itse.

Ainoa Swift-paketti on [supabase-swift](https://github.com/supabase/supabase-swift)
(`from: 2.0.0`). Versiolukko on tiedostossa `ci_scripts/Package.resolved`.

## Käynnistys

```bash
# 1. Konfiguraatio. Arvot löytyvät web-repon .env-tiedostosta;
#    Config/Config.xcconfig on gitignoressa.
cp Config/Config.example.xcconfig Config/Config.xcconfig   # ja täytä arvot

# 2. Generoi Xcode-projekti. Volu.xcodeproj on gitignoressa ja generoidaan aina.
xcodegen generate

# 3. Avaa projekti ja aja Volu-skeema.
open Volu.xcodeproj
```

Web-repon dev-palvelin käynnistetään web-repon juuressa, esimerkiksi
`npm run dev -- -p 3300`. Tiedosto `.claude/launch.json` tekee saman Claude Codesta.

Kun `project.yml` muuttuu, aja `xcodegen generate` uudelleen. Kun riippuvuuksia
muutetaan, päivitä myös `ci_scripts/Package.resolved`, muuten Xcode Cloud kääntää
eri versioilla kuin oma kone.

## Konfiguraatio

`Config/Config.xcconfig` (pohja: `Config/Config.example.xcconfig`):

| Avain | Merkitys |
|---|---|
| `VOLU_SUPABASE_URL` | Supabase-projektin osoite |
| `VOLU_SUPABASE_ANON_KEY` | Supabasen anon-avain |
| `VOLU_API_BASE_URL` | Next.js-API:n osoite konfiguraatioittain: Debug ja simulaattori `http://localhost:3300`, Debug ja laite sekä Release `https://volu.fi` |

Arvot injektoidaan Info.plistiin avaimina `SupabaseURL`, `SupabaseAnonKey` ja
`APIBaseURL`, ja ne luetaan `AppConfig`-enumista. Puuttuva arvo kaataa sovelluksen
heti käynnistyksessä tarkoituksella. Huomaa, että xcconfigissa `//` aloittaa
kommentin, siksi osoitteissa on `https:/$()/`-kikka.

Muut konfiguraatiotiedostot:

- `Config/Volu.storekit`: StoreKit-testikonfiguraatio. Skeema lataa sen ajossa,
  jotta tilaustuotteet ovat olemassa simulaattorissa ilman App Store Connectia.
- `project.yml`: kohteet, skeema, oikeudet (HealthKit, Sign in with Apple, push,
  aikaherkät ilmoitukset), Info.plist-avaimet (käyttötarkoitustekstit, Live
  Activities, URL-skeema `fi.volu.app`) ja kehitystiimi.

## Testit

Yksikkötestit ovat hakemistossa `Tests/` (XCTest, target `VoluTests`). Ne kattavat
näkymistä irrotetun logiikan: sarjojen kirjaus ja yhdistäminen, treenilohkot,
reseptien skaalaus ja ainesvaihdot, päivämäärien jäsennys, kyselyparametrien
koodaus, Health-vienti, uusintayritykset ja kontrastit.

```bash
xcodegen generate
xcodebuild test -scheme Volu \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

Valitse `name`-arvoksi koneelle asennettu simulaattori. Xcodessa testit ajetaan
komennolla ⌘U.

## Rakenne

```
.
├── project.yml                 # XcodeGen-määrittely: kohteet, skeema, oikeudet, Info.plist
├── Config/
│   ├── Config.example.xcconfig # Pohja → kopioi nimellä Config.xcconfig (gitignoressa)
│   └── Volu.storekit           # StoreKit-testikonfiguraatio
├── Volu/                       # Sovellus (target Volu, fi.volu.app)
│   ├── VoluApp.swift           # Juuri: AppDelegate (APNs, ilmoitukset), TabView, jaetut mallit
│   ├── AppConfig.swift         # Konfiguraation luku Info.plistista
│   ├── Auth/                   # AuthManager (Supabase Auth), Sign in with Apple -painike
│   ├── Networking/             # APIClient, CachedModel, ResponseCache, PendingSetStore, FunnelEvent
│   ├── Models/                 # API-vastausten tyypit, muotoilu, asetukset, Entitlement, LegalLinks
│   ├── Features/               # Näkymät ja niiden @Observable-mallit (ks. taulukko alla)
│   ├── Health/                 # HealthManager (luku), HealthWorkoutExport (vienti), lajikartta
│   ├── Push/                   # PushManager (APNs-tunniste), NotificationRouter
│   ├── Store/                  # SubscriptionStore (StoreKit 2)
│   ├── Assets.xcassets/        # Sovelluskuvake ja korostusväri
│   ├── Info.plist
│   ├── Volu.entitlements
│   └── PrivacyInfo.xcprivacy   # Tietosuojamanifesti
├── VoluWidgets/                # Widget-laajennos (fi.volu.app.widgets): lepoajastimen Live Activity
├── Shared/                     # RestActivityAttributes, käännetään sovellukseen ja laajennokseen
├── Tests/                      # XCTest-yksikkötestit (target VoluTests)
├── Tools/
│   └── make-app-icon.swift     # Generoi sovelluskuvakkeen: swift Tools/make-app-icon.swift
├── Distribution/               # App Store Connectin tekstit ja kuvat (ks. Distribution/README.md)
│   ├── metadata/fi-FI/         # Nimi, kuvaus, avainsanat, julkaisumuistiinpanot, arviointiohjeet
│   └── screenshots/            # 6.9" ja 6.5" kuvasarjat sekä review-kuvat
├── ci_scripts/
│   ├── ci_post_clone.sh        # Xcode Cloud: XcodeGen, Config.xcconfig, buildinumero, projekti
│   └── Package.resolved        # Riippuvuuslukko, kopioidaan generoituun projektiin
└── .claude/launch.json         # Web-repon dev-palvelimen käynnistys (portti 3300)
```

`Features/`-hakemiston tiedostot alueittain:

| Alue | Tiedostot |
|---|---|
| Kirjautuminen | `LoginView`, `PasswordResetSheet`, `OnboardingView` |
| Tänään | `TodayView`, `TodayModel` (jaettu Treenin kanssa), `AddActivitySheet`, `AddMeasurementSheet` |
| Treeni | `WorkoutsListView`, `StartWorkoutSheet`, `WorkoutView`, `WorkoutModel`, `SetTable`, `RestTimer`, `ExercisePickerSheet`, `DurationEditSheet` |
| Ohjelmat | `ProgramsModel`, `CreateProgramView`, `ProgramDraftEditor`, `CoachProgramsView`, `CoachProgramsModel` |
| Kehitys | `ExerciseProgressView` |
| Ravinto | `NutritionView`, `NutritionModel`, `AddMealSheet`, `MealDetailSheet`, `MacroEnergySplit` |
| Reseptit | `RecipeLibraryView`, `RecipeLibraryModel`, `RecipeDetailSheet`, `RecipeQuickLookSheet` |
| Keho | `BodyView` |
| Profiili ja tilaus | `ProfileView`, `PaywallView`, `DeleteAccountSheet` |
| Yhteiset | `SaveToolbarButton` |

## API-reitit

Sovellus käyttää web-Volun reittejä. Mobiilille tehdyt kevyet reitit ovat polussa
`/api/mobile/*`:

`today`, `profile`, `onboarding`, `nutrition`, `recipes`, `measurements`,
`measurements/import`, `programs`, `program-templates`, `coach/programs`,
`workouts/{id}`, `exercise-progress`, `subscription`, `device-token`, `events`,
`password-reset`, `account`.

Webin kanssa jaettuja reittejä ovat `/api/workouts/*` (aloitus, sarjat, liikkeet,
muistiinpano, keskeytys, valmis), `/api/programs/*`, `/api/day-meal-plans`,
`/api/extra-activities`, `/api/exercises/search` ja `/api/nutrition/ai-estimate`.

## Julkaisu

- **Xcode Cloud** kääntää TestFlight- ja App Store -versiot. Skripti
  `ci_scripts/ci_post_clone.sh` asentaa XcodeGenin, kirjoittaa `Config.xcconfig`in
  ympäristömuuttujista (`VOLU_SUPABASE_URL`, `VOLU_SUPABASE_ANON_KEY` sekä
  valinnaiset `VOLU_API_BASE_URL_DEBUG` ja `VOLU_API_BASE_URL_RELEASE`), asettaa
  buildinumeron muuttujasta `CI_BUILD_NUMBER`, generoi projektin ja kopioi
  riippuvuuslukon paikalleen.
- **Versionumero** nostetaan tiedostoon `project.yml` (`MARKETING_VERSION`,
  molemmat kohteet). Buildinumeron antaa pilvi.
- **App Store -aineisto** (kuvaukset, avainsanat, julkaisumuistiinpanot,
  arviointiohjeet, kuvakaappaukset) on hakemistossa `Distribution/`. Ohjeet ja
  täyttämättömät kohdat ovat tiedostossa `Distribution/README.md`.
- **Sovelluskuvake** generoidaan komennolla `swift Tools/make-app-icon.swift`,
  joka kirjoittaa tuloksen suoraan resurssikatalogiin.
- Sovellus ei sisällä vientirajoitusten alaista salausta
  (`ITSAppUsesNonExemptEncryption: false`).

## Tiedossa

- Jos Supabase-projektin captcha-suojaus on päällä, natiivikirjautuminen vaatisi
  hCaptcha-tokenin. Sovellus näyttää silloin yleisen virheilmoituksen, joten
  captcha pidetään pois päältä.
- Push-ilmoitukset eivät toimi simulaattorissa. APNs-rekisteröinnin
  epäonnistuminen kirjataan lokiin, eikä se estä muuta käyttöä.
- Simulaattorin Healthissa ei ole dataa, joten Tänään-näkymä kertoo, ettei
  tietoja saatu. Syötä dataa käsin Health-sovellukseen (ohje tiedostossa
  `Distribution/README.md`).
