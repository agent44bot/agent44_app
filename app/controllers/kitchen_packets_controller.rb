# Recipe packets for NY Kitchen classes, attached from Sam's list page.
# Flow: open a class on Sam's list -> "+ Recipe" -> new (upload a PDF, paste a
# recipe URL, or reuse an existing packet) -> create runs the AI extraction ->
# edit reviews the recipe with a live PDF preview -> print renders the branded
# NY Kitchen PDF (full pages then single-station pages).
class KitchenPacketsController < ApplicationController
  MAX_PDF_BYTES = 10.megabytes

  # The edit and print pages embed the recipe PDF (served by #print) in an
  # iframe. The app-wide CSP sets frame-ancestors 'none' and production sets
  # X-Frame-Options: DENY, which block even same-origin framing, so relax both
  # to self for these actions (mirrors KitchenController's display preview).
  content_security_policy(only: %i[edit print]) do |policy|
    policy.frame_ancestors :self
  end
  after_action :allow_same_origin_framing, only: %i[edit print]

  def new
    @event_url  = params[:event_url].to_s
    @event_name = params[:event_name].to_s
    # All packets, rendered for the client-side "copy an existing recipe" live
    # filter (recipe-filter controller), matching the class list.
    @existing = KitchenPacket.order(updated_at: :desc).to_a
  end

  def create
    event_url = params[:event_url].to_s

    # Reuse path: COPY an existing packet onto this class, no AI involved. A copy
    # (not a shared link) so editing or deleting this class's recipe never
    # touches the packet it came from. Land on edit so the copy can be reviewed
    # and tweaked for this class right away.
    if params[:existing_id].present?
      source = KitchenPacket.find(params[:existing_id])
      return redirect_to nyk_list_path, notice: "#{source.title} ready." if event_url.blank?

      packet = source.copy_to!(event_url)
      KitchenPacketAutoAttacher.attach_forward(packet)
      return redirect_to edit_nyk_packet_path(packet),
                         notice: "Copied #{packet.title} to this class. Edits here stay on this class; the original recipe is untouched."
    end

    # Generate path: AI writes a draft recipe from the class name + description
    # (no document). Lands on edit for review, like the extract path.
    if params[:generate].present?
      event = event_for(event_url)
      name  = params[:event_name].presence || event&.name
      result = KitchenAi::RecipeExtractor.new(user: Current.user).generate(
        class_name: name, description: event&.description
      )
      return back_to_new(event_url, result.error) unless result.ok?

      packet = KitchenPacket.create!(
        title: name.presence || result.recipes.first["title"],
        data: { "recipes" => result.recipes },
        source_kind: "generated",
        extract_cost_cents: result.cost_cents
      )
      if event_url.present?
        packet.attach_to!(event_url)
        KitchenPacketAutoAttacher.attach_forward(packet)
      end
      return redirect_to edit_nyk_packet_path(packet),
                         notice: "Draft recipe generated with AI#{packet.extract_cost_label}. Review and edit it, then save."
    end

    pdf = params[:pdf].presence
    if pdf && pdf.size > MAX_PDF_BYTES
      return back_to_new(event_url, "PDF is too large (10 MB max).")
    end

    source_url = params[:recipe_url].to_s.strip.presence
    result = KitchenAi::RecipeExtractor.new(user: Current.user).extract(
      text: params[:recipe_text].presence,
      pdf: pdf&.read,
      url: source_url
    )
    return back_to_new(event_url, result.error) unless result.ok?

    packet = KitchenPacket.create!(
      title: params[:event_name].presence || result.recipes.first["title"],
      data: { "recipes" => result.recipes },
      source_url: source_url,
      source_kind: source_kind_for(pdf: pdf, url: source_url),
      extract_cost_cents: result.cost_cents
    )
    if event_url.present?
      packet.attach_to!(event_url)
      KitchenPacketAutoAttacher.attach_forward(packet)
    end

    redirect_to edit_nyk_packet_path(packet),
                notice: "Recipes built with the Opus model#{packet.extract_cost_label}. Review them against the preview, then save."
  end

  def edit
    @packet = KitchenPacket.find(params[:id])
    @equipment_catalog = KitchenPacket.equipment_catalog
    @pull_classes = pull_classes_for(@packet)
  end

  # Ask the AI to rewrite this packet's recipes from a free-text request
  # (e.g. "split the rolls into Tuna, Salmon, and Vegetarian plus a shared
  # rice"). Replaces data["recipes"] with the revised set; equipment is left
  # alone. Billed under the same AI line as Generate.
  def regenerate
    @packet = KitchenPacket.find(params[:id])
    event = event_for(@packet.links.first&.event_url)
    result = KitchenAi::RecipeExtractor.new(user: Current.user).regenerate(
      class_name:      event&.name.presence || @packet.title,
      description:     event&.description,
      current_recipes: @packet.recipes,
      instruction:     params[:instruction]
    )
    unless result.ok?
      return redirect_to edit_nyk_packet_path(@packet), alert: result.error
    end

    @packet.update!(
      data: @packet.data.merge("recipes" => result.recipes),
      extract_cost_cents: result.cost_cents
    )
    redirect_to edit_nyk_packet_path(@packet),
                notice: "Recipes revised with AI#{@packet.extract_cost_label}. Review the changes, then save."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_nyk_packet_path(@packet), alert: e.message
  end

  # Auto-save just the equipment list (the tag picker posts here on every
  # add/remove). Only touches data["equipment"] so unsaved recipe edits in the
  # form aren't affected.
  def update_equipment
    packet = KitchenPacket.find(params[:id])
    packet.update!(data: packet.data.merge("equipment" => parse_equipment))
    head :ok
  end

  # Delete an equipment tag from the shared palette for good (the tag picker's
  # "-" button posts here). Persisted in Setting so it stays gone across recipes.
  def hide_equipment
    KitchenPacket.hide_equipment(params[:name])
    head :ok
  end

  def update
    @packet = KitchenPacket.find(params[:id])
    # Equipment now lives on its own tab and auto-saves separately, so it is no
    # longer in this form; merge to keep the saved equipment instead of wiping it.
    @packet.update!(
      title: params[:title].presence || @packet.title,
      station_label: params[:station_label].presence || @packet.station_label,
      data: @packet.data.merge("recipes" => parse_recipes_params)
    )
    # Stay on edit so the refreshed PDF preview shows the change; "Done" on the
    # edit page is what returns to the class list once the packet looks right.
    redirect_to edit_nyk_packet_path(@packet), notice: "Saved. Preview updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_nyk_packet_path(@packet), alert: e.message
  end

  # Remove a recipe packet (and its class links via dependent: :destroy).
  # Open to any signed-in user for now; can be gated to owner/admin later.
  def destroy
    KitchenPacket.find(params[:id]).destroy!
    # Return to the library when deleted from there, else Sam's list. Only
    # allow our own in-app paths (no open redirect).
    back = params[:return_to].to_s
    dest = back.start_with?("/nykitchen/") ? back : nyk_list_path
    redirect_to dest, notice: "Packet deleted."
  end

  # The print page (HTML) embeds the PDF; the .pdf format streams it, used by
  # the preview iframe, the print page, and direct download.
  def print
    @packet = KitchenPacket.find(params[:id])
    respond_to do |format|
      format.html { render layout: false }
      format.pdf do
        send_data KitchenPacketPdf.new(@packet).render,
                  filename: "#{@packet.title.parameterize}.pdf",
                  type: "application/pdf",
                  disposition: params[:download].present? ? "attachment" : "inline"
      end
    end
  end

  private

  # Production sets a global X-Frame-Options: DENY; override to SAMEORIGIN so
  # the recipe PDF can be framed by our own edit/print pages.
  def allow_same_origin_framing
    response.headers["X-Frame-Options"] = "SAMEORIGIN"
  end

  def back_to_new(event_url, alert)
    redirect_to new_nyk_packet_path(event_url: event_url, event_name: params[:event_name]), alert: alert
  end

  # The current class for an event URL (latest snapshot), for its description.
  def event_for(url)
    return nil if url.blank?
    KitchenSnapshot.latest&.kitchen_events&.find_by(url: url)
  end

  # Classes this recipe is attached to, resolved to current events, ordered for
  # the Pull sheet tab's date dropdown: soonest upcoming run first, then any
  # past runs (most recent first) as a fallback when nothing is upcoming.
  def pull_classes_for(packet)
    snap = KitchenSnapshot.latest
    return [] unless snap
    events = packet.links.map(&:event_url).uniq.filter_map { |u| snap.kitchen_events.find_by(url: u) }
    now = Time.current
    upcoming, past = events.partition { |e| e.start_at >= now }
    upcoming.sort_by(&:start_at) + past.sort_by(&:start_at).reverse
  end

  def source_kind_for(pdf:, url:)
    return "url" if url.present?
    return "pdf" if pdf.present?
    "text"
  end

  # The edit form posts recipes as nested hashes keyed by index:
  # recipes[0][title], recipes[0][ingredients][0][qty], ... Blank ingredient
  # rows (the spare rows the form renders) are dropped here.
  def parse_recipes_params
    recipes = params[:recipes]
    return [] unless recipes.is_a?(ActionController::Parameters)

    recipes.values.map do |r|
      ingredients = (r[:ingredients]&.values || []).filter_map do |i|
        next if i[:item].blank?
        { "qty" => KitchenUnits.standardize(i[:qty]), "station_qty" => KitchenUnits.standardize(i[:station_qty]),
          "item" => IngredientText.normalize(i[:item]), "section" => i[:section].presence }
      end
      directions = (r[:directions]&.values || []).filter_map do |d|
        steps = normalize_steps(d[:steps])
        next if steps.empty?
        { "section" => d[:section].presence, "steps" => steps }
      end
      { "title" => r[:title].to_s.strip, "headcount" => parse_headcount(r[:headcount]),
        "ingredients" => ingredients, "directions" => directions }
    end.reject { |r| r["title"].blank? }
  end

  # Per-recipe headcount: a positive integer, or nil when left blank.
  def parse_headcount(raw)
    n = raw.to_s.strip
    return nil if n.blank?
    [ n.to_i, 0 ].max.then { |v| v.positive? ? v : nil }
  end

  # Equipment list from the textarea: one item per line, blanks dropped.
  def parse_equipment
    params[:equipment].to_s.split("\n").map(&:strip).reject(&:blank?)
  end

  # One step per line, but KEEP blank lines (stored as "") so the spacing Lora
  # adds between steps in the editor carries through to the PDF. Leading and
  # trailing blanks are trimmed and runs of blank lines collapse to a single
  # gap, so the spacing stays tidy and predictable.
  def normalize_steps(raw)
    lines = raw.to_s.split("\n").map(&:strip)
    lines.shift while lines.first == ""
    lines.pop   while lines.last == ""
    lines.each_with_object([]) do |line, out|
      next if line == "" && out.last == ""
      out << line
    end
  end
end
