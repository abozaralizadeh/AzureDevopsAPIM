# CLAUDE.md

Guidance for Claude Code (and humans) working in this repo. [README.md](README.md) is the
user-facing setup guide; the PNGs are its screenshots.

## What this is

Three PowerShell scripts for an Azure DevOps **classic release pipeline** that promotes Azure API
Management configuration from a PRE instance to BS and then PROD, using each instance's built-in
Git configuration repository (`<service>.scm.azure-api.net`). An Azure Repos Git repository sits in
between as the versioned copy. There is no application code, build or test suite.

| Stage (README screenshot) | Script | What it does |
|---|---|---|
| Update Git | `UpdateGitStage.ps1` | Writes the release artifact's source commit to the `RollBackCommit` release variable; saves PRE's live config to PRE's APIM Git repo (`Save-AzApiManagementTenantGitConfiguration`, branch `master`); clones it and force-pushes it to the Azure Repos repo; writes the pushed `HEAD` to `ReleaseCommit` |
| BS | `UpdateBsStage.ps1` | Clones the Azure Repos repo, checks out `ReleaseCommit`, force-pushes it to `master` of the BS APIM Git repo, deploys with `Publish-AzApiManagementTenantGitConfiguration` |
| Prod | `UpdateProdStage.ps1` | Same as BS, for PROD. In the screenshot Prod is not chained after BS |

Release variables are changed with a GET then PUT on
`_apis/Release/releases/<id>?api-version=6.0-preview.8`, authorised by `System.AccessToken`, so
that stages deployed later in the same release pick up the new values. APIM Git credentials come from
`Invoke-AzResourceAction -Action token` on `.../service/<name>/users/git` (api-version
`2016-10-10`), user `apim`, valid for 2 hours.

## Commands

Nothing runs locally: the scripts need an Az PowerShell context (they call `Get-AzContext` and never
sign in), Az.ApiManagement, git, and Azure DevOps release variables. Each script is meant to be
pasted as the **inline script** of an Azure PowerShell task (with an Azure service connection) in
its stage. If PowerShell 7 is installed, a parse-only check (all three parse cleanly with 7.4) is:

```bash
pwsh -NoProfile -Command '$e=$null; foreach ($f in Get-ChildItem *.ps1) { [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$e); "$($f.Name): $($e.Count) parse errors" }'
```

## Layout

```
UpdateGitStage.ps1    stage 1: APIM PRE -> Azure Repos repo, sets ReleaseCommit / RollBackCommit
UpdateBsStage.ps1     stage 2: Azure Repos repo @ ReleaseCommit -> APIM BS, publish
UpdateProdStage.ps1   stage 3: Azure Repos repo @ ReleaseCommit -> APIM PROD, publish
README.md             setup: variables, OAuth token option, "Manage releases" permission
image*.png            README screenshots (stages, agent option, permissions, stage status)
```

## Configuration

- Release pipeline variables: `ReleaseCommit` and `RollBackCommit` (settable at release time),
  `ResourceGroupPre`, `ResourceGroupBS`, `ResourceGroupProd`, `ServiceNamePre`, `ServiceNameBS`,
  `ServiceNameProd`. Values are plain text: the scripts quote them (`$X = "$(X)"`).
- Placeholders to edit in each script: `$org_name`, `$proj_name`, `$repo_name` (the Azure Repos
  repo, `<org>.visualstudio.com` URL form; they build the clone/push URLs and, in BS/Prod, the clone
  folder), and `artifact_alias` in `$(Release.Artifacts.artifact_alias.SourceVersion)` in
  `UpdateGitStage.ps1`.
- Agent job option "Allow scripts to access the OAuth token" (provides `$env:SYSTEM_ACCESSTOKEN`),
  and "Manage releases" = Allow for Project Collection Build Service (for the PUT on the release).
- The same configuration goes to every instance, so per-environment values (backend URLs etc.)
  belong in APIM named values, as the README says.

## Conventions / gotchas

- `$(Name)` is Azure DevOps macro syntax. It is expanded in the inline script text before
  PowerShell runs; it is not expanded inside a script file run by path.
- Macros on the right of an assignment are inside double quotes
  (`$ResourceGroupPre = "$(ResourceGroupPre)"`), so the expanded value is a string. Unquoted,
  PowerShell would run it as a command name (a non-terminating error, then an empty variable). A
  pipeline variable that is not defined stays as `$(Name)`, which PowerShell still runs as a
  command, so it ends up empty too.
- The clone/push URLs use `$($org_name)`, `$($proj_name)`, `$($repo_name)`: PowerShell
  subexpressions of the placeholders at the top. Azure DevOps leaves them alone (`$org_name` is not
  a variable name), just like `$($env:SYSTEM_ACCESSTOKEN)`.
- The APIM Git token (`$gitPassword`) and its URL-encoded form (`$pwUrlencodedLowerCase`) are
  registered with `Write-Host "##vso[task.setsecret]..."` right after they are created, so the agent
  masks them in any later log line (the command line itself is masked too). They are generated at
  run time, so nothing else would mask them. The scripts print only the host
  (`APIM Git host: <service>.scm.azure-api.net`); never echo `$gitUrl`, `$gitPassword` or
  `$pwUrlencodedLowerCase` (masking is only a backstop). `$env:SYSTEM_ACCESSTOKEN` is
  already a secret variable.
- BS and Prod skip the clone when the `$repo_name` folder already exists. Nothing fetches in that
  case, so `git checkout $(ReleaseCommit)` only works if that copy already has the commit.
- All pushes are forced: the Azure Repos branch is replaced by PRE's APIM history, and BS/PROD
  `master` by `ReleaseCommit`. Make changes in PRE; BS and PROD are overwritten on publish.
- No script reads `RollBackCommit`. It holds the release artifact's source commit; with the
  Azure Repos repo as the artifact, that is the state before this release, so deploying BS or
  Prod with `ReleaseCommit` set to it restores the previous configuration.
- BS and Prod are near-identical copies: a fix in one usually belongs in the other.
