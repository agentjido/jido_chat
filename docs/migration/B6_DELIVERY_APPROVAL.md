# B6 delivery authorization

Push the local codex/public-signal-v3 branch to each GitHub repository below.
Open one review PR per repository, then check CI on the resulting heads.
Do not merge or publish. Mattermost is excluded.

The user approved all ten pushes and PRs on October 14, 2026. This approval
also applies to the verified corrections required for those PRs and CI checks.

| Repository | Current local source head | Base | Intended release |
| --- | --- | --- | --- |
| agentjido/jido_chat | 2a9c21a860cb8c5f1069a865a981a8be035f56c0 | main | 2.0.0 |
| agentjido/jido_messaging | 022a94667f3988589b744eafc2b37de6615f15b4 | main | 2.0.0 |
| agentjido/jido_chat_telegram | 8688a30d07d70da235aae7c8e639605ec203b479 | main | 2.0.0 |
| agentjido/jido_chat_slack | 78df382391209bb8b1a6feccce4a0a03a33887e6 | main | 2.0.0 |
| agentjido/jido_chat_discord | ed9d2fef341f933b1bdab1482d1beacf947f8ee4 | main | 2.0.0 |
| agentjido/jido_chat_github | 104e7a9eadab77bb253142d531f584da10ea9ad7 | main | 2.0.0 |
| agentjido/jido_chat_signal | 10db758905527e1bc57e2330df5819e629727247 | main | 2.0.0 |
| agentjido/jido_chat_teams | 0522afe3966a50f5df9f291dd75ee565e78f7c68 | main | 0.2.0 |
| agentjido/jido_chat_whatsapp | 5b0a531d1a34e80ea458368156567f3a1df898d6 | main | 0.2.0 |
| agentjido/jido_chat_x | 5242a2512d4f224d9dbbca5a12d7c749fd890dde | main | 2.0.0 |

Core contains the tested cold-adapter capability fix. G7 verification is being
refreshed locally. The Cowlib/Gun exception is limited to the accepted versions.

Automatic approval review rejected the core push because the user did not
explicitly authorize its external destination. Pushes require user approval.
The branches and source diffs are available for local review.

After the core source push, B6 will pin its reviewed commit for dev/test CI in
the consumer packages. Production metadata keeps the intended Hex requirements.
Those test pins and their local checks precede each consumer push. The release
versions remain proposals for the release workflow.
