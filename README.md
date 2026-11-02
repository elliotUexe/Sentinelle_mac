# Sentinel Mac

App menu bar macOS pour [Sentinel](https://github.com/) (supervision homelab, orchestrateur sur `fsociety`). Icône colorée selon la santé globale (SSE `/events`), popover de résumé, fenêtre avec le dashboard web existant (WKWebView).

## Architecture — deux mécanismes de mise à jour distincts

1. **Contenu du dashboard** (JS/CSS/API côté Sentinel) : automatique, zéro action nécessaire. L'app charge la page web existante à chaque ouverture — toute évolution du dashboard est visible immédiatement, sans nouvelle version de l'app.
2. **La coquille native elle-même** (ce dépôt) : mise à jour via [Sparkle](https://sparkle-project.org/), déclenchée par un tag `v*` qui lance la CI (`.github/workflows/release.yml`, runner `macos-latest` — ce projet ne peut pas être compilé sur Linux).

Pas de compte Apple Developer : signature ad-hoc (`codesign --sign -`), pas de notarisation. La toute première installation nécessite un clic droit → "Ouvrir" (Gatekeeper). Les mises à jour suivantes via Sparkle devraient rester fluides mais ce n'est pas garanti sans notarisation.

## Mise en route (étapes manuelles, une seule fois)

1. **Rendre le dépôt public** : Settings → General → Danger Zone → Change visibility → Public. Nécessaire pour que GitHub Pages (appcast) et les assets de Release (.dmg) soient téléchargeables sans authentification (Sparkle ne sait pas s'authentifier). Aucun secret n'est jamais committé ici — seule une IP tailscale de fsociety, non exploitable sans être pair du tailnet.
2. **GitHub Pages** : Settings → Pages → Source = "Deploy from a branch" → branche `main`, dossier `/ (root)`. Sert `appcast.xml` à l'URL `https://elliotuexe.github.io/Sentinelle_mac/appcast.xml` (déjà référencée dans `Resources/Info.plist`).
3. **Clés Sparkle — à générer EN LOCAL sur un Mac, jamais via la CI** (la clé privée ne doit jamais transiter par des logs, a fortiori sur un repo public) :
   ```sh
   curl -L -o /tmp/sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz
   mkdir -p /tmp/sparkle-tools && tar -xf /tmp/sparkle.tar.xz -C /tmp/sparkle-tools
   /tmp/sparkle-tools/bin/generate_keys
   ```
   Affiche la clé **publique** (`SUPublicEDKey`) — sans risque, à coller dans un secret GitHub `SPARKLE_PUBLIC_KEY`. Pour récupérer la clé **privée** (jamais à partager, jamais à coller ailleurs que dans le secret GitHub ci-dessous) :
   ```sh
   security find-generic-password -s "https://sparkle-project.org" -a "ed25519" -w
   ```
   Coller directement le résultat dans Settings → Secrets and variables → Actions → `SPARKLE_PRIVATE_KEY`.
4. **Premier tag** : `git tag v0.1.0 && git push origin v0.1.0` déclenche la CI, qui construit le `.dmg`, publie une GitHub Release et met à jour `appcast.xml`.
5. **Première installation** : télécharger le `.dmg` depuis la Release, ouvrir, glisser dans `/Applications`, clic droit → Ouvrir (Gatekeeper, une seule fois).

Les mises à jour suivantes (nouveaux tags `v*`) devraient s'installer seules via Sparkle, sans repasser par ces étapes.

## Développement local

Nécessite Xcode (macOS uniquement) :

```sh
swift build
swift run
```

## Structure

- `Sources/SentinelMac/` : code Swift (SwiftUI + AppKit minimal + Sparkle).
- `Resources/Info.plist` : métadonnées du bundle, config Sparkle (`SUFeedURL`, `SUPublicEDKey`).
- `scripts/` : assemblage du `.app`, packaging `.dmg`, signature Sparkle + régénération d'`appcast.xml`.
- `releases/` : archive de tous les `.dmg` publiés (nécessaire à `generate_appcast`, qui reconstruit l'appcast complet à partir de cet historique à chaque release).
- `.github/workflows/release.yml` : CI de release (sur tag `v*`).

## Config Sentinel

L'URL du serveur est en dur dans `Sources/SentinelMac/Config.swift` (IP tailscale de fsociety) — un seul utilisateur, une seule instance, pas de fichier de settings pour l'instant.
