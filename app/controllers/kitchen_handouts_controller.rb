# Recipe handouts for NY Kitchen classes, attached from Sam's list page.
# Flow: "+ Recipe" on a class -> new (paste text / upload PDF, or reuse an
# existing packet) -> create runs the AI extraction -> edit to review and fix
# (especially the proposed single-station quantities) -> print renders the
# branded packet, full pages then station pages.
class KitchenHandoutsController < ApplicationController
  MAX_PDF_BYTES = 10.megabytes

  def new
    @event_url  = params[:event_url].to_s
    @event_name = params[:event_name].to_s
    # Reuse picker: recurring classes share a packet (the Aug run reuses
    # May's upload). Name-similarity match floats the best candidate first.
    @existing = KitchenHandout.order(updated_at: :desc).limit(25).to_a
    @suggested = @existing.max_by { |h| name_similarity(h.title, @event_name) } if @event_name.present?
    @suggested = nil if @suggested && name_similarity(@suggested.title, @event_name) < 0.3
  end

  def create
    event_url = params[:event_url].to_s

    # Reuse path: attach an existing packet to this class, no AI involved.
    if params[:existing_id].present?
      handout = KitchenHandout.find(params[:existing_id])
      handout.attach_to!(event_url) if event_url.present?
      return redirect_to nyk_list_path, notice: "#{handout.title} attached. Print it from the class row."
    end

    pdf = params[:pdf].presence
    if pdf && pdf.size > MAX_PDF_BYTES
      return redirect_to new_nyk_handout_path(event_url: event_url, event_name: params[:event_name]),
                         alert: "PDF is too large (10 MB max)."
    end

    result = KitchenAi::RecipeExtractor.new(user: Current.user).extract(
      text: params[:recipe_text].presence,
      pdf: pdf&.read
    )

    unless result.ok?
      return redirect_to new_nyk_handout_path(event_url: event_url, event_name: params[:event_name]),
                         alert: result.error
    end

    handout = KitchenHandout.create!(
      title: params[:event_name].presence || result.recipes.first["title"],
      data: { "recipes" => result.recipes }
    )
    handout.attach_to!(event_url) if event_url.present?

    redirect_to edit_nyk_handout_path(handout),
                notice: "Recipes extracted. Review the quantities below, the station column is a proposal."
  end

  def edit
    @handout = KitchenHandout.find(params[:id])
  end

  def update
    @handout = KitchenHandout.find(params[:id])
    @handout.update!(
      title: params[:title].presence || @handout.title,
      station_label: params[:station_label].presence || @handout.station_label,
      data: { "recipes" => parse_recipes_params }
    )
    redirect_to print_nyk_handout_path(@handout), notice: "Saved."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_nyk_handout_path(@handout), alert: e.message
  end

  def print
    @handout = KitchenHandout.find(params[:id])
    render layout: false
  end

  private

  # The edit form posts recipes as nested hashes keyed by index:
  # recipes[0][title], recipes[0][ingredients][0][qty], ... Blank ingredient
  # rows (the spare rows the form renders) are dropped here.
  def parse_recipes_params
    recipes = params[:recipes]
    return [] unless recipes.is_a?(ActionController::Parameters)

    recipes.values.map do |r|
      ingredients = (r[:ingredients]&.values || []).filter_map do |i|
        next if i[:item].blank?
        { "qty" => i[:qty].to_s.strip, "station_qty" => i[:station_qty].to_s.strip,
          "item" => i[:item].to_s.strip, "section" => i[:section].presence }
      end
      directions = (r[:directions]&.values || []).filter_map do |d|
        steps = d[:steps].to_s.split(/\n+/).map(&:strip).reject(&:blank?)
        next if steps.empty?
        { "section" => d[:section].presence, "steps" => steps }
      end
      { "title" => r[:title].to_s.strip, "ingredients" => ingredients, "directions" => directions }
    end.reject { |r| r["title"].blank? }
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
