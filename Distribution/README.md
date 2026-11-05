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

Sama seitsemän kuvan sarja kahtena kokona. Sovellus on iPhone-only
(`TARGETED_DEVICE_FAMILY: "1"`), joten iPad- tai Watch-kuvia ei tarvita.

- `iphone-6.9/` — 1320 × 2868 px
- `iphone-6.5/` — 1284 × 2778 px

**Kumpi kelpaa, riippuu siitä minkä paikan App Store Connect näyttää.**
Lomakkeen iPhone-välilehti tarjosi 19.8.2026 vain 6.5" -paikkaa
(1242 × 2688, 2688 × 1242, 1284 × 2778 tai 2778 × 1284) ja hylkäsi 6.9"
kuvat väärän kokoisina — käytä silloin `iphone-6.5/`-sarjaa. 6.9"
kuvat voi ladata **View All Sizes in Media Manager** -näkymästä.

Nykyiset kuvat (5.11.2026, versio 1.0.8) on otettu iPhone 17 Pro
-simulaattorista (1206 × 2622) ja skaalattu molempiin kokoihin
(`sips -z 2868 1320` ja `sips -z 2778 1284`). Skaalaus venyttää 6.5"
kuvaa pystysuunnassa ~0,5 %, mikä ei näy silmällä. Tarkempi tulos syntyy,
kun kuvat otetaan suoraan iPhone 17 Pro Max -simulaattorilla (6.9").

Järjestys App Store Connectiin (kolme ensimmäistä näkyy hakutuloksissa,
joten vahvin tarina ensin) = tiedostonimen numero:

1. `01-treeni.png` — sarjan kirjaus: viime kerran arvot, esitäytetyt
   toistot ja kuormat sekä lepoajastin
2. `02-ravinto.png` — päivän energia ja makrot
3. `03-ai-arvio.png` — tekoälyn tekemä ateria-arvio (Pron kärki)
4. `04-reseptit.png` — reseptikirjasto kahdessa sarakkeessa
5. `05-resepti.png` — reseptin makrot ja annoskoko
6. `06-kehitys.png` — kehitys liikkeittäin
7. `07-keho.png` — paino ja mitat

Kuvat on otettu **demotunnuksella** (sama kuin arviointiohjeessa, Pro
päällä), jotta kauppasivulle ei päädy oikean käyttäjän nimeä tai dataa:

- **Treenikuvan treeni aloitettiin kuvaa varten ja poistettiin heti
  perään.** "Viimeksi"-sarake täyttyy vasta kun treeni on aloitettu
  ohjelmasta.
- **Ravintopäivälle kirjattiin kolme reseptiä**, ja AI-arvio peruttiin
  tallentamatta.
- **Tänään-näkymä puuttuu sarjasta**, koska simulaattorin Apple Health
  -kortissa lukee "Apple Healthista ei saatu tietoja", mikä näyttää kuvassa
  virheeltä. Jos se halutaan mukaan: anna Volulle Health-lukuoikeus ja syötä
  simulaattorin Health-sovellukseen askeleet ja yksi yö unta käsin.
- Google Playn pre-launch-testi kirjautuu samalla demotunnuksella ja
  painelee sovellusta (aloittaa treenejä, kuittaa sarjoja, poistaa
  kirjauksia). Jos demodata muuttuu kesken kuvauksen, syy on todennäköisesti
  se.

Uusinta: aseta ensin tilapalkki vakioksi, muuten kellonaika ja akku vaihtelevat
kuvien välillä.

```bash
xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 --dataNetwork wifi
```

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
