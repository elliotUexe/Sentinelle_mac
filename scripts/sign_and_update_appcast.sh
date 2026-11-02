#!/bin/bash
# Signe le .dmg (clé privée Sparkle EdDSA) et régénère appcast.xml.
#
# Suit le flux documenté par Sparkle 2.x : `generate_appcast` scanne un
# dossier contenant TOUTES les versions déjà publiées (releases/*.dmg) et
# reconstruit l'appcast complet à partir de leurs Info.plist embarqués — on
# ne signe/génère donc jamais un item isolé à la main.
#
# Usage : VERSION=0.1.0 SPARKLE_PRIVATE_KEY="..." ./scripts/sign_and_update_appcast.sh
#
# SPARKLE_PRIVATE_KEY = valeur affichée par `generate_keys -x` (peut faire 44
# OU 128 caractères selon le format — les deux sont valides en 2.6.4, cf.
# generate_appcast/main.swift::loadPrivateKeys "We always allow the old
# format without private seed"). Vérifié contre le tag 2.6.4 exact de
# Sparkle, pas la branche master (qui a un format différent, plus strict).
set -euo pipefail

VERSION="${VERSION:?VERSION requis}"
SPARKLE_PRIVATE_KEY="${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY requis (secret GitHub Actions)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASES_DIR="$ROOT_DIR/releases"
DMG_SRC="$ROOT_DIR/build/SentinelMac-$VERSION.dmg"

mkdir -p "$RELEASES_DIR"
cp "$DMG_SRC" "$RELEASES_DIR/"

echo "==> Récupération des outils Sparkle (generate_appcast, sign_update)"
SPARKLE_TOOLS_DIR="$ROOT_DIR/.sparkle-tools"
if [ ! -x "$SPARKLE_TOOLS_DIR/bin/generate_appcast" ]; then
    SPARKLE_VERSION="2.6.4"
    curl -L -o /tmp/sparkle.tar.xz \
        "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    mkdir -p "$SPARKLE_TOOLS_DIR"
    tar -xf /tmp/sparkle.tar.xz -C "$SPARKLE_TOOLS_DIR"
fi

echo "==> Régénération de l'appcast à partir de tout releases/"
# --ed-key-file - : lit la clé depuis stdin (readLine strippingNewline),
# pattern documenté explicitement dans l'aide de l'outil lui-même :
# `echo "$PRIVATE_KEY_SECRET" | generate_appcast --ed-key-file -`
# -s est déprécié et explicitement rejeté pour les clés nouvellement
# générées ("no longer supported for newly generated keys").
#
# --download-url-prefix : sans ça, generate_appcast construit une URL de
# téléchargement à la racine du site (https://.../SentinelMac-X.Y.Z.dmg),
# qui n'existe pas — le .dmg est réellement servi sous /releases/ (c'est ce
# dossier qui est committé et servi par GitHub Pages). Bug réel constaté en
# prod : l'appcast pointait vers une URL 404, Sparkle ne voyait donc jamais
# la mise à jour côté client malgré un appcast valide.
echo "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_TOOLS_DIR/bin/generate_appcast" \
    --ed-key-file - \
    --download-url-prefix "https://elliotuexe.github.io/Sentinelle_mac/releases/" \
    "$RELEASES_DIR"

cp "$RELEASES_DIR/appcast.xml" "$ROOT_DIR/appcast.xml"
echo "==> appcast.xml mis à jour"
