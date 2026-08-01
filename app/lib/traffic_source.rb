# Tells a person apart from a machine on the two public, *billed* NY Kitchen
# endpoints: the printable flyer and the QR scan redirect.
#
# Why this exists: on 2026-08-01 the flyer's counters read "101 prints, 30 flyer
# scans this month" and every one of that month's scans was a link-safety
# crawler fanning out from 21 datacenter IPs across four continents, following
# each QR link on the page seconds after the URL went out in an email. At 4c an
# event, NY Kitchen was being invoiced for robots reading a bathroom flyer.
#
# Two different questions, so two different tests:
#   automated? - "is this not a person at a browser" (crawlers, previewers,
#                scripts, headless QA runs). Used to keep junk out of the print
#                counters. Deliberately broad: a missed print is cheaper than a
#                billed bot.
#   camera_scan? - "did a phone camera do this". A printed QR is scanned with a
#                phone, full stop, so anything without a handheld user agent is
#                not a flyer scan no matter how browser-like it looks. This is
#                what catches a crawler wearing a stock desktop Chrome string.
module TrafficSource
  # Self-identifying non-browsers, plus the link-preview/security scanners that
  # fetch any URL pasted into an email or chat (SkypeUriPreview hit us the same
  # afternoon), plus the headless drivers we use for our own QA renders.
  AUTOMATED = /
    bot\b | \bbots\b | crawler | spider | scrap(er|ing) | preview | fetcher |
    monitor(ing)? | scanner | headless | phantom | puppeteer | playwright |
    curl | wget | libwww | python-requests | okhttp | axios | node-fetch |
    go-http | java\/ | apache-httpclient | http_client | ruby | postman |
    facebookexternalhit | slackbot | skypeuri | bingpreview | whatsapp |
    telegrambot | discordbot | linkedinbot | google-?(read-?aloud|other)
  /xi

  # A handheld browser: the only thing that can point a camera at a flyer.
  HANDHELD = /iPhone|iPad|iPod|Android|Mobile Safari|\bMobile\b|Silk|KAIOS/i

  def self.automated?(user_agent)
    ua = user_agent.to_s
    # No user agent at all is a script, not a browser.
    return true if ua.blank?
    ua.match?(AUTOMATED)
  end

  def self.human_browser?(user_agent)
    !automated?(user_agent)
  end

  # A real flyer/poster scan: a phone, and not a crawler dressed as one.
  def self.camera_scan?(user_agent)
    ua = user_agent.to_s
    ua.match?(HANDHELD) && !automated?(ua)
  end
end
