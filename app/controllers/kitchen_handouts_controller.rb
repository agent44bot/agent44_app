# Recipe handouts for NY Kitchen classes, attached from Sam's list page.
# Flow: open a class on Sam's list -> "+ Recipe" -> new (upload a PDF, paste a
# recipe URL, or reuse an existing packet) -> create runs the AI extraction ->
# edit reviews the recipe with a live PDF preview -> print renders the branded
# NY Kitchen PDF (full pages then single-station pages).
class KitchenHandoutsController < ApplicationController
  MAX_PDF_BYTES = 10.megabytes

  # The edit and print pages embed the recipe PDF (served by #print) in an
  # iframe. The app-wide CSP sets frame-ancestors 'none' and production sets
  # X-Frame-Options: DENY, which block even same-origin framing, so relax both
  # to self for these actions (mirrors KitchenController's display preview).
  content_security_policy(only: %i[edit print]) do |policy|
    policy.frame_ancestors :self
  end
  after_action :allow_same_origin_framing, only: %i[edit print]

  # Searchable recipe library: browse/search every packet, then Edit/Print/Delete.
  def index
    @q = params[:q].to_s.strip
    @handouts = KitchenHandout.search(@q).order(:title)
    @attach_counts = KitchenHandoutLink.group(:kitchen_handout_id).count
  end

  def new
    @event_url  = params[:event_url].to_s
    @event_name = params[:event_name].to_s
    @q = params[:q].to_s.strip
    if @q.present?
      # Searching the full library: title or recipe-content match, no similarity
      # suggestion (the search box is the explicit pick).
      @existing = KitchenHandout.search(@q).order(:title).limit(50).to_a
      @suggested = nil
    else
      # Reuse picker: recurring classes share a packet (the Aug run reuses
      # May's upload). Name-similarity match floats the best candidate first.
      @existing = KitchenHandout.order(updated_at: :desc).limit(25).to_a
      @suggested = @existing.max_by { |h| name_similarity(h.title, @event_name) } if @event_name.present?
      @suggested = nil if @suggested && name_similarity(@suggested.title, @event_name) < 0.3
    end
  end

  def create
    event_url = params[:event_url].to_s

    # Reuse path: COPY an existing packet onto this class, no AI involved. A copy
    # (not a shared link) so editing or deleting this class's recipe never
    # touches the packet it came from. Land on edit so the copy can be reviewed
    # and tweaked for this class right away.
    if params[:existing_id].present?
      source = KitchenHandout.find(params[:existing_id])
      return redirect_to nyk_list_path, notice: "#{source.title} ready." if event_url.blank?

      handout = source.copy_to!(event_url)
      KitchenPacketAutoAttacher.attach_forward(handout)
      return redirect_to edit_nyk_handout_path(handout),
                         notice: "Copied #{handout.title} to this class. Edits here stay on this class; the original packet is untouched."
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

    handout = KitchenHandout.create!(
      title: params[:event_name].presence || result.recipes.first["title"],
      data: { "recipes" => result.recipes },
      source_url: source_url,
      source_kind: source_kind_for(pdf: pdf, url: source_url),
      extract_cost_cents: result.cost_cents
    )
    if event_url.present?
      handout.attach_to!(event_url)
      KitchenPacketAutoAttacher.attach_forward(handout)
    end

    redirect_to edit_nyk_handout_path(handout),
                notice: "Recipes built with the Opus model#{handout.extract_cost_label}. Review them against the preview, then save."
  end

  def edit
    @handout = KitchenHandout.find(params[:id])
    @equipment_catalog = KitchenHandout.equipment_catalog
  end

  # Delete an equipment tag from the shared palette for good (the tag picker's
  # "-" button posts here). Persisted in Setting so it stays gone across recipes.
  def hide_equipment
    KitchenHandout.hide_equipment(params[:name])
    head :ok
  end

  def update
    @handout = KitchenHandout.find(params[:id])
    @handout.update!(
      title: params[:title].presence || @handout.title,
      station_label: params[:station_label].presence || @handout.station_label,
      data: { "recipes" => parse_recipes_params, "equipment" => parse_equipment }
    )
    # Stay on edit so the refreshed PDF preview shows the change; "Done" on the
    # edit page is what returns to the class list once the packet looks right.
    redirect_to edit_nyk_handout_path(@handout), notice: "Saved. Preview updated."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_nyk_handout_path(@handout), alert: e.message
  end

  # Remove a recipe handout (and its class links via dependent: :destroy).
  # Open to any signed-in user for now; can be gated to owner/admin later.
  def destroy
    KitchenHandout.find(params[:id]).destroy!
    # Return to the library when deleted from there, else Sam's list. Only
    # allow our own in-app paths (no open redirect).
    back = params[:return_to].to_s
    dest = back.start_with?("/nykitchen/") ? back : nyk_list_path
    redirect_to dest, notice: "Recipe deleted."
  end

  # The print page (HTML) embeds the PDF; the .pdf format streams it, used by
  # the preview iframe, the print page, and direct download.
  def print
    @handout = KitchenHandout.find(params[:id])
    respond_to do |format|
      format.html { render layout: false }
      format.pdf do
        send_data KitchenHandoutPdf.new(@handout).render,
                  filename: "#{@handout.title.parameterize}.pdf",
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
    redirect_to new_nyk_handout_path(event_url: event_url, event_name: params[:event_name]), alert: alert
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
      { "title" => r[:title].to_s.strip, "ingredients" => ingredients, "directions" => directions }
    end.reject { |r| r["title"].blank? }
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

  # Cheap token-overlap similarity for the reuse suggestion; good enough to
  # match "Fresh Pasta: Ravioli Workshop 8/6/26" to "Fresh Pasta Ravioli".
  def name_similarity(a, b)
    ta = a.to_s.downcase.scan(/[a-z]+/).to_set
    tb = b.to_s.downcase.scan(/[a-z]+/).to_set
    return 0.0 if ta.empty? || tb.empty?
    (ta & tb).size.to_f / [ ta.size, tb.size ].min
  end
end
