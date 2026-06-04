require "csv"

# NY Kitchen storage-room alcohol inventory. Two write paths — Lora scans cases
# IN (receive), Chris scans bottles OUT (remove) — recorded as InventoryMovements.
# On-hand for any item is the running Σ (in − out), so the stock list (#index) is
# always the live "what's in the room right now" view. No AI / external calls.
#
# Auth: every action requires sign-in (no allow_unauthenticated_access). This is
# an internal ops tool; ApplicationController#enforce_workspace_scope already
# permits NYK workspace members to reach /nykitchen/*.
class InventoryController < ApplicationController
  before_action :set_item, only: %i[show_item edit_item update_item]

  # Stock list — current on-hand per item, with search / category / low-stock
  # filters. on_hand pulled in one grouped query to avoid N+1.
  def index
    @on_hand = InventoryItem.on_hand_by_item
    @items   = InventoryItem.by_name.to_a

    if (@category = params[:category].presence)
      @items.select! { |i| i.category == @category }
    end
    if (q = params[:q].presence)
      needle = q.downcase
      @items.select! { |i| "#{i.name} #{i.producer}".downcase.include?(needle) }
    end
    @low_only = params[:low] == "1"
    @items.select! { |i| i.low_stock?(@on_hand[i.id].to_i) } if @low_only

    @total_units = @on_hand.values.sum
    @low_count   = InventoryItem.where.not(par_level: nil).select { |i| i.low_stock?(@on_hand[i.id].to_i) }.size

    render "inventory/index", layout: "application"
  end

  # Lora's scan-in console (receives cases). Shared scan UI, direction "in".
  def receive
    render "inventory/receive", layout: "application"
  end

  # Chris's scan-out console (draws down bottles). Shared scan UI, direction "out".
  def remove
    render "inventory/remove", layout: "application"
  end

  # JSON for the scan console. `code` → exact bottle/case-code match (camera or
  # hardware scanner). `q` → name search, for items that won't scan / have no
  # barcode (Chris finds them by typing).
  def lookup
    if (q = params[:q].presence)
      items = InventoryItem.where("LOWER(name) LIKE ?", "%#{q.strip.downcase}%").by_name.limit(10)
      return render json: { results: items.map { |i| item_json(i) } }
    end

    code = params[:code].to_s.strip
    item = InventoryItem.find_by_code(code)
    if item
      render json: { found: true, item: item_json(item, scanned_code: code) }
    else
      render json: { found: false, code: code }
    end
  end

  # Record an in/out movement. Accepts item_id OR a scanned code; when the code
  # is unknown and item[...] fields are present (receive flow's inline setup),
  # the item is created first, then the movement.
  def create_movement
    code = params[:code].to_s.strip
    item =
      if params[:item_id].present?
        InventoryItem.find_by(id: params[:item_id])
      else
        InventoryItem.find_by_code(code)
      end

    if item.nil? && params[:item].present?
      item = InventoryItem.new(item_params)
      return respond_movement(ok: false, errors: item.errors.full_messages) unless item.save
    end

    return respond_movement(ok: false, errors: [ "Unknown item — set it up first." ]) if item.nil?

    qty = params[:quantity].presence&.to_i || item.units_for_code(code)
    movement = item.movements.build(
      direction:    params[:direction].to_s,
      quantity:     qty,
      user:         Current.user,
      scanned_code: code.presence,
      note:         params[:note].presence
    )

    if movement.save
      respond_movement(ok: true, item: item, movement: movement)
    else
      respond_movement(ok: false, errors: movement.errors.full_messages)
    end
  end

  def new_item
    @item = InventoryItem.new(barcode: params[:code], units_per_case: 12)
    render "inventory/item_form", layout: "application"
  end

  def create_item
    @item = InventoryItem.new(item_params)
    if @item.save
      redirect_to nyk_inventory_item_path(@item), notice: "#{@item.name} added to the catalog."
    else
      render "inventory/item_form", layout: "application", status: :unprocessable_entity
    end
  end

  def show_item
    @on_hand    = @item.on_hand
    @movements  = @item.movements.recent.includes(:user).limit(200)
    render "inventory/show_item", layout: "application"
  end

  def edit_item
    render "inventory/item_form", layout: "application"
  end

  def update_item
    if @item.update(item_params)
      redirect_to nyk_inventory_item_path(@item), notice: "Updated #{@item.name}."
    else
      render "inventory/item_form", layout: "application", status: :unprocessable_entity
    end
  end

  # Bootstrap from Chris's spreadsheet. GET shows the upload form.
  def import
    render "inventory/import", layout: "application"
  end

  # CSV upload → seeds the catalog and an opening-balance "in" movement per new
  # row. Header mapping is intentionally forgiving; FINALIZE against Chris's real
  # column names once we have his sheet. Existing items (matched by barcode or
  # name) get catalog fields refreshed but NO new opening movement, so re-running
  # an import can't double-count on-hand.
  def import_upload
    file = params[:file]
    return redirect_to(nyk_inventory_import_path, alert: "Choose a CSV file to import.") if file.blank?

    created = updated = opened = 0
    CSV.parse(file.read, headers: true, header_converters: ->(h) { h.to_s.strip.downcase }) do |row|
      h = row.to_h
      name = pick(h, "name", "product", "item", "description")
      next if name.blank?

      barcode = pick(h, "barcode", "upc", "sku")
      item = (barcode.present? && InventoryItem.find_by(barcode: barcode)) ||
             InventoryItem.find_by("LOWER(name) = ?", name.downcase)
      is_new = item.nil?
      item ||= InventoryItem.new

      item.assign_attributes(
        name:           name,
        category:       pick(h, "category", "type"),
        size:           pick(h, "size", "volume"),
        producer:       pick(h, "producer", "brand", "winery"),
        vintage:        pick(h, "vintage", "year"),
        vendor:         pick(h, "vendor", "supplier", "distributor"),
        barcode:        barcode.presence || item.barcode,
        par_level:      pick(h, "par", "par_level", "reorder", "min").presence&.to_i,
        units_per_case: pick(h, "units_per_case", "case_size", "pack").presence&.to_i || item.units_per_case || 12
      )
      next unless item.save

      is_new ? created += 1 : updated += 1

      # Opening balance only for brand-new items, so re-imports don't double-count.
      if is_new
        qty = pick(h, "quantity", "qty", "on_hand", "count", "stock").to_i
        if qty.positive?
          item.movements.create!(direction: "in", quantity: qty, user: Current.user,
                                 note: "Opening balance (spreadsheet import)")
          opened += 1
        end
      end
    end

    redirect_to nyk_inventory_path,
                notice: "Imported #{created} new, updated #{updated}, set opening stock on #{opened}."
  rescue CSV::MalformedCSVError => e
    redirect_to nyk_inventory_import_path, alert: "Couldn't parse that CSV: #{e.message}"
  end

  # ── Photo + price capture log ─────────────────────────────────────────────
  # Snap a product photo, record quantity + unit price + category. Rows
  # accumulate per month and export to a spreadsheet (CSV). Self-contained:
  # does NOT touch the on-hand ledger — it's a purchase/tracking record.
  def captures
    @month_label, @from, @to = capture_range
    @month_param = @from.strftime("%Y-%m")
    @capture  = InventoryCapture.new
    @captures = InventoryCapture.in_range(@from, @to).recent.with_attached_photo.includes(:user)
    @total    = @captures.sum(&:line_total)
    render "inventory/captures", layout: "application"
  end

  def create_capture
    @capture = InventoryCapture.new(capture_params)
    @capture.user = Current.user
    if @capture.save
      redirect_to nyk_inventory_captures_path,
                  notice: "Logged #{@capture.name.presence || @capture.category.presence || 'item'}."
    else
      redirect_to nyk_inventory_captures_path, alert: @capture.errors.full_messages.to_sentence
    end
  end

  def captures_export
    _, from, to = capture_range
    rows = InventoryCapture.in_range(from, to).recent.with_attached_photo.includes(:user)
    csv = CSV.generate do |out|
      out << [ "Date", "Category", "Product", "Quantity", "Unit", "Unit price", "Line total", "Destination", "Logged by", "Photo" ]
      rows.each do |c|
        out << [
          c.captured_at.strftime("%Y-%m-%d %H:%M"),
          c.category, c.name, c.quantity, c.unit,
          (c.unit_price ? format("%.2f", c.unit_price) : ""),
          format("%.2f", c.line_total),
          c.destination,
          c.user&.display_identifier,
          (c.photo.attached? ? rails_blob_url(c.photo) : "")
        ]
      end
    end
    send_data csv, filename: "nyk-inventory-#{from.strftime('%Y-%m')}.csv", type: "text/csv"
  end

  # Delete a logged capture (mistyped price, wrong photo, duplicate). The photo
  # blob is purged automatically by ActiveStorage on destroy.
  def destroy_capture
    InventoryCapture.find(params[:id]).destroy
    redirect_back fallback_location: nyk_inventory_captures_path, notice: "Entry deleted."
  end

  private

  def capture_params
    params.require(:capture).permit(:category, :name, :quantity, :unit, :unit_price, :note, :destination, :photo)
  end

  # [label, from, to] for the requested month (?month=YYYY-MM), default this month.
  def capture_range
    month = begin
      Date.strptime(params[:month].to_s, "%Y-%m")
    rescue ArgumentError, TypeError
      Date.current
    end.beginning_of_month
    [ month.strftime("%B %Y"), month.beginning_of_day, month.end_of_month.end_of_day ]
  end

  def set_item
    @item = InventoryItem.find(params[:id])
  end

  def item_params
    params.require(:item).permit(:name, :category, :size, :producer, :vintage, :vendor,
                                 :barcode, :case_barcode, :units_per_case, :par_level, :notes)
  end

  # First non-blank value among the given header aliases.
  def pick(hash, *keys)
    keys.map { |k| hash[k] }.find { |v| v.to_s.strip.present? }.to_s.strip
  end

  def item_json(item, scanned_code: nil)
    on_hand = item.on_hand
    {
      id:             item.id,
      name:           item.name,
      category:       item.category,
      size:           item.size,
      producer:       item.producer,
      on_hand:        on_hand,
      units_per_case: item.units_per_case,
      low_stock:      item.low_stock?(on_hand),
      default_in:     item.units_for_code(scanned_code) # case code → units_per_case, else 1
    }
  end

  def movement_json(m)
    { id: m.id, direction: m.direction, quantity: m.quantity, occurred_at: m.occurred_at.iso8601 }
  end

  def respond_movement(ok:, item: nil, movement: nil, errors: [])
    respond_to do |format|
      format.json do
        if ok
          render json: { ok: true, item: item_json(item), movement: movement_json(movement) }
        else
          render json: { ok: false, errors: errors }, status: :unprocessable_entity
        end
      end
      format.html do
        if ok
          redirect_back fallback_location: nyk_inventory_path,
                        notice: "#{movement.direction == 'in' ? 'Received' : 'Removed'} #{movement.quantity} × #{item.name}."
        else
          redirect_back fallback_location: nyk_inventory_path, alert: errors.to_sentence
        end
      end
    end
  end
end
