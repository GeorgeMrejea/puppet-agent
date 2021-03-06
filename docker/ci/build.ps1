$ErrorActionPreference = 'Stop'

function Get-CurrentDirectory
{
  $thisName = $MyInvocation.MyCommand.Name
  [IO.Path]::GetDirectoryName((Get-Content function:$thisName).File)
}

function Get-ContainerVersion
{
  # shallow repositories need to pull remaining code to `git describe` correctly
  if (Test-Path "$(git rev-parse --git-dir)/shallow")
  {
    git fetch --unshallow
  }

  # tags required for versioning
  git fetch origin 'refs/tags/*:refs/tags/*'
  (git describe) -replace '-.*', ''
}

function Build-Container(
  $Namespace = 'puppet',
  $Version = (Get-ContainerVersion),
  $Vcs_ref = $(git rev-parse HEAD),
  $Base = 'ubuntu')
{
  Push-Location (Join-Path (Get-CurrentDirectory) '..')

  $build_date = (Get-Date).ToUniversalTime().ToString('o')
  $subdir = if ($Base -eq 'alpine') { 'windows-build' } else { '' }
  $docker_args = @(
    '--pull',
    '--build-arg', "vcs_ref=$Vcs_ref",
    '--build-arg', "build_date=$build_date",
    '--build-arg', "version=$Version",
    '--file', "puppet-agent-$Base/$subdir/Dockerfile",
    '--tag', "$Namespace/puppet-agent-${Base}:$Version"
  )
  if ($Base -eq 'ubuntu')
  {
    $docker_args += @(
      '--tag', "$Namespace/puppet-agent:$Version"
    )
  }
  else # alpine
  {
    $docker_args += @('--memory', '3g')

    # fake multistage builds for Windows since LCOW doesn't support yet
    docker build --pull `
      --file puppet-agent-alpine/windows-build/Dockerfile.build `
      --tag $Namespace/puppet-agent-alpine:build `
      .

    docker run -v (Join-Path (Get-CurrentDirectory) 'output'):/srv `
      --rm puppet/puppet-agent-alpine:build `
      cp -a /usr/lib/ruby/vendor_ruby/facter.rb `
      /etc/puppetlabs `
      /usr/local/share `
      /usr/local/bin `
      /usr/local/lib `
      /usr/lib/ruby/gems `
      /srv
  }

  docker build $docker_args puppet-agent-$Base

  Pop-Location
}
