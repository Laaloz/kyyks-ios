#!/bin/sh
set -e

# Xcode Cloud ajaa tämän automaattisesti kloonauksen jälkeen, ennen käännöstä.
#
# Kaksi asiaa puuttuu kloonista tarkoituksella, ja molemmat rakennetaan tässä:
#
#   1. Xcode-projekti. *.xcodeproj on gitignoressa, koska se generoidaan
#      XcodeGenillä project.yml:stä — versioituna generoitu tiedosto tuottaisi
#      jatkuvia konflikteja.
#
#   2. Config/Config.xcconfig. Se sisältää projektin osoitteet ja anon-avaimen,
#      eikä sitä pidetä repossa. Arvot tulevat Xcode Cloudin ympäristö-
#      muuttujista, jotka asetetaan App Store Connectissa.
#
# Vaiheet kirjoitetaan lokiin näkyviin: pilvikäännöksen virhe näkyy vasta
# lokista, ja ilman merkkejä on vaikea sanoa mikä askel kaatui.

echo "=== ci_post_clone: alkaa ==="

cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ -z "$VOLU_SUPABASE_URL" ] || [ -z "$VOLU_SUPABASE_ANON_KEY" ]; then
  echo "VIRHE: VOLU_SUPABASE_URL ja VOLU_SUPABASE_ANON_KEY on asetettava" >&2
  echo "Xcode Cloudin ympäristömuuttujiksi App Store Connectissa." >&2
  exit 1
fi

# Homebrew ei ole aina valmiiksi polulla, ja sen asennus on hidas. XcodeGen
# haetaan siksi ensisijaisesti valmiina binäärinä julkaisusta — se on nopeampi
# ja riippumaton siitä onko Homebrew käytettävissä.
echo "=== ci_post_clone: asennetaan XcodeGen ==="
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

if command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen löytyi valmiina."
elif curl -fsSL -o /tmp/xcodegen.zip \
  "https://github.com/yonaskolb/XcodeGen/releases/download/2.43.0/xcodegen.zip"; then
  unzip -q /tmp/xcodegen.zip -d /tmp/xcodegen
  export PATH="/tmp/xcodegen/xcodegen/bin:$PATH"
  echo "XcodeGen haettu julkaisusta."
else
  echo "Julkaisun haku ei onnistunut, kokeillaan Homebrew'ta."
  brew install xcodegen
fi

xcodegen --version
echo "=== ci_post_clone: generoidaan projekti ==="
xcodegen generate

# xcconfigissa "//" aloittaa kommentin, joten kauttaviivat on katkaistava
# $()-kikalla — muuten osoitteesta jäisi jäljelle vain "https:".
escape_url() {
  printf '%s' "$1" | sed 's|//|/$()/|'
}

echo "=== ci_post_clone: kirjoitetaan Config.xcconfig ==="
cat > Config/Config.xcconfig <<CONFIG
// Generoitu Xcode Cloudissa (ci_scripts/ci_post_clone.sh) — älä muokkaa.
VOLU_SUPABASE_URL = $(escape_url "$VOLU_SUPABASE_URL")
VOLU_SUPABASE_ANON_KEY = $VOLU_SUPABASE_ANON_KEY
VOLU_API_BASE_URL[config=Debug] = $(escape_url "${VOLU_API_BASE_URL_DEBUG:-https://volu.fi}")
VOLU_API_BASE_URL[config=Debug][sdk=iphoneos*] = $(escape_url "${VOLU_API_BASE_URL_DEBUG:-https://volu.fi}")
VOLU_API_BASE_URL[config=Release] = $(escape_url "${VOLU_API_BASE_URL_RELEASE:-https://volu.fi}")
CONFIG

# Avain ei kuulu lokiin, joten tarkistetaan vain että rivit syntyivät.
echo "Config.xcconfig kirjoitettu, rivejä: $(wc -l < Config/Config.xcconfig)"
ls -d Volu.xcodeproj
echo "=== ci_post_clone: valmis ==="
