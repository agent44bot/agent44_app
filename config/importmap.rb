# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "trix"
pin "@rails/actiontext", to: "actiontext.esm.js"

# Nostr keypair auth crypto libraries (vendored)
pin "@noble/curves/secp256k1", to: "noble-curves-secp256k1.js"
pin "@noble/hashes/sha256", to: "noble-hashes-sha256.js"
pin "@noble/hashes/utils", to: "noble-hashes-utils.js"
pin "@scure/base", to: "scure-base.js"
