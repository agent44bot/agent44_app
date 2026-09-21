# Text rules every NY Kitchen recipe follows, wherever the words come from.
module KitchenText
  module_function

  # Em and en dashes never reach a printed handout (house rule). Recipes drafted
  # by AI pick them up ("Cook for 10-12 minutes", "rest, then slice") and they
  # sit in saved packets, so this runs on save AND at render time: new recipes
  # are stored clean, and every recipe already on file still prints clean.
  #
  # A range becomes a hyphen; a dash used as punctuation becomes a comma, which
  # is how the kitchen writes it.
  def no_dashes(str)
    str.to_s
       .gsub(/(?<=\d)\s*[—–]\s*(?=\d)/, "-")
       .gsub(/\s+[—–]\s+/, ", ")
       .tr("—–", "-")
  end

  # no_dashes applied to every string inside a recipe (titles, amounts, items,
  # section names, steps), at any depth.
  def scrub(value)
    case value
    when String then no_dashes(value)
    when Array  then value.map { |v| scrub(v) }
    when Hash   then value.transform_values { |v| scrub(v) }
    else value
    end
  end
end
