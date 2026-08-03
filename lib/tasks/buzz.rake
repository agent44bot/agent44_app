# frozen_string_literal: true

namespace :buzz do
  desc "Generate a Buzz/Nostr keypair (BUZZ_PRIVATE_KEY or BUZZ_KEY_<AGENT>)"
  task keygen: :environment do
    keypair = Buzz::Keypair.generate
    puts "private key (secret): #{keypair.private_key_hex}"
    puts "public key (identity): #{keypair.public_key_hex}"
  end

  desc "Publish a message to the configured relay: rake 'buzz:say[hello,vlad,agent44]'"
  task :say, [ :text, :agent, :channel ] => :environment do |_t, args|
    unless Buzz.enabled?
      abort "Buzz is not configured. Set BUZZ_RELAY_URL and BUZZ_PRIVATE_KEY (see rake buzz:keygen)."
    end

    text    = args[:text].presence || "hello from agent44_app"
    channel = args[:channel].presence || Buzz::DEFAULT_CHANNEL

    if Buzz.say(text, agent: args[:agent].presence, channel: channel)
      puts "published to #{Buzz.relay_url} ##{channel} as #{Buzz.keypair_for(args[:agent].presence).public_key_hex[0, 12]}…"
    else
      abort "publish failed (see log for the relay's reason)"
    end
  end
end
