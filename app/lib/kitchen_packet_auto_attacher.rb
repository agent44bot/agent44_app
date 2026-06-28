# Curriculum matching for recipe "carry-forward". Each dated run of a recurring
# class has its OWN url (the date is baked into the Tock slug / name), so
# "same class" can't be a url match. We match on the curriculum: the class name
# reduced to its meaningful words (dates, punctuation and generic words like
# "class" dropped). Matching is EXACT on that word set (not the reuse picker's
# loose 0.3 similarity) and needs a minimum number of real words, so generic
# names like "Cooking Class" never match.
#
# Carry-forward is LAZY: when a user opens a no-recipe class, the controller
# looks up `packet_for(name)` and COPIES it onto this run (an independent copy,
# so editing one run never touches the others). The next run copies whatever is
# latest-edited at the moment it's opened.
class KitchenPacketAutoAttacher
  # Words that don't identify a curriculum on their own.
  STOPWORDS = %w[class classes cooking cook the a an and or with for of at to
                 in on private event reserved hands hands-on].to_set
  # A name needs at least this many real words to be matchable.
  MIN_TOKENS = 2

  # The curriculum fingerprint: lowercased alpha words, dates/punctuation and
  # stopwords removed, as a Set. nil when the name is too generic to match on.
  def self.curriculum_key(name)
    tokens = name.to_s.downcase.scan(/[a-z]+/).reject { |w| STOPWORDS.include?(w) }.to_set
    tokens.size >= MIN_TOKENS ? tokens : nil
  end

  # The most-recently-edited packet whose curriculum matches `name`, or nil when
  # the name is too generic or no prior run exists. `updated_at`-last means a
  # newly opened run copies the latest edited version, which is the carry-forward
  # "loop" the owner asked for.
  def self.packet_for(name)
    key = curriculum_key(name)
    return nil unless key
    KitchenPacket.order(updated_at: :asc).select { |p| curriculum_key(p.title) == key }.last
  end
end
