# B6 delivery — October 14, 2026

G7 passes. G8 implementation readiness passes with publish_ready false.
G9 is running. All ten PRs are open and attached. Final current-head CI and the delivery index remain.
No merge, publication or live provider operation is included.

The migration guide, public READMEs, version proposals, production metadata,
package file lists, ten package builds, publication order and rollback pins are
saved. Development and test use exact Git commits. Production metadata has no
path dependency or source cache. The source comparison names the compatible
upstream release blockers. Current published Signal lacks the required Catalog
and router DSL. Published Jido AI 2.x requires Jido 2.x.

The local review found and fixed cold adapter loading, missing adapter fixtures,
CI selection of an incompatible published Signal, local sibling test paths, and
stale public README examples. All required local checks pass. The corrected
consumer source commits passed CI. Final documentation commits require current
CI results before G9 can pass.

See evidence/checkpoint-b5-scope-update/pr-delivery.json and release-readiness.json.

The core automated review failed on GitHub's 300-file diff limit and the shell
argument size limit. The local review packet now uses the complete Git file
inventory and a bounded local patch. Its 350-document fixture passes.
Current-head CI must confirm this workflow correction.
