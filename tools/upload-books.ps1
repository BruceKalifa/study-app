# Solvit 교재 올리기
# 선생님 PC에서 `_서버에 올릴 교재` 폴더의 .pulinote 파일을 전부 서버 교재 창고에 올린다.
# 보통은 같은 폴더의 `교재 올리기.bat` 을 더블클릭하면 이 파일이 실행된다.
# 비밀번호는 이 PC 에서만 쓰이고, 어디에도 저장되지 않는다.
param(
  [string]$Server = 'https://pulinote-server.onrender.com',
  [string]$Folder = '',
  [string]$Id = '',
  [string]$Password = '',  # 시험용 — 평소엔 비워 두면 물어본다
  [string]$Open = ''       # 시험용 — 'y' 또는 'n' (비우면 물어본다)
)
$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
if (-not $Folder) { $Folder = Join-Path $PSScriptRoot '_서버에 올릴 교재' }
$Server = $Server.TrimEnd('/')

function Get-ErrorText($err) {
  $msg = ''
  try {
    if ($err.ErrorDetails -and $err.ErrorDetails.Message) {
      $msg = $err.ErrorDetails.Message
    } elseif ($err.Exception.Response) {
      $stream = $err.Exception.Response.GetResponseStream()
      $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::UTF8)
      $msg = $reader.ReadToEnd()
    }
  } catch {}
  if ($msg) {
    try { $j = $msg | ConvertFrom-Json; if ($j.error) { return [string]$j.error } } catch {}
    return $msg
  }
  return $err.Exception.Message
}

Write-Host ''
Write-Host '=== Solvit 교재 올리기 ===' -ForegroundColor Cyan
Write-Host "서버: $Server"
Write-Host "폴더: $Folder"
Write-Host ''

if (-not (Test-Path -LiteralPath $Folder)) {
  Write-Host '폴더를 찾을 수 없어요. "_서버에 올릴 교재" 폴더가 이 파일과 같은 곳에 있어야 해요.' -ForegroundColor Red
  exit 1
}
$files = @(Get-ChildItem -LiteralPath $Folder -Filter *.pulinote -File | Sort-Object Name)
if ($files.Count -eq 0) {
  Write-Host '올릴 .pulinote 파일이 없어요.' -ForegroundColor Yellow
  exit 0
}
Write-Host "올릴 교재 $($files.Count)개:"
foreach ($f in $files) {
  $mb = [math]::Round($f.Length / 1MB, 1)
  Write-Host "  - $($f.Name)  ($mb MB)"
}
Write-Host ''

if (-not $Id) { $Id = (Read-Host '선생님 아이디').Trim() }
if (-not $Password) {
  $sec = Read-Host '비밀번호 (입력해도 화면에 안 보여요)' -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
if (-not $Open) {
  $a = Read-Host '올리면서 바로 모든 학생에게 열까요? (Enter = 예, n = 아니요)'
  $Open = if ($a -match '^[nN]') { 'n' } else { 'y' }
}
$openFlag = if ($Open -match '^[nN]') { 0 } else { 1 }

Write-Host ''
Write-Host '로그인 중… (서버가 자고 있었다면 30초쯤 걸릴 수 있어요)'
$token = ''
try {
  $json = @{ loginId = $Id; password = $Password } | ConvertTo-Json -Compress
  $login = Invoke-RestMethod -Method Post -Uri "$Server/api/auth/login" `
    -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($json)) -TimeoutSec 90
} catch {
  Write-Host ('로그인하지 못했어요: ' + (Get-ErrorText $_)) -ForegroundColor Red
  exit 1
} finally {
  $Password = $null
}
if (-not $login -or -not $login.user -or $login.user.role -ne 'teacher') {
  Write-Host '선생님 계정으로 들어와 주세요.' -ForegroundColor Red
  exit 1
}
$token = $login.token
Write-Host "$($login.user.name) 선생님, 안녕하세요." -ForegroundColor Green
Write-Host ''

$ok = 0
$bad = 0
try {
  foreach ($f in $files) {
    Write-Host "올리는 중: $($f.Name) …"
    try {
      $res = Invoke-RestMethod -Method Post -Uri "$Server/api/books?open=$openFlag" `
        -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/octet-stream' `
        -InFile $f.FullName -TimeoutSec 600
      $b = $res.book
      $what = if ($res.replaced) { '같은 교재를 바꿔 끼웠어요' } else { '올렸어요' }
      Write-Host "  완료  $($b.title) - $what ($($b.problems)문항)" -ForegroundColor Green
      $ok++
    } catch {
      Write-Host ('  실패  ' + $f.Name + ': ' + (Get-ErrorText $_)) -ForegroundColor Red
      $bad++
    }
  }
} finally {
  try {
    Invoke-RestMethod -Method Post -Uri "$Server/api/auth/logout" -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 20 | Out-Null
  } catch {}
}

Write-Host ''
if ($bad -eq 0) {
  Write-Host "끝! ${ok}개 모두 올렸어요. 학생 앱은 켤 때 저절로 받아가요." -ForegroundColor Cyan
} else {
  Write-Host "${ok}개 올렸고 ${bad}개는 실패했어요. 위의 메시지를 확인해 주세요." -ForegroundColor Yellow
  exit 1
}
