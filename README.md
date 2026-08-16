# Volu iOS (natiivi, V0)

Natiivi SwiftUI-clientti, joka käyttää web-Volun Supabase-authia ja Next.js-API:a
(`Authorization: Bearer <jwt>`). Suorituskykyperiaatteet: Keychain-istunto ilman
verkkokutsua käynnistyksessä, stale-while-revalidate-levyvälimuisti, kaikkien
API-kutsujen vasteajat lokiin (subsystem `fi.volu.app`, category `api`).

## Vaatimukset

- Xcode 16+ (App Store) ja `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- XcodeGen (`brew install xcodegen`)
- Web-repon dev-palvelin ajossa (`pnpm dev` volu-repossa) — API vastaa osoitteessa `http://localhost:3000`

## Käynnistys

```bash
# 1. Konfiguraatio (arvot web-repon .env:stä; Config.xcconfig on gitignoressa)
cp Config/Config.example.xcconfig Config/Config.xcconfig  # ja täytä arvot

# 2. Generoi Xcode-projekti
xcodegen generate

# 3. Avaa ja aja
open Volu.xcodeproj
```

## Rakenne

- `Volu/Auth/AuthManager.swift` — supabase-swift, istunto Keychainissa
- `Volu/Networking/APIClient.swift` — Bearer-kutsut + vasteaikaloki
- `Volu/Networking/ResponseCache.swift` — SWR-levyvälimuisti
- `Volu/Models/AppState.swift` — virhesietoinen minimidekoodaus `/api/app-state`
- `Volu/Features/` — LoginView, TodayView (read-only)

## Tiedossa (V0)

- Jos Supabase-projektin captcha-suojaus on päällä, natiivikirjautuminen vaatii
  hCaptcha-tokenin → dev-vaiheessa captcha pois päältä Supabase-dashboardista
  tai hCaptcha iOS-SDK myöhemmin.
- `/api/app-state` on raskas bootstrap-reitti; vasteaikaloki kertoo, tarvitaanko
  mobiilille kevyempi endpoint (suunnitelman kohta 03/e).
