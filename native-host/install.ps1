# 사용법: .\native-host\install.ps1 [확장-ID]
# 확장 ID를 생략하면 현재 저장소의 mytools 폴더 경로에서 Chrome 압축해제 확장 ID를 자동 계산한다.
param(
  [string]$ExtensionId
)

$ErrorActionPreference = 'Stop'

$NodeCmd = Get-Command node -ErrorAction SilentlyContinue
if (-not $NodeCmd) {
  Write-Error "node를 찾지 못했습니다."
  exit 1
}
$Node = $NodeCmd.Source
$Dir = $PSScriptRoot

if (-not $ExtensionId) {
  $MyToolsPath = [System.IO.Path]::GetFullPath((Join-Path $Dir "..\mytools"))
  if ($MyToolsPath.Length -ge 2 -and $MyToolsPath[1] -eq ':') {
    $MyToolsPath = $MyToolsPath.Substring(0, 1).ToUpperInvariant() + $MyToolsPath.Substring(1)
  }
  $Bytes = [System.Text.Encoding]::Unicode.GetBytes($MyToolsPath)
  $Sha256 = [System.Security.Cryptography.SHA256]::Create()
  $HashHex = [System.BitConverter]::ToString($Sha256.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant().Substring(0, 32)
  $Chars = foreach ($c in $HashHex.ToCharArray()) {
    [char]([int][char]'a' + [Convert]::ToInt32([string]$c, 16))
  }
  $ExtensionId = -join $Chars
}

$Dest = Join-Path $env:LOCALAPPDATA "Google\Chrome\NativeMessagingHosts"
$HostCmd = Join-Path $Dest "com.personaltools.clip.cmd"
$ManifestPath = Join-Path $Dest "com.personaltools.clip.json"
$ClipHostMjs = Join-Path $Dir "clip_host.mjs"

New-Item -ItemType Directory -Force -Path $Dest | Out-Null

$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

# cmd.exe가 명령 줄을 stdout에 찍으면 Native Messaging 4바이트 길이 헤더가 깨지므로 @echo off 필수
$CmdContent = "@echo off`r`n`"$Node`" `"$ClipHostMjs`"`r`n"
[System.IO.File]::WriteAllText($HostCmd, $CmdContent, $Utf8NoBom)

$EscapedHostCmd = $HostCmd.Replace('\', '\\')
$ManifestContent = @"
{
  "name": "com.personaltools.clip",
  "description": "PersonalToolsWithAI: claude -p 요약·번역",
  "path": "$EscapedHostCmd",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$ExtensionId/"]
}
"@
[System.IO.File]::WriteAllText($ManifestPath, $ManifestContent, $Utf8NoBom)

# Windows Chrome은 레지스트리에서 Native Messaging 호스트 매니페스트 경로를 찾는다
$RegKey = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\com.personaltools.clip"
New-Item -Path $RegKey -Force | Out-Null
Set-ItemProperty -Path $RegKey -Name "(Default)" -Value $ManifestPath

Write-Host "설치됨: $ManifestPath"
Write-Host "래퍼:   $HostCmd (node: $Node)"
Write-Host "레지스트리: $RegKey"
Write-Host "확장 ID: $ExtensionId (chrome://extensions 의 ID와 다르면: .\native-host\install.ps1 <확장-ID>)"
