# G4 checks incomplete shared membership fixtures. Full native Slack wiring is required in G5.
ExUnit.start(seed: 0, capture_log: true)
Code.require_file(Path.expand("../fixtures/slack_membership_schema_test.exs", __DIR__))
