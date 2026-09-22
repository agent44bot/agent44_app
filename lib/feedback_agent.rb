# The Mac mini side of the feedback pipeline (docs/feedback_pipeline.md).
# Plain Ruby (no Rails boot): bin/feedback-agent loads these files directly,
# and Rails autoloads them for the tests.
#
# One Worker polls the app's queue and runs one step per item:
#   plan  - Claude Code with read-only tools writes a plan (and maybe a question)
#   build - Claude Code edits and commits on feedback/<id>; the worker pushes,
#           opens or updates the PR, and reports it once CI settles
#   merge - after Rich's Merge it: re-checks the head SHA and checks against
#           GitHub, squash-merges with --match-head-commit, waits for the
#           auto-deploy, verifies prod, reports shipped
module FeedbackAgent
end
