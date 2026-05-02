require_relative "system_test_helper"

# Verifies the corner-web bubbles fired by web_pulses_controller:
#  - each spawn() adds a <circle> with two <animate> elements (cx, cy) heading
#    down a known strand
#  - distinct concurrent bubbles pick distinct strands (random among free ones)
#  - the animation actually runs (cx/cy actually move) — not just declared
#  - complete() flips the bubble emerald and fades it out of the DOM
class WebPulsesSystemTest < SystemTestCase
  STRAND_ENDS = [
    [198.0, 27.8],
    [185.4, 75.0],
    [157.6, 123.2],
    [123.2, 157.6],
    [75.0, 185.4],
    [27.8, 198.0]
  ].freeze

  AMBER   = "#fb923c"
  EMERALD = "#34d399"

  setup do
    @page.goto("#{BASE_URL}/", waitUntil: "networkidle")
    @page.wait_for_selector('[data-controller~="web-pulses"]')
    @page.wait_for_function("() => { const el = document.querySelector('[data-controller~=\"web-pulses\"]'); return !!(el && window.Stimulus && window.Stimulus.getControllerForElementAndIdentifier(el, 'web-pulses')); }")
  end

  test "six concurrent bubbles ride down six distinct strands" do
    strands = @page.evaluate(<<~JS)
      () => {
        const el = document.querySelector('[data-controller~="web-pulses"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'web-pulses');
        for (let i = 0; i < 6; i++) ctrl.spawn(`b-${i}`);
        const host = el.querySelector('[data-web-pulses-target="host"]');
        return Array.from(host.querySelectorAll('circle'))
          .map(c => Number(c.getAttribute('data-strand')));
      }
    JS

    assert_equal 6, strands.size, "Expected one bubble per spawn"
    assert_equal (0..5).to_a, strands.sort,
      "Expected each free strand to be used exactly once when 6 bubbles are spawned concurrently"
  end

  test "a freed strand is reused on the next spawn" do
    used, sixth = @page.evaluate(<<~JS)
      () => {
        const el = document.querySelector('[data-controller~="web-pulses"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'web-pulses');
        const host = el.querySelector('[data-web-pulses-target="host"]');

        for (let i = 0; i < 5; i++) ctrl.spawn(`fill-${i}`);
        const used = Array.from(host.querySelectorAll('circle'))
          .map(c => Number(c.getAttribute('data-strand')));

        ctrl.spawn('sixth');
        const sixth = Number(host.querySelector('circle:last-child').getAttribute('data-strand'));

        return [used, sixth];
      }
    JS

    expected_unused = (0..5).to_a - used
    assert_equal 1, expected_unused.size, "Test setup expected exactly one free strand"
    assert_equal expected_unused.first, sixth,
      "Sixth bubble should claim the only remaining free strand"
  end

  test "bubble actually travels — cx and cy move toward the strand endpoint" do
    # Spawn one bubble, sample its cx/cy a moment later. Even after a small wait
    # it should be measurably away from origin and heading toward the assigned end.
    snapshot = @page.evaluate(<<~JS)
      () => {
        const el = document.querySelector('[data-controller~="web-pulses"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'web-pulses');
        ctrl.spawn('mover');
        const circle = el.querySelector('[data-web-pulses-target="host"] circle');
        return { strand: Number(circle.getAttribute('data-strand')) };
      }
    JS

    # Let the SMIL animation tick. Travel time is 8s, so ~600ms in the bubble
    # should be ~7.5% of the way down its strand.
    @page.wait_for_timeout(600)

    moved = @page.evaluate(<<~JS)
      () => {
        const circle = document.querySelector('[data-web-pulses-target="host"] circle');
        // Use the *animated* values (the live position SMIL is driving), not the
        // base-attribute values which stay at 0 throughout.
        return { cx: circle.cx.animVal.value, cy: circle.cy.animVal.value };
      }
    JS

    end_x, end_y = STRAND_ENDS[snapshot["strand"]]

    assert moved["cx"] > 0, "cx should have advanced from 0 (got #{moved["cx"]})"
    assert moved["cy"] > 0, "cy should have advanced from 0 (got #{moved["cy"]})"
    assert moved["cx"] < end_x, "cx should still be approaching the endpoint (#{moved["cx"]} >= #{end_x})"
    assert moved["cy"] < end_y, "cy should still be approaching the endpoint (#{moved["cy"]} >= #{end_y})"
  end

  test "complete() flips amber bubble to emerald and removes it after fade" do
    state = @page.evaluate(<<~JS)
      () => {
        const el = document.querySelector('[data-controller~="web-pulses"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'web-pulses');
        const host = el.querySelector('[data-web-pulses-target="host"]');

        ctrl.spawn('agent-x');
        const circle = host.querySelector('circle');
        const fillBefore = circle.getAttribute('fill');

        ctrl.complete('agent-x');
        const fillAfter = circle.getAttribute('fill');

        return { fillBefore, fillAfter, hadCircle: !!circle };
      }
    JS

    assert state["hadCircle"], "spawn() should have appended a <circle> to the host"
    assert_equal AMBER, state["fillBefore"], "Active bubble should be amber"
    assert_equal EMERALD, state["fillAfter"], "complete() should flip the bubble to emerald"

    # Fade is 700ms; give it a comfortable margin.
    @page.wait_for_timeout(900)

    remaining = @page.evaluate(<<~JS)
      () => {
        const host = document.querySelector('[data-web-pulses-target="host"]');
        return host ? host.querySelectorAll('circle').length : -1;
      }
    JS

    assert_equal 0, remaining, "Bubble should be removed from the DOM after the fade"
  end

  test "spawn() is idempotent for the same agent id" do
    count = @page.evaluate(<<~JS)
      () => {
        const el = document.querySelector('[data-controller~="web-pulses"]');
        const ctrl = window.Stimulus.getControllerForElementAndIdentifier(el, 'web-pulses');
        ctrl.spawn('dupe');
        ctrl.spawn('dupe');
        ctrl.spawn('dupe');
        return el.querySelectorAll('[data-web-pulses-target="host"] circle').length;
      }
    JS

    assert_equal 1, count, "spawn() should ignore repeat calls for the same id"
  end
end
