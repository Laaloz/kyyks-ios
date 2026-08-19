# App Store -jakelun aineisto

Kaikki App Store Connectiin syötettävä teksti ja kuva on tässä, jotta lomake
täytetään tiedostosta eikä muistista. Kentän raja on merkitty jokaiseen
kohtaan — App Store Connect katkaisee ylimenevän ilman varoitusta.

## Tekstit (`metadata/fi-FI/`)

| Tiedosto | ASC-kenttä | Raja | Nyt |
|---|---|---|---|
| `name.txt` | App Name | 30 | 24 |
| `subtitle.txt` | Subtitle | 30 | 26 |
| `promotional_text.txt` | Promotional Text | 170 | 157 |
| `keywords.txt` | Keywords | 100 | 96 |
| `description.txt` | Description | 4000 | 2089 |
| `release_notes.txt` | What's New | 4000 | 313 |
| `review_notes.txt` | App Review Information → Notes | 4000 | — |
| `support_url.txt` | Support URL | — | volu.fi/tuki (200 OK) |
| `marketing_url.txt` | Marketing URL | — | volu.fi |
| `privacy_url.txt` | Privacy Policy URL | — | volu.fi/privacy (200 OK) |

**Promotional textin voi vaihtaa ilman uutta versiota** — kaikki muu teksti
lukittuu arviointiin lähetettyyn versioon. Käytä sitä kokeilujakson tai
kampanjan viestintään, älä descriptionia.

`keywords.txt` on pilkuilla eroteltu **ilman välilyöntejä** — välilyönti
kuluttaa merkkirajaa. Sovelluksen nimessä olevia sanoja ei toisteta
avainsanoissa, koska nimi indeksoidaan muutenkin.

## Kuvat (`screenshots/fi-FI/iphone-6.9/`)

Kahdeksan kuvaa, 1320 × 2868 px (iPhone 17 Pro Max, @3x). **Tämä on ainoa
pakollinen koko**: sovellus on iPhone-only (`TARGETED_DEVICE_FAMILY: "1"`),
ja Apple skaalaa 6.9" kuvat pienemmille laitteille itse.

Suositeltu järjestys App Store Connectiin (kolme ensimmäistä näkyy
hakutuloksissa, joten vahvin tarina ensin):

1. `02-treeni.png` — sarjan kirjaus, toistot ja kuormat
2. `03-ravinto.png` — päivän energia ja makrot
3. `08-ai-arvio.png` — tekoälyn tekemä ateria-arvio (Pron kärki)
4. `01-tanaan.png` — päivän yhteenveto, askeleet ja yöuni
5. `06-kehitys.png` — kehitys liikkeittäin
6. `05-keho.png` — paino ja mitat
7. `04-reseptit.png` — reseptikirjasto
8. `07-resepti.png` — reseptin makrot ja annoskoko

Kuvat on otettu simulaattorista kirjautuneena, ja niissä näkyy oikeaa dataa
omalta tililtä. Kaksi asiaa on siksi hoidettu erikseen:

- **Nimi on demonimi.** Tänään-näkymä näyttää `profiles.full_name`-kentän, jota
  sovelluksessa ei voi muokata. Nimi vaihdettiin kannassa kuvan ajaksi
  ("Mikko Laine") ja palautettiin heti perään. Jos kuva otetaan uudelleen,
  tee sama — muuten kauppasivulle päätyy oikea nimi.
- **Apple Health -kortti näyttää dataa.** Simulaattorin Health-sovellukseen
  syötettiin käsin askeleet (8 432) ja yksi yö unta (7 h 1 min). Ilman niitä
  kortissa lukee "Apple Healthista ei saatu tietoja", mikä lukee kuvassa
  virheeltä. Data on simulaattorikohtaista: uusi simulaattori tarkoittaa
  uutta syöttöä (Health → Selaa → Aktiivisuus/Uni → +).

Uusinta: aseta ensin tilapalkki vakioksi, muuten kellonaika ja akku vaihtelevat
kuvien välillä.

```bash
xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 --dataNetwork wifi
```

## Kesken

- [ ] **Ravinto-kuvan päivä.** `03-ravinto.png` näyttää saman aterian kahteen
      kertaan (Banaanipannukakut ×2), koska rivin poisto ei mene läpi:
      `DELETE /api/day-meal-plans/[entryId]` jää vastaamatta dev-palvelimella
      (todennettu curlilla, 60 s ilman vastausta, muut reitit vastaavat heti).
      Kun poisto toimii, päivälle kirjataan aamupala ja lounas kirjastosta ja
      kuva otetaan uudelleen.

## Vielä täyttämättä App Store Connectissa

- [ ] **Demotunnukset** `review_notes.txt`:n alkuun ja ASC:n App Review
      -osioon. Ilman niitä arviointi hylkää heti: sovellus vaatii kirjautumisen.
- [ ] **Category:** Health & Fitness (toissijainen: Lifestyle).
- [ ] **Age rating** -kysely.
- [ ] **Tilaustuotteiden lokalisoinnit** (`fi.volu.app.pro.monthly` /
      `.yearly`): näyttönimi, kuvaus ja tarkistuskuva tilausryhmälle "Volu Pro".
- [ ] **Saatavuus:** päätä myydäänkö vain Suomessa. Jos muihin maihin, tarvitaan
      englanninkielinen lokalisointi — sovelluksen käyttöliittymä on suomeksi,
      joten pelkkä englanninkielinen kauppasivu johtaisi harhaan.
- [ ] `APPLE_APP_APPLE_ID` webin ympäristöön, kun sovellus on luotu ASC:hen.
- [ ] Server Notifications V2 -osoite: `https://volu.fi/api/apple/notifications`.

Privacy labelit on julkaistu 17.8.2026 — niitä ei tarvitse täyttää uudelleen,
mutta ne on päivitettävä jos kerättävät tiedot tai kolmannet osapuolet muuttuvat.
