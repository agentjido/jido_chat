ExUnit.start(seed: 0)
defmodule AuditExceptionTest do
 use ExUnit.Case
 alias Jido.Chat.Integration.Conformance
 @policy Path.expand("../../audit-exceptions.json", __DIR__) |> File.read!() |> Jason.decode!()
 @output "Advisories:\n  cowlib 2.21.0 - EEF-CVE-2026-43966 (MEDIUM)\n  gun 2.7.0 - GHSA-w4f7-4cxr-rv3c (MEDIUM)\nFound packages with security advisories\n"
 test "only the exact accepted pair passes", do: assert Conformance.accepted_audit?(@output, @policy)
 test "another package is rejected", do: refute Conformance.accepted_audit?(@output <> "  other 1.0.0 - CVE-2026-00000 (HIGH)\n", @policy)
 test "a different version is rejected", do: refute Conformance.accepted_audit?(String.replace(@output, "2.21.0", "2.22.0"), @policy)
 test "a retirement is rejected", do: refute Conformance.accepted_audit?(@output <> "Retired packages\n", @policy)
 test "an audit task error is rejected", do: refute Conformance.accepted_audit?(@output <> "** (Mix) audit failed\n", @policy)
end
