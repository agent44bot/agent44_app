require "test_helper"

# Acrobat refused to extract the hinted, composite-glyph Carlito subsets Prawn
# embedded ("Cannot extract the embedded font"), dropping fractions and some
# letters (Lora, 2026-10-09). The vendored files are dehinted with every
# composite glyph flattened; keep them that way.
class CarlitoFontTest < ActiveSupport::TestCase
  Dir[Rails.root.join("vendor/fonts/carlito/*.ttf")].each do |path|
    name = File.basename(path)

    test "#{name} has no hinting programs" do
      tables = TTFunk::File.open(path).directory.tables
      assert_empty tables.keys & %w[fpgm prep cvt\ ]
    end

    test "#{name} has no composite glyphs" do
      font = TTFunk::File.open(path)
      compound = (0...font.maximum_profile.num_glyphs).select { |id| font.glyph_outlines.for(id)&.compound? }
      assert_empty compound
    end
  end
end
