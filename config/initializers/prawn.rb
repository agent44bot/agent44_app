# Prawn warns whenever AFM (built-in) fonts touch non-ASCII; KitchenHandoutPdf
# already ASCII-ifies fraction glyphs and WinAnsi-sanitizes every string, so
# the warning is just noise in the logs.
Rails.application.config.after_initialize do
  Prawn::Fonts::AFM.hide_m17n_warning = true if defined?(Prawn::Fonts::AFM)
end
