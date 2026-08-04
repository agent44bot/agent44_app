require "test_helper"

class EmployeeNameTest < ActiveSupport::TestCase
  test "splits a two-word name" do
    assert_equal [ "Rafael", "DeGuzman" ], EmployeeName.split("Rafael DeGuzman")
  end

  test "keeps a middle name or initial with the first name" do
    assert_equal [ "Cynthia S", "Clinton" ], EmployeeName.split("Cynthia S Clinton")
  end

  test "keeps a hyphenated last name intact" do
    assert_equal [ "Michele", "Smith-Frearson" ], EmployeeName.split("Michele Smith-Frearson")
  end

  test "a one-word name has no last name" do
    assert_equal [ "Elisha", "" ], EmployeeName.split("Elisha")
  end

  test "handles blank and extra whitespace" do
    assert_equal [ "", "" ], EmployeeName.split(nil)
    assert_equal [ "Mary", "Brinkerhoff" ], EmployeeName.split("  Mary   Brinkerhoff ")
  end

  test "sorts one-word names on that name, case-insensitively" do
    names = [ "Zoe Adams", "Dacia mcwilliams", "Elisha", "Al Zimmer" ]
    assert_equal [ "Zoe Adams", "Elisha", "Dacia mcwilliams", "Al Zimmer" ],
                 names.sort_by { |n| EmployeeName.last_first_key(n) }
  end
end
