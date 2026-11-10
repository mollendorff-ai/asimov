# Security Policy

## Important context

Asimov launches AI coding agents with their approval prompts turned off, and its build mode runs them unattended. That autonomy is the point of the tool, so an agent doing something harmful inside the session is not a vulnerability in Asimov. Use it only in a sandbox (a VM or a container) with nothing in it you cannot afford to lose, as the README explains.

## Supported versions

Only the latest release gets security fixes. `asimov update` installs it.

## Reporting a vulnerability

Please do not open a public issue for a security problem.

Email **security@mollendorff.ai** with:

- what you found and what it lets someone do,
- steps that reproduce it,
- the Asimov version (`asimov --version`), the agent CLI you used and your operating system.

You can also use GitHub's private vulnerability reporting, under the **Security** tab of this repository, if it is enabled.

Asimov is a personal tool kept up on a best-effort basis. I aim to reply within 14 days, and I will tell you what I plan to do about the report. Please give me reasonable time to ship a fix before you share the details publicly. I am glad to credit you in the release notes if you want that.

## What is in scope

- `install.sh` and `asimov update`, which download a release from GitHub and check every file against its SHA256SUMS before installing.
- Anything that makes the sandbox setting (`build.sandbox`) or the spending cap (`--max-usd`) fail to do what the README says.
- The pre-commit hook and the other files Asimov writes into a project: whether they can be made to run something the user did not ask for.
- How build mode reads spec files and URLs, and what it does with them.
- The GitHub Actions workflows that build and publish releases, including their permissions.

## What is not in scope

- The agent CLIs Asimov starts (Claude Code, Gemini CLI, Codex CLI): report those to their vendors.
- What an agent chooses to do once it runs without approval prompts, including actions that follow instructions hidden in a spec, a web page or a repository.
- A failing test or a bad build result is a bug, not a security problem: please open a normal issue for those.
