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
its stage. If PowerShell 7 is installed, a parse-only check (all three parse cleanly) is:

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
  `ServiceNameProd`.
- Placeholders to edit in each script: `$org_name`, `$proj_name`, `$repo_name` (the Azure Repos
  repo, `<org>.visualstudio.com` URL form), and `artifact_alias` in
  `$(Release.Artifacts.artifact_alias.SourceVersion)` in `UpdateGitStage.ps1`.
- Agent job option "Allow scripts to access the OAuth token" (provides `$env:SYSTEM_ACCESSTOKEN`),
  and "Manage releases" = Allow for Project Collection Build Service (for the PUT on the release).
- The same configuration goes to every instance, so per-environment values (backend URLs etc.)
  belong in APIM named values, as the README says.

## Conventions / gotchas

- `$(Name)` is Azure DevOps macro syntax. It is expanded in the inline script text before
  PowerShell runs; it is not expanded inside a script file run by path.
- Macros sit unquoted on the right of assignments (`$ResourceGroupPre = $(ResourceGroupPre)`).
  After expansion PowerShell runs a bare value as a command name unless the variable's value
  carries its own quotes. The error is non-terminating, so the script carries on with an empty
  variable (checked with PowerShell 7.4).
- The clone/push URLs use `$(org_name)`, `$(proj_name)`, `$(repo_name)`: macro syntax, not the
  PowerShell variables set at the top. Without pipeline variables of those names, PowerShell runs
  them as commands and the URL gets empty segments (`https://<token>@.visualstudio.com//_git/`).
  `cd $repo_name` does use the PowerShell variable.
- `UpdateBsStage.ps1` sets `$ResourceGroupBS = $(ResourceGroupPre)`, so the BS stage looks for the
  BS service in the PRE resource group and the `ResourceGroupBS` variable is never read.
- In the BS and Prod scripts the "Skip Clone" check tests for the PRE clone folder
  (`<ServiceNamePre>.scm.azure-api.net`), but the script then `cd`s into `$repo_name`.
- Every script echoes `$gitUrl`, which embeds the APIM Git token; `UpdateBsStage.ps1` also echoes
  the password and its URL-encoded form. They are generated at run time, so Azure DevOps does not
  mask them. Do not add more output like this.
- All pushes are forced: the Azure Repos branch is replaced by PRE's APIM history, and BS/PROD
  `master` by `ReleaseCommit`. Make changes in PRE; BS and PROD are overwritten on publish.
- No script reads `RollBackCommit`. It holds the release artifact's source commit; with the
  Azure Repos repo as the artifact, that is the state before this release, so deploying BS or
  Prod with `ReleaseCommit` set to it restores the previous configuration.
- BS and Prod are near-identical copies: a fix in one usually belongs in the other.
