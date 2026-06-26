# Links a recipe packet forward to other runs of the SAME class, so Lora only
# attaches a recipe once. Two entry points:
#
#   * attach_forward(packet)   - when a packet is attached to a class, link it
#                                 to future runs already on the calendar.
#   * run_for_snapshot(snap)    - when the nightly snapshot lands, link newly
#                                 appeared future runs to a matching packet.
#
# Each dated run of a recurring class has its OWN url (the date is baked into
# the Tock slug / name), so "same class" can't be a url match. We match on the
# curriculum: the class name reduced to its meaningful words (dates, punctuation
# and generic words like "class" dropped). Matching is EXACT on that word set
# (not the reuse picker's loose 0.3 similarity) and needs a minimum number of
# real words, so generic names like "Cooking Class" never auto-attach.
#
# Auto-links are created with auto: true and NEVER overwrite an existing link,
# so a manual attach always wins and stays put.
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

  # Attach-time: link `packet` to every future run on the latest snapshot that
  # shares its curriculum and has no packet yet. Returns the number linked.
  def self.attach_forward(packet, now: Time.current)
    key = curriculum_key(packet.title)
    return 0 unless key

    snapshot = KitchenSnapshot.latest
    return 0 unless snapshot

    linked = KitchenPacketLink.pluck(:event_url).to_set
    count = 0
    snapshot.kitchen_events.where("start_at > ?", now).find_each do |ev|
      next if linked.include?(ev.url)
      next unless curriculum_key(ev.name) == key
      next unless link!(packet, ev.url)
      linked << ev.url
      count += 1
    end
    count
  end

  # Ingest-time: for every future event in `snapshot` without a packet, link the
  # best-matching existing packet (same curriculum, most recently updated wins).
  # Returns the number linked.
  def self.run_for_snapshot(snapshot, now: Time.current)
    by_key = packets_by_key
    return 0 if by_key.empty?

    linked = KitchenPacketLink.pluck(:event_url).to_set
    count = 0
    snapshot.kitchen_events.where("start_at > ?", now).find_each do |ev|
      next if linked.include?(ev.url)
      key = curriculum_key(ev.name)
      packet = key && by_key[key]
      next unless packet
      next unless link!(packet, ev.url)
      linked << ev.url
      count += 1
    end
    count
  end

  # Index of candidate packets by curriculum key. Iterating oldest-first means
  # the newest packet for a curriculum wins (later writes overwrite earlier).
  def self.packets_by_key
    KitchenPacket.order(updated_at: :asc).each_with_object({}) do |h, acc|
      key = curriculum_key(h.title)
      acc[key] = h if key
    end
  end

  # Create the auto link, tolerating a race on the unique event_url index.
  def self.link!(packet, event_url)
    KitchenPacketLink.create!(kitchen_packet: packet, event_url: event_url, auto: true)
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false
  end

  private_class_method :packets_by_key, :link!
end
