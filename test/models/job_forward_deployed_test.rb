require "test_helper"

class JobForwardDeployedTest < ActiveSupport::TestCase
  def job(title:, description: nil, category: "full_time")
    Job.create!(title: title, url: "https://example.com/#{SecureRandom.hex(6)}",
                category: category, description: description)
  end

  test "matches the spelled-out forms in the title (case-insensitive)" do
    j1 = job(title: "Forward Deployed Engineer")
    j2 = job(title: "Senior Forward-Deployed AI Engineer")
    j3 = job(title: "forward deployed software engineer")
    assert_includes Job.forward_deployed, j1
    assert_includes Job.forward_deployed, j2
    assert_includes Job.forward_deployed, j3
  end

  test "matches the FDE acronym only with word boundaries" do
    hit1 = job(title: "Forward Deployed Engineer (FDE) Partner Lead")
    hit2 = job(title: "Lead FDE Solutions")           # "FDE " prefix
    hit3 = job(title: "Senior FDE Engineer")          # " FDE "
    assert_includes Job.forward_deployed, hit1
    assert_includes Job.forward_deployed, hit2
    assert_includes Job.forward_deployed, hit3
  end

  test "matches forward deployed mentioned only in the description" do
    j = job(title: "AI Engineer", description: "You will be forward deployed with our largest customer.")
    assert_includes Job.forward_deployed, j
  end

  test "does not match unrelated roles or FDE-substring words" do
    miss1 = job(title: "Senior Test Automation Engineer")
    miss2 = job(title: "Confidence Builder")  # contains 'fde'? no — guards against loose LIKE
    assert_not_includes Job.forward_deployed, miss1
    assert_not_includes Job.forward_deployed, miss2
  end
end
