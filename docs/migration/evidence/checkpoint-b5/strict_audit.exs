app = Mix.Project.config()[:app]
Mix.Project.pop()
Mix.Project.in_project(app, File.cwd!(), [hex: [ignore_advisories: [], ignore_retirements: []]], fn _ -> Mix.Task.run("hex.audit") end)
