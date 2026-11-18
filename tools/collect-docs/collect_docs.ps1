#Requires -Version 5.1
<#
    문서 수집 도구 (사내 AI 비서용)

    이 스크립트가 하는 일
      1. 이 PC의 바탕화면, 문서, 다운로드 폴더에서 업무 문서 파일만 찾습니다.
      2. 사진, 동영상, 프로그램, 임시 파일은 건드리지 않습니다.
      3. 파일 이름에 민감한 단어(비밀번호, 계좌 등)가 있으면 복사하지 않습니다.
      4. 내용이 완전히 같은 파일은 하나만 복사합니다.
      5. NAS의 "AI비서/개인/부서/이름" 폴더에 원래 폴더 구조대로 복사합니다.
      6. 원본 파일은 절대 지우거나 옮기지 않습니다. 복사만 합니다.
      7. 무엇을 복사했는지 목록(CSV)을 NAS와 이 PC에 남깁니다.

    실행 방법
      - 같은 폴더의 "1_미리보기.bat"  : 복사하지 않고 무엇을 복사할지 목록만 봅니다.
      - 같은 폴더의 "2_수집실행.bat"  : 실제로 복사합니다.
      - 설정은 같은 폴더의 collect_config.json 에서 바꿉니다.

    직접 실행할 때 쓸 수 있는 옵션
      -DryRun     복사하지 않고 목록만 만듭니다.
      -FullScan   바탕화면/문서/다운로드가 아니라 PC의 모든 드라이브를 검색합니다. (오래 걸림)
      -NoPrompt   질문 없이 진행합니다. (자동 실행용)
      -ConfigPath 다른 설정 파일을 지정합니다.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = "",
    [switch]$DryRun,
    [switch]$FullScan,
    [switch]$NoPrompt
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ---------------------------------------------------------------------------
# 1. 설정 읽기
# ---------------------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ConfigPath) { $ConfigPath = Join-Path $ScriptDir 'collect_config.json' }

# 설정 파일이 없거나 일부 항목이 빠져 있을 때 쓰는 기본값
$Config = @{
    Destination         = '\\NAS\AI비서\개인'          # NAS 공유 폴더 (팀장이 설정)
    Department          = '기술지원부'
    UserName            = ''                            # 비워 두면 실행할 때 물어봄
    SourceFolders       = @('Desktop', 'Documents', 'Downloads')
    ExtraFolders        = @()                           # 추가로 검색할 폴더 (예: "D:\업무")
    Extensions          = @('pdf', 'doc', 'docx', 'xls', 'xlsx', 'xlsm', 'ppt', 'pptx',
                            'hwp', 'hwpx', 'txt', 'csv', 'rtf', 'md')
    ExcludeDirNames     = @('AppData', '$Recycle.Bin', 'Windows', 'Program Files', 'Program Files (x86)',
                            'ProgramData', 'node_modules', '.git', '.cache', 'Temp', 'tmp',
                            'System Volume Information', 'OneDriveTemp', '$WinREAgent')
    ExcludeNameKeywords = @('비밀번호', 'password', 'passwd', '계좌', '통장', '급여', '연봉',
                            '주민등록', '신분증', '여권', '인감')
    MaxFileSizeMB       = 200
    FullScan            = $false
}

if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $json = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $json.PSObject.Properties) {
            if ($prop.Name -like '_*') { continue }      # "_설명" 같은 메모 항목은 무시
            $Config[$prop.Name] = $prop.Value
        }
        Write-Host "설정 파일을 읽었습니다: $ConfigPath"
    } catch {
        Write-Host "설정 파일을 읽지 못해 기본값을 사용합니다. ($($_.Exception.Message))" -ForegroundColor Yellow
    }
} else {
    Write-Host "설정 파일이 없어 기본값을 사용합니다: $ConfigPath" -ForegroundColor Yellow
}

if ($FullScan) { $Config.FullScan = $true }

# 배열이어야 하는 항목이 문자열 하나로 들어와도 동작하게 정리
foreach ($key in @('SourceFolders', 'ExtraFolders', 'Extensions', 'ExcludeDirNames', 'ExcludeNameKeywords')) {
    if ($null -eq $Config[$key]) { $Config[$key] = @() }
    $Config[$key] = @($Config[$key])
}
$Config.Extensions = @($Config.Extensions | ForEach-Object { $_.ToString().TrimStart('.').ToLower() })

# ---------------------------------------------------------------------------
# 2. 이름 확인과 시작 안내
# ---------------------------------------------------------------------------
$UserName = $Config.UserName
if (-not $UserName) {
    if ($NoPrompt) {
        $UserName = $env:USERNAME
    } else {
        $answer = Read-Host "이름을 입력하세요 (그냥 엔터를 누르면 '$($env:USERNAME)' 사용)"
        if ($answer) { $UserName = $answer.Trim() } else { $UserName = $env:USERNAME }
    }
}
# 폴더 이름으로 쓸 수 없는 문자는 _ 로 바꿈
$UserName = ($UserName -replace '[\\/:*?"<>|]', '_')

$Mode = if ($DryRun) { '미리보기 (복사하지 않음)' } else { '실제 수집 (복사함)' }
$DestRoot = Join-Path (Join-Path $Config.Destination $Config.Department) $UserName

Write-Host ''
Write-Host '=============================================================='
Write-Host '  사내 AI 비서용 문서 수집 도구'
Write-Host '=============================================================='
Write-Host "  실행 모드   : $Mode"
Write-Host "  PC 이름     : $env:COMPUTERNAME"
Write-Host "  부서 / 이름 : $($Config.Department) / $UserName"
Write-Host "  저장 위치   : $DestRoot"
if ($Config.FullScan) {
    Write-Host '  검색 범위   : PC의 모든 드라이브 (시간이 오래 걸립니다)'
} else {
    Write-Host "  검색 범위   : $($Config.SourceFolders -join ', ')"
    if ($Config.ExtraFolders.Count -gt 0) { Write-Host "                + $($Config.ExtraFolders -join ', ')" }
}
Write-Host "  문서 종류   : $($Config.Extensions -join ', ')"
Write-Host "  제외 단어   : $($Config.ExcludeNameKeywords -join ', ')"
Write-Host "  크기 제한   : $($Config.MaxFileSizeMB) MB 이하만"
Write-Host ''
Write-Host '  * 원본 파일은 지우거나 옮기지 않습니다. 복사만 합니다.'
Write-Host '  * 사진, 동영상, 프로그램 파일은 건드리지 않습니다.'
Write-Host ''

if (-not $NoPrompt) {
    $go = Read-Host '계속하려면 Y 를 입력하세요'
    if ($go -notmatch '^[Yy]') { Write-Host '취소했습니다.'; exit 0 }
}

# ---------------------------------------------------------------------------
# 3. NAS 연결 확인
# ---------------------------------------------------------------------------
$DestinationOk = Test-Path -LiteralPath $Config.Destination
if (-not $DestinationOk) {
    Write-Host ''
    Write-Host "NAS 폴더에 연결할 수 없습니다: $($Config.Destination)" -ForegroundColor Red
    Write-Host '  - 윈도우 탐색기 주소창에 위 주소를 붙여 넣고 NAS 계정으로 로그인한 뒤 다시 실행하세요.'
    Write-Host '  - 또는 collect_config.json 의 Destination 주소가 맞는지 팀장에게 확인하세요.'
    if (-not $DryRun) {
        if (-not $NoPrompt) { Read-Host '엔터를 누르면 창이 닫힙니다' | Out-Null }
        exit 1
    }
    Write-Host '  미리보기 모드이므로 NAS 없이 목록만 만듭니다.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 4. 검색할 폴더 목록 만들기
# ---------------------------------------------------------------------------
function Get-KnownFolderPath([string]$name) {
    switch ($name) {
        'Desktop'   { return [Environment]::GetFolderPath('Desktop') }
        'Documents' { return [Environment]::GetFolderPath('MyDocuments') }
        'Downloads' {
            $p = $null
            try {
                $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
                $p = (Get-ItemProperty -Path $key -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
            } catch { }
            if ($p) { return [Environment]::ExpandEnvironmentVariables($p) }
            return (Join-Path $env:USERPROFILE 'Downloads')
        }
        default     { return $name }   # 그 외는 실제 경로로 취급
    }
}

function Get-FolderLabel([string]$name, [string]$path) {
    switch ($name) {
        'Desktop'   { return '바탕화면' }
        'Documents' { return '문서' }
        'Downloads' { return '다운로드' }
        default     { return ($path -replace '[\\/:*?"<>|]', '_').Trim('_') }
    }
}

# 검색 대상: @{ Label = 'NAS에 만들 폴더 이름'; Path = 'PC의 실제 경로' }
$Roots = @()
if ($Config.FullScan) {
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue
    foreach ($d in $drives) {
        $Roots += @{ Label = ('드라이브_' + $d.DeviceID.TrimEnd(':')); Path = ($d.DeviceID + '\') }
    }
} else {
    foreach ($name in $Config.SourceFolders) {
        $p = Get-KnownFolderPath $name
        if ($p -and (Test-Path -LiteralPath $p)) {
            $Roots += @{ Label = (Get-FolderLabel $name $p); Path = $p }
        } else {
            Write-Host "폴더를 찾지 못해 건너뜁니다: $name ($p)" -ForegroundColor Yellow
        }
    }
    foreach ($extra in $Config.ExtraFolders) {
        $p = [Environment]::ExpandEnvironmentVariables($extra)
        if ($p -and (Test-Path -LiteralPath $p)) {
            $Roots += @{ Label = (Get-FolderLabel $p $p); Path = $p }
        } else {
            Write-Host "추가 폴더를 찾지 못해 건너뜁니다: $extra" -ForegroundColor Yellow
        }
    }
}

if ($Roots.Count -eq 0) {
    Write-Host '검색할 폴더가 하나도 없습니다. 설정을 확인하세요.' -ForegroundColor Red
    if (-not $NoPrompt) { Read-Host '엔터를 누르면 창이 닫힙니다' | Out-Null }
    exit 1
}

# ---------------------------------------------------------------------------
# 5. 기록 파일 준비
# ---------------------------------------------------------------------------
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$LocalLogDir = Join-Path $env:USERPROFILE 'AI비서수집로그'
New-Item -ItemType Directory -Path $LocalLogDir -Force | Out-Null
$LocalCsv = Join-Path $LocalLogDir ("수집목록_{0}_{1}.csv" -f $env:COMPUTERNAME, $Stamp)
$LocalSummary = Join-Path $LocalLogDir ("요약_{0}_{1}.txt" -f $env:COMPUTERNAME, $Stamp)
$NasCsv = Join-Path $DestRoot '_수집목록.csv'

# 이전에 복사한 파일의 내용 지문(해시)을 읽어 두어, 같은 내용이면 다시 복사하지 않음
$KnownHashes = @{}
if ($DestinationOk -and (Test-Path -LiteralPath $NasCsv)) {
    try {
        Import-Csv -LiteralPath $NasCsv -Encoding UTF8 | Where-Object { $_.상태 -eq '복사' -or $_.상태 -eq '이미있음' } |
            ForEach-Object { if ($_.내용지문) { $KnownHashes[$_.내용지문] = $_.원본경로 } }
        Write-Host "이전 수집 기록을 읽었습니다: $($KnownHashes.Count) 개"
    } catch {
        Write-Host '이전 수집 기록을 읽지 못했습니다. 처음부터 검사합니다.' -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# 6. 파일 찾기
# ---------------------------------------------------------------------------
$ExcludeDirSet = @{}
foreach ($n in $Config.ExcludeDirNames) { $ExcludeDirSet[$n.ToString().ToLower()] = $true }
$MaxBytes = [int64]$Config.MaxFileSizeMB * 1MB

function Test-InExcludedDir([string]$fullPath, [string]$rootPath) {
    # 검색 시작 폴더 아래의 폴더 이름 중 하나라도 제외 목록에 있으면 건너뜀
    $rel = $fullPath.Substring($rootPath.Length).TrimStart('\')
    $parts = $rel.Split('\')
    for ($i = 0; $i -lt $parts.Length - 1; $i++) {
        if ($ExcludeDirSet.ContainsKey($parts[$i].ToLower())) { return $true }
    }
    return $false
}

function Test-SensitiveName([string]$name) {
    foreach ($kw in $Config.ExcludeNameKeywords) {
        if ($name.IndexOf([string]$kw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $kw }
    }
    return $null
}

Write-Host ''
Write-Host '문서 파일을 찾는 중입니다. 잠시 기다려 주세요...'
$Candidates = New-Object System.Collections.ArrayList
foreach ($root in $Roots) {
    $rootPath = $root.Path.TrimEnd('\')
    if ($rootPath.Length -eq 2) { $rootPath = $rootPath + '\' }   # "C:" -> "C:\"
    Write-Host "  검색: $($root.Path)"
    $files = Get-ChildItem -LiteralPath $root.Path -Recurse -File -Force -ErrorAction SilentlyContinue
    foreach ($f in $files) {
        $ext = $f.Extension.TrimStart('.').ToLower()
        if ($Config.Extensions -notcontains $ext) { continue }
        if ($f.Name.StartsWith('~$')) { continue }                                # 오피스 임시 파일
        if ($f.Attributes -band [System.IO.FileAttributes]::System) { continue }   # 시스템 파일
        if ($f.Length -le 0) { continue }
        if (Test-InExcludedDir $f.FullName $rootPath) { continue }
        [void]$Candidates.Add(@{ File = $f; Root = $rootPath; Label = $root.Label })
    }
}
Write-Host "  후보 파일: $($Candidates.Count) 개"
Write-Host ''

# ---------------------------------------------------------------------------
# 7. 검사하고 복사하기
# ---------------------------------------------------------------------------
$Rows = New-Object System.Collections.ArrayList
$Count = @{ '복사' = 0; '이미있음' = 0; '중복' = 0; '제외' = 0; '너무큼' = 0; '오류' = 0 }
$CopiedBytes = [int64]0
$SeenHashes = @{}
$i = 0

foreach ($c in $Candidates) {
    $i++
    $f = $c.File
    if ($i % 20 -eq 0 -or $i -eq $Candidates.Count) {
        Write-Progress -Activity '문서 검사 및 복사' -Status "$i / $($Candidates.Count)  $($f.Name)" -PercentComplete ([int](100 * $i / $Candidates.Count))
    }

    $rel = $f.FullName.Substring($c.Root.Length).TrimStart('\')
    $dest = Join-Path (Join-Path $DestRoot $c.Label) $rel
    $status = ''
    $note = ''
    $hash = ''

    $kw = Test-SensitiveName $f.Name
    if ($kw) {
        $status = '제외'; $note = "파일명에 '$kw' 포함"
    } elseif ($f.Length -gt $MaxBytes) {
        $status = '너무큼'; $note = ('{0:N1} MB' -f ($f.Length / 1MB))
    } else {
        try {
            $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
        } catch {
            $status = '오류'; $note = "읽을 수 없음: $($_.Exception.Message)"
        }
        if (-not $status) {
            if ($SeenHashes.ContainsKey($hash)) {
                $status = '중복'; $note = "같은 내용: $($SeenHashes[$hash])"
            } elseif ($KnownHashes.ContainsKey($hash) -and -not (Test-Path -LiteralPath $dest)) {
                $status = '중복'; $note = "이전에 복사됨: $($KnownHashes[$hash])"
            } elseif ((Test-Path -LiteralPath $dest) -and
                      ((Get-Item -LiteralPath $dest).Length -eq $f.Length) -and
                      ([math]::Abs(((Get-Item -LiteralPath $dest).LastWriteTime - $f.LastWriteTime).TotalSeconds) -lt 2)) {
                $status = '이미있음'
            } elseif ($DryRun) {
                $status = '복사'; $note = '(미리보기: 실제로 복사하지 않음)'
            } else {
                try {
                    $destDir = Split-Path -Parent $dest
                    if (-not (Test-Path -LiteralPath $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop | Out-Null
                    }
                    Copy-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction Stop
                    $status = '복사'
                    $CopiedBytes += $f.Length
                } catch {
                    $status = '오류'; $note = "복사 실패: $($_.Exception.Message)"
                }
            }
            if ($status -eq '복사' -or $status -eq '이미있음') { $SeenHashes[$hash] = $f.FullName }
        }
    }

    $Count[$status]++
    [void]$Rows.Add([PSCustomObject]@{
        수집시각 = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        PC       = $env:COMPUTERNAME
        부서     = $Config.Department
        이름     = $UserName
        상태     = $status
        원본경로 = $f.FullName
        저장경로 = $(if ($status -eq '복사' -or $status -eq '이미있음') { $dest } else { '' })
        크기바이트 = $f.Length
        수정일시 = $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
        내용지문 = $hash
        비고     = $note
    })
}
Write-Progress -Activity '문서 검사 및 복사' -Completed

# ---------------------------------------------------------------------------
# 8. 기록 저장과 요약
# ---------------------------------------------------------------------------
$Rows | Export-Csv -LiteralPath $LocalCsv -NoTypeInformation -Encoding UTF8
if (-not $DryRun -and $DestinationOk) {
    try {
        New-Item -ItemType Directory -Path $DestRoot -Force | Out-Null
        if (Test-Path -LiteralPath $NasCsv) {
            $Rows | Where-Object { $_.상태 -ne '이미있음' } | Export-Csv -LiteralPath $NasCsv -NoTypeInformation -Encoding UTF8 -Append
        } else {
            $Rows | Export-Csv -LiteralPath $NasCsv -NoTypeInformation -Encoding UTF8
        }
    } catch {
        Write-Host "NAS에 목록을 저장하지 못했습니다: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

$CopiedMB = '{0:N1}' -f ($CopiedBytes / 1MB)
$ByExt = @($Rows | Where-Object { $_.상태 -eq '복사' } |
    Group-Object { [System.IO.Path]::GetExtension($_.원본경로).TrimStart('.').ToLower() } |
    Sort-Object Count -Descending | ForEach-Object { "    {0,-6} {1,6} 개" -f $_.Name, $_.Count })

$SummaryLines = @(
    '==============================================================',
    "  수집 결과  ($Mode)",
    '==============================================================',
    "  PC / 부서 / 이름 : $env:COMPUTERNAME / $($Config.Department) / $UserName",
    "  저장 위치        : $DestRoot",
    "  검사한 파일      : $($Candidates.Count) 개",
    "  복사             : $($Count.복사) 개  ($CopiedMB MB)",
    "  이미 있음(건너뜀): $($Count.이미있음) 개",
    "  중복(건너뜀)     : $($Count.중복) 개",
    "  제외(민감 단어)  : $($Count.제외) 개",
    "  너무 큼(건너뜀)  : $($Count.너무큼) 개",
    "  오류             : $($Count.오류) 개",
    '',
    '  복사한 문서 종류별:'
) + $ByExt + @(
    '',
    "  상세 목록(이 PC) : $LocalCsv",
    $(if (-not $DryRun -and $DestinationOk) { "  상세 목록(NAS)   : $NasCsv" } else { '' }),
    '=============================================================='
)
$SummaryLines | Set-Content -LiteralPath $LocalSummary -Encoding UTF8
Write-Host ''
$SummaryLines | ForEach-Object { Write-Host $_ }

if ($Count.오류 -gt 0) {
    Write-Host ''
    Write-Host '오류가 난 파일 (최대 10개):' -ForegroundColor Yellow
    $Rows | Where-Object { $_.상태 -eq '오류' } | Select-Object -First 10 | ForEach-Object { Write-Host "  $($_.원본경로)  -  $($_.비고)" }
}
if ($DryRun) {
    Write-Host ''
    Write-Host '미리보기였습니다. 목록이 괜찮으면 "2_수집실행.bat" 을 실행하세요.' -ForegroundColor Cyan
}

if (-not $NoPrompt) { Read-Host '엔터를 누르면 창이 닫힙니다' | Out-Null }
