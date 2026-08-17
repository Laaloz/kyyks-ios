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
#      muuttujista, jotka asetetaan App Store Connectin workflow-asetuksissa.

cd "$CI_PRIMARY_REPOSITORY_PATH"

if [ -z "$VOLU_SUPABASE_URL" ] || [ -z "$VOLU_SUPABASE_ANON_KEY" ]; then
  echo "VIRHE: VOLU_SUPABASE_URL ja VOLU_SUPABASE_ANON_KEY on asetettava" >&2
  echo "Xcode Cloudin workflow-ympäristömuuttujiksi App Store Connectissa." >&2
  exit 1
fi

brew install xcodegen
xcodegen generate

# xcconfigissa "//" aloittaa kommentin, joten kauttaviivat on katkaistava
# $()-kikalla — muuten osoitteesta jäisi jäljelle vain "https:".
escape_url() {
  printf '%s' "$1" | sed 's|//|/$()/|'
}

cat > Config/Config.xcconfig <<CONFIG
// Generoitu Xcode Cloudissa (ci_scripts/ci_post_clone.sh) — älä muokkaa.
VOLU_SUPABASE_URL = $(escape_url "$VOLU_SUPABASE_URL")
VOLU_SUPABASE_ANON_KEY = $VOLU_SUPABASE_ANON_KEY
VOLU_API_BASE_URL[config=Debug] = $(escape_url "${VOLU_API_BASE_URL_DEBUG:-https://volu.fi}")
VOLU_API_BASE_URL[config=Debug][sdk=iphoneos*] = $(escape_url "${VOLU_API_BASE_URL_DEBUG:-https://volu.fi}")
VOLU_API_BASE_URL[config=Release] = $(escape_url "${VOLU_API_BASE_URL_RELEASE:-https://volu.fi}")
CONFIG

echo "Projekti generoitu ja konfiguraatio kirjoitettu."
