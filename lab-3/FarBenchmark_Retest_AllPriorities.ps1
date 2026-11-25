[CmdletBinding()]
param(
    [ValidateSet(1,4,10)][int]$SizeGB = 1,
    [ValidateSet('Low','AboveNormal','High','Realtime')][string]$Priority = 'Low',
    [ValidateSet('OFF','ON')][string]$UseSystemCopy = 'OFF',
    [ValidateRange(1,20)][int]$Iterations = 4,
    [string]$TestPath = 'F:\Important\Study\ITMO\Semester_7\InfoSec\Lab-3\FarBenchMarkTest',
    [ValidateRange(10,3600)][int]$TimeoutSec = 600,
    [switch]$CheckOnly,
    [switch]$MakeSummary,
    [switch]$AllowRealtime
)

$ErrorActionPreference = 'Stop'
$sourceDir = Join-Path $TestPath 'Source'
$destDir   = Join-Path $TestPath 'Destination'
$fileName  = 'test_{0}GB.dat' -f $SizeGB
$source    = Join-Path $sourceDir $fileName
$dest      = Join-Path $destDir $fileName
$rawCsv    = Join-Path $TestPath 'FarBenchmark_Retest_Results.csv'
$summaryCsv = Join-Path $TestPath 'FarBenchmark_Retest_Summary.csv'
$expectedBytes = [int64]$SizeGB * [int64]1GB

function Write-RetestSummary {
    param([string]$RawFile, [string]$SummaryFile)
    if (-not (Test-Path -LiteralPath $RawFile -PathType Leaf)) {
        Write-Host 'No retest CSV exists yet.' -ForegroundColor Yellow
        return
    }
    $rows = @(Import-Csv -LiteralPath $RawFile -Encoding UTF8)
    $latest = @{}
    foreach ($group in ($rows | Group-Object -Property RunId)) {
        $measurements = @($group.Group | Sort-Object { [int]$_.Iteration })
        if ($measurements.Count -ne 4) { continue }
        if ((($measurements | ForEach-Object { $_.Iteration }) -join ',') -ne '1,2,3,4') { continue }
        $first = $measurements[0]
        $valid = $true
        foreach ($m in $measurements) {
            if ($m.FileSizeGB -ne $first.FileSizeGB -or
                $m.Priority -ne $first.Priority -or
                $m.UseSystemCopy -ne $first.UseSystemCopy) {
                $valid = $false
            }
        }
        if (-not $valid) { continue }
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        $t1 = [double]::Parse($measurements[0].CopyTimeSeconds, $culture)
        $t2 = [double]::Parse($measurements[1].CopyTimeSeconds, $culture)
        $t3 = [double]::Parse($measurements[2].CopyTimeSeconds, $culture)
        $t4 = [double]::Parse($measurements[3].CopyTimeSeconds, $culture)
        $mean = ($t2 + $t3 + $t4) / 3.0
        $obj = [PSCustomObject]@{
            FileSizeGB       = [int]$first.FileSizeGB
            Priority         = $first.Priority
            UseSystemCopy    = $first.UseSystemCopy
            T1_Seconds       = $t1.ToString('F4', $culture)
            T2_Seconds       = $t2.ToString('F4', $culture)
            T3_Seconds       = $t3.ToString('F4', $culture)
            T4_Seconds       = $t4.ToString('F4', $culture)
            Mean_T2_T4       = $mean.ToString('F4', $culture)
            RunId            = $first.RunId
            LastTimestamp    = $measurements[3].Timestamp
        }
        $key = ('{0}|{1}|{2}' -f $obj.FileSizeGB,$obj.Priority,$obj.UseSystemCopy)
        if ((-not $latest.ContainsKey($key)) -or ($obj.LastTimestamp -gt $latest[$key].LastTimestamp)) {
            $latest[$key] = $obj
        }
    }
    $summary = @($latest.Values | Sort-Object FileSizeGB, UseSystemCopy, Priority)
    if ($summary.Count -eq 0) {
        Write-Host 'No completed four-iteration sessions found; summary not updated.' -ForegroundColor Yellow
        return
    }
    $summary | Export-Csv -LiteralPath $SummaryFile -NoTypeInformation -Encoding UTF8
    Write-Host ('Summary updated: {0} complete configurations -> {1}' -f $summary.Count, $SummaryFile) -ForegroundColor Cyan
}

if ($MakeSummary) {
    Write-RetestSummary -RawFile $rawCsv -SummaryFile $summaryCsv
    return
}

if (-not (Test-Path -LiteralPath $sourceDir -PathType Container)) { throw "Source folder is missing: $sourceDir" }
if (-not (Test-Path -LiteralPath $destDir -PathType Container)) { throw "Destination folder is missing: $destDir" }
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Source file is missing: $source" }
$actualBytes = (Get-Item -LiteralPath $source).Length
if ($actualBytes -ne $expectedBytes) {
    throw ('Incorrect source size. Expected {0} bytes; found {1} bytes.' -f $expectedBytes,$actualBytes)
}
if ([System.IO.Path]::GetFullPath($source) -eq [System.IO.Path]::GetFullPath($dest)) {
    throw 'Source and Destination are the same file.'
}
if (Test-Path -LiteralPath $dest -PathType Container) {
    throw "Destination test file name points to a directory. Refusing to delete: $dest"
}

$farList = @(Get-Process -Name 'Far' -ErrorAction SilentlyContinue)
if ($farList.Count -ne 1) { throw "Exactly ONE Far.exe must be running. Found: $($farList.Count)." }
$far = $farList[0]
$priorityMap = @{
    Low         = [System.Diagnostics.ProcessPriorityClass]::Idle
    AboveNormal = [System.Diagnostics.ProcessPriorityClass]::AboveNormal
    High        = [System.Diagnostics.ProcessPriorityClass]::High
    Realtime    = [System.Diagnostics.ProcessPriorityClass]::RealTime
}

Write-Host "`n==== FAR BENCHMARK / FRESH RETEST ====" -ForegroundColor Cyan
Write-Host ('File:        {0} ({1} bytes)' -f $fileName, $expectedBytes)
Write-Host ('Priority:    {0}' -f $Priority)
Write-Host ('SystemCopy:  {0} (MUST be set MANUALLY in Far)' -f $UseSystemCopy)
Write-Host ('Iterations:  {0}' -f $Iterations)
Write-Host ('Far PID:     {0}' -f $far.Id)
Write-Host ('Source:      {0}' -f $source)
Write-Host ('Destination: {0}' -f $dest)
Write-Host ('Raw CSV:     {0}' -f $rawCsv)
Write-Host ('Summary CSV: {0}' -f $summaryCsv)

if ($CheckOnly) {
    Write-Host 'CHECK ONLY: paths, file size, and exactly one Far.exe are valid. No copying performed.' -ForegroundColor Green
    return
}
if ($Iterations -ne 4) {
    Write-Warning 'The assignment expects 4 iterations; summary CSV only includes completed 4-iteration runs.'
}
if ($Priority -eq 'Realtime') {
    if (-not $AllowRealtime) {
        throw 'REFUSED: Realtime is dangerous on a main PC. Run only in an isolated, recoverable VM, manually set Far.exe to Realtime first, then provide -AllowRealtime.'
    }
    $far.Refresh()
    if ($far.PriorityClass -ne $priorityMap['Realtime']) {
        throw 'Realtime must already be selected MANUALLY for Far.exe in Task Manager. Script will NOT set Realtime.'
    }
    Write-Warning 'REALTIME: use only in an isolated, recoverable VM. The script will attempt to restore NORMAL when finished.'
}

if (Test-Path -LiteralPath $rawCsv) {
    $header = Get-Content -LiteralPath $rawCsv -TotalCount 1
    if (($header -notmatch 'RunId') -or ($header -notmatch 'CopyTimeSeconds')) {
        throw "Existing retest CSV has unexpected columns. Rename it manually before continuing: $rawCsv"
    }
}

Write-Host "`nCHECK FAR BEFORE STARTING:" -ForegroundColor Yellow
Write-Host ('  LEFT panel:  {0}, cursor ON {1}' -f $sourceDir,$fileName)
Write-Host ('  RIGHT panel: {0}' -f $destDir)
Write-Host ('  System Copy is really {0}; no Copy dialog is open.' -f $UseSystemCopy)
Write-Host '  ONLY the named Destination test file may be deleted between iterations.' -ForegroundColor Yellow
Write-Host '  Keep Far focused; do not touch mouse or keyboard while measurements run.' -ForegroundColor Yellow
$answer = Read-Host 'Type YES to confirm these conditions and start (anything else cancels)'
if ($answer -cne 'YES') { Write-Host 'Cancelled. No files changed.'; return }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class FarRetestWindow {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hwnd, StringBuilder value, int maxCount);
    public static string ForegroundTitle() {
        StringBuilder title = new StringBuilder(512);
        GetWindowText(GetForegroundWindow(), title, title.Capacity);
        return title.ToString();
    }
}
'@
function Assert-FarForeground {
    $title = [FarRetestWindow]::ForegroundTitle()
    if ($title -notmatch '(?i)far') {
        throw "Wrong foreground window: '$title'. F5/Enter were NOT sent. Keep Far Manager focused."
    }
}
function Test-CopyCompleted {
    param([string]$Path, [int64]$Bytes)
    if (-not [System.IO.File]::Exists($Path)) { return $false }
    try {
        if ((Get-Item -LiteralPath $Path).Length -ne $Bytes) { return $false }
        $handle = [System.IO.File]::Open($Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None)
        $handle.Dispose()
        return $true
    } catch {
        return $false
    }
}

$runId = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8)
$completedTimes = New-Object 'System.Collections.Generic.List[double]'
$priorityModified = $false
try {
    if ($Priority -ne 'Realtime') {
        $far.PriorityClass = $priorityMap[$Priority]
        $priorityModified = $true
        $far.Refresh()
        if ($far.PriorityClass -ne $priorityMap[$Priority]) { throw "Cannot set Far.exe priority to $Priority." }
    }
    Write-Host 'Switch to FAR MANAGER now. Starting in 7 seconds...' -ForegroundColor Yellow
    Start-Sleep -Seconds 7

    for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
        Assert-FarForeground
        if (Test-Path -LiteralPath $dest) {
            Remove-Item -LiteralPath $dest -Force
            Start-Sleep -Milliseconds 300
        }
        if (Test-Path -LiteralPath $dest) { throw "Cannot clear prior Destination test file: $dest" }

        Assert-FarForeground
        [System.Windows.Forms.SendKeys]::SendWait('{F5}')
        Start-Sleep -Milliseconds 700
        Assert-FarForeground

        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        $complete = $false
        while ($watch.Elapsed.TotalSeconds -lt $TimeoutSec) {
            if (Test-CopyCompleted -Path $dest -Bytes $expectedBytes) {
                $complete = $true
                break
            }
            Start-Sleep -Milliseconds 50
        }
        $watch.Stop()
        if (-not $complete) {
            throw "Copy did not complete for $fileName before timeout ($TimeoutSec seconds). This iteration was NOT saved."
        }
        $seconds = [math]::Round($watch.Elapsed.TotalSeconds,4)
        $completedTimes.Add($seconds)
        $record = [PSCustomObject]@{
            RunId           = $runId
            FileSizeGB      = $SizeGB
            Priority        = $Priority
            UseSystemCopy   = $UseSystemCopy
            Iteration       = $iteration
            CopyTimeSeconds = $seconds.ToString('F4',[System.Globalization.CultureInfo]::InvariantCulture)
            Timestamp       = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            FarPID          = $far.Id
            SourceBytes     = $expectedBytes
        }
        $record | Export-Csv -LiteralPath $rawCsv -NoTypeInformation -Encoding UTF8 -Append
        Write-Host ('Iteration {0}/{1}: {2:N4} s' -f $iteration,$Iterations,$seconds) -ForegroundColor Green
        Start-Sleep -Milliseconds 500
    }
    Write-Host ('COMPLETE. RunId: {0}' -f $runId) -ForegroundColor Green
    if ($completedTimes.Count -eq 4) {
        $avg = ($completedTimes[1] + $completedTimes[2] + $completedTimes[3]) / 3
        Write-Host ('MAIN AVERAGE (iterations 2-4): {0:F4} seconds' -f $avg) -ForegroundColor Cyan
    }
    Write-RetestSummary -RawFile $rawCsv -SummaryFile $summaryCsv
} finally {
    try {
        $runningFar = Get-Process -Id $far.Id -ErrorAction Stop
        if ($Priority -eq 'Realtime' -or $priorityModified) {
            $runningFar.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
            Write-Host 'Far.exe priority restored to NORMAL.' -ForegroundColor Yellow
        }
    } catch {
        Write-Warning ('Could not restore Far priority automatically. Check Task Manager: {0}' -f $_.Exception.Message)
    }
}
