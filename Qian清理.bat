@echo off
rem ================================================================
rem  QianClean (Qian清理) - one-click memory/CPU/GPU and junk cleaner
rem  Version 1.0.0
rem
rem  Copyright (C) 2026 白小谦 (Bai Xiaoqian)
rem  Feedback: qianxlfk@163.com
rem
rem  This program is free software: you can redistribute it and/or
rem  modify it under the terms of the GNU Affero General Public
rem  License as published by the Free Software Foundation, either
rem  version 3 of the License, or (at your option) any later version.
rem
rem  This program is distributed in the hope that it will be useful,
rem  but WITHOUT ANY WARRANTY; without even the implied warranty of
rem  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
rem  GNU Affero General Public License for more details.
rem
rem  You should have received a copy of the license along with this
rem  program (see the LICENSE file). If not, see
rem  https://www.gnu.org/licenses/
rem
rem  SPDX-License-Identifier: AGPL-3.0-or-later
rem  Entry point: start.bat  -  keep 100%% ASCII here, CRLF required.
rem ================================================================
title Qian Clean
if "%QIAN_SKIP_UAC%"=="1" goto run
net session >nul 2>&1
if not errorlevel 1 goto run
echo.
echo  [!] Administrator rights are needed for full cleanup.
echo  [!] A UAC prompt will appear - please click "Yes".
echo.
powershell -NoProfile -Command "try { Start-Process -FilePath '%~f0' -Verb RunAs } catch { exit 1 }"
if not errorlevel 1 exit /b
echo  [X] UAC declined - continuing with limited rights (or close this window).
echo.
goto run
:run
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $i=$t.LastIndexOf('# ==== POWERSHELL BODY ===='); Invoke-Expression $t.Substring($i)"
echo.
pause
exit /b

# ==== POWERSHELL BODY ====
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference     = 'SilentlyContinue'
try { if([Console]::IsOutputRedirected){ [Console]::OutputEncoding=[Text.Encoding]::UTF8 } } catch {}
try { $Host.UI.RawUI.WindowTitle = 'Qian清理 · 360级全面清理' } catch {}

# QianClean v1.0.0 · AGPL-3.0 · 作者: 白小谦 · 反馈: qianxlfk@163.com

$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# 永不结束的系统关键进程名单 (安全保护)
$PROTECT = @(
  'system','idle','registry','memcompression','memory compression','smss','csrss','wininit','winlogon',
  'services','lsass','svchost','dwm','explorer','sihost','taskhostw','ctfmon','conhost','cmd','powershell','pwsh',
  'windowsterminal','openconsole','dllhost','fontdrvhost','searchindexer','spoolsv','audiodg','wudfhost',
  'dashost','runtimebroker','shellexperiencehost','startmenuexperiencehost','textinputhost',
  'applicationframehost','systemsettings','securityhealthservice','securityhealthsystray','msmpeng',
  'mssense','nissrv','wdnissvc','vmmem','vmmemwsl','vmmemdocker'
)

# ---------- 输出小工具 ----------
function W([string]$text,[string]$color='Gray'){ Write-Host $text -ForegroundColor $color }
function OK([string]$t){ Write-Host ('   [OK] '+$t) -ForegroundColor Green }
function SKIP([string]$t){ Write-Host ('   [--] '+$t) -ForegroundColor DarkGray }
function WARN([string]$t){ Write-Host ('   [!]  '+$t) -ForegroundColor Yellow }
function Step([string]$t){ Write-Host ''; Write-Host ('   >> '+$t) -ForegroundColor Cyan }
function Pause-Return { Write-Host ''; Write-Host '   按回车返回主菜单 ...' -ForegroundColor DarkGray; [void](Read-Host) }
function Short([string]$s,[int]$n){ if($s -and $s.Length -gt $n){ $s.Substring(0,$n)+'…' } else { $s } }
function Is-Protected([string]$n){ $PROTECT -contains $n.ToLower() }
function PadW([string]$s,[int]$w,[string]$align='l'){   # 中英文混排对齐 (中文按 2 列宽)
  $len=0; foreach($ch in $s.ToCharArray()){ if([int]$ch -ge 0x2E80){ $len+=2 } else { $len+=1 } }
  $pad=[math]::Max(0,$w-$len)
  if($align -eq 'r'){ (' '*$pad)+$s } else { $s+(' '*$pad) }
}

# ---------- 快速计量 (全部走低开销路径) ----------
function Get-AvailMB  { [int][math]::Round((Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory).FreePhysicalMemory/1KB) }
function Get-FreeCMB  { [int][math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -Property FreeSpace).FreeSpace/1MB) }
function Get-FreeAllMB{ [int][math]::Round(((Get-CimInstance Win32_LogicalDisk -Property FreeSpace,DriveType | Where-Object { $_.DriveType -eq 3 }) | Measure-Object FreeSpace -Sum).Sum/1MB) }
function Get-EvtMB    { [math]::Round(((Get-ChildItem "$env:SystemRoot\System32\winevt\Logs" -File -Force | Measure-Object Length -Sum).Sum)/1MB,1) }
function Get-WSumMB   { [int][math]::Round(((Get-Process | Measure-Object WorkingSet64 -Sum).Sum)/1MB) }
function Get-CpuLoad {                                   # 250ms 采样, 不依赖 WMI 慢查询
  $c=[Environment]::ProcessorCount
  $s=@{}; foreach($p in (Get-Process)){ if($p.TotalProcessorTime){ $s[$p.Id]=$p.TotalProcessorTime.TotalMilliseconds } }
  $w=Get-Date; Start-Sleep -Milliseconds 250
  $ms=((Get-Date)-$w).TotalMilliseconds; if($ms -le 0){ return 0 }
  $used=0.0
  foreach($p in (Get-Process)){ if($s.ContainsKey($p.Id) -and $p.TotalProcessorTime){ $used+=$p.TotalProcessorTime.TotalMilliseconds-$s[$p.Id] } }
  $v=[int][math]::Round($used/$ms/$c*100)
  if($v -lt 0){ $v=0 }; if($v -gt 100){ $v=100 }
  $v
}
function Get-GpuNames {                                  # 注册表瞬间读取
  $out=@()
  try{
    $base='HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach($k in (Get-ChildItem $base | Where-Object { $_.PSChildName -match '^\d{4}$' })){
      $d=(Get-ItemProperty $k.PSPath).DriverDesc
      if($d -and $d -notmatch 'Null'){ $out+=$d }
    }
  }catch{}
  if($out.Count){ ($out | Select-Object -Unique) -join ' + ' } else { $null }
}
function Get-SmiPath {
  foreach($c in @("$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe","$env:SystemRoot\System32\nvidia-smi.exe")){
    if(Test-Path $c){ return $c } }
  $g = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
  if($g){ $g.Source } else { $null }
}

# ---------- 引擎按需装载 (首次使用才编译, 启动零等待) ----------
$EngineOk=$false
function Init-Engine {
  if($EngineOk){ return }
  Write-Host '   装载清理引擎 (约 2~3 秒, 仅首次) ... ' -NoNewline -ForegroundColor DarkCyan
  try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class W32Mem {
  [DllImport("psapi.dll", SetLastError=true)] public static extern int EmptyWorkingSet(IntPtr hProcess);
  [DllImport("ntdll.dll")] public static extern int NtSetSystemInformation(int InfoClass, ref int Info, int Length);
  [DllImport("advapi32.dll", SetLastError=true)] public static extern bool OpenProcessToken(IntPtr h, uint access, out IntPtr tok);
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern bool LookupPrivilegeValue(string sys, string name, out long luid);
  [DllImport("advapi32.dll", SetLastError=true)] public static extern bool AdjustTokenPrivileges(IntPtr tok, bool disableAll, ref TOKPRIV newst, int len, IntPtr prev, IntPtr ret);
  [StructLayout(LayoutKind.Sequential)] public struct TOKPRIV { public int Count; public long Luid; public int Attr; }
  public static int Command(int cmd) {
    IntPtr tok = IntPtr.Zero;
    OpenProcessToken(System.Diagnostics.Process.GetCurrentProcess().Handle, 0x28, out tok);
    TOKPRIV tp = new TOKPRIV(); tp.Count = 1; tp.Attr = 2;
    long luid = 0;
    LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out luid);
    tp.Luid = luid;
    AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    return NtSetSystemInformation(0x50, ref cmd, 4);
  }
}
'@
    $script:EngineOk=$true; Write-Host '完成' -ForegroundColor Green
  } catch { $script:EngineOk=$false; Write-Host '不可用 (功能受限)' -ForegroundColor Red }
}

# ---------- 静态信息缓存 ----------
$OSc     = Get-CimInstance Win32_OperatingSystem -Property Caption,LastBootUpTime,TotalVisibleMemorySize
$TotalGB = [math]::Round($OSc.TotalVisibleMemorySize/1MB,1)
$Cores   = [Environment]::ProcessorCount
$GpuNames= Get-GpuNames

# ---------- 实时内存变化提示 ----------
function Show-Delta([int]$a0){
  $a=Get-AvailMB; $d=$a-$a0
  $sign=''; if($d -ge 0){ $sign='+' }
  W ("       · 实时可用内存 {0:N0} MB  ({1}{2:N0} MB)" -f $a,$sign,$d) DarkCyan
}

# ---------- 卡死进程检测 / 结束 ----------
function Get-Hung([switch]$All){
  $now=Get-Date
  Get-Process | Where-Object {
    $_.MainWindowTitle -and (-not $_.Responding) -and (-not (Is-Protected $_.Name)) -and
    ( $All -or (( $now - $_.StartTime ).TotalSeconds -gt 60) )
  } | Sort-Object WorkingSet64 -Descending
}

function End-Proc($p,[string]$note=''){
  if(Is-Protected $p.Name){ WARN ('已跳过受保护系统进程 {0} (PID {1})' -f $p.Name,$p.Id); return -1 }
  $freed=[math]::Round($p.WorkingSet64/1MB)
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 120
  if(Get-Process -Id $p.Id -ErrorAction SilentlyContinue){
    WARN ('未能结束 {0} (PID {1}) - 可能权限不足' -f $p.Name,$p.Id); return -1
  }
  OK ('已结束 {0}  (PID {1}, 释放约 {2} MB) {3}' -f $p.Name,$p.Id,$freed,$note)
  return $freed
}

function Kill-Pids([string]$ans){
  $ids=@($ans -split '\s+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ })
  if(-not $ids -or $ids.Count -eq 0){ SKIP '未输入有效 PID'; return }
  $targets=@(Get-Process | Where-Object { $ids -contains $_.Id })
  if($targets.Count -eq 0){ SKIP '未找到对应进程'; return }
  Step '将结束以下进程:'
  foreach($p in $targets){ Write-Host ('       {0}  (PID {1})  {2} MB' -f $p.Name,$p.Id,[math]::Round($p.WorkingSet64/1MB)) -ForegroundColor Yellow }
  $c=Read-Host '   确认结束? (Y/N)'
  if($c -notmatch '^[Yy]'){ SKIP '已取消'; return }
  $ok=0; $freed=0
  foreach($p in $targets){ $r=End-Proc $p; if($r -ge 0){ $ok++; $freed+=$r } }
  OK ('完成: {0}/{1} 个进程已结束' -f $ok,$targets.Count)
  if($ok -gt 0){ OK ('本项释放内存: 约 {0:N0} MB' -f $freed) } else { SKIP '本项释放: 0 MB (无进程被结束)' }
}

# ==================================================================
#  360 级垃圾扫描 / 清理机制  (19 类无用数据)
# ==================================================================
$JunkDefs = @(
  @{ cat='临时文件·用户';     type='files'; age=2; paths=@($env:TEMP) }
  @{ cat='临时文件·系统';     type='files'; age=2; paths=@("$env:SystemRoot\Temp") }
  @{ cat='Windows更新缓存';   type='wu' }
  @{ cat='传递优化缓存';      type='do' }
  @{ cat='系统日志·CBS';      type='files'; age=0; paths=@("$env:SystemRoot\Logs\CBS") }
  @{ cat='系统日志·DISM';     type='files'; age=0; paths=@("$env:SystemRoot\Logs\DISM") }
  @{ cat='系统日志·MoSetup';  type='files'; age=0; paths=@("$env:SystemRoot\Logs\MoSetup") }
  @{ cat='系统日志·服务';     type='files'; age=0; paths=@("$env:SystemRoot\System32\LogFiles") }
  @{ cat='崩溃转储·内核';     type='files'; age=0; paths=@("$env:SystemRoot\Minidump","$env:SystemRoot\MEMORY.DMP","$env:SystemRoot\LiveKernelReports") }
  @{ cat='崩溃转储·程序';     type='files'; age=0; paths=@("$env:LOCALAPPDATA\CrashDumps") }
  @{ cat='错误报告·系统';     type='files'; age=0; paths=@('C:\ProgramData\Microsoft\Windows\WER\ReportArchive','C:\ProgramData\Microsoft\Windows\WER\ReportQueue') }
  @{ cat='错误报告·用户';     type='files'; age=0; paths=@("$env:LOCALAPPDATA\Microsoft\Windows\WER") }
  @{ cat='显卡缓存·DirectX';  type='files'; age=0; paths=@("$env:LOCALAPPDATA\D3DSCache") }
  @{ cat='显卡缓存·NVIDIA';   type='files'; age=0; paths=@("$env:LOCALAPPDATA\NVIDIA\DXCache","$env:LOCALAPPDATA\NVIDIA\GLCache") }
  @{ cat='显卡缓存·AMD';      type='files'; age=0; paths=@("$env:LOCALAPPDATA\AMD\DxCache","$env:LOCALAPPDATA\AMD\GLCache") }
  @{ cat='缩略图/图标缓存';   type='files'; age=0; paths=@("$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db","$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache_*.db") }
  @{ cat='网页缓存·系统';     type='files'; age=0; paths=@("$env:LOCALAPPDATA\Microsoft\Windows\INetCache") }
  @{ cat='浏览器缓存·Edge';   type='files'; age=0; paths=@("$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache\Cache_Data","$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Code Cache") }
  @{ cat='浏览器缓存·Chrome'; type='files'; age=0; paths=@("$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache\Cache_Data","$env:LOCALAPPDATA\Google\Chrome\User Data\*\Code Cache") }
)

function Scan-Junk {
  $rows=@(); $i=0
  foreach($d in $JunkDefs){
    $i++
    Write-Host ("`r       扫描进度 {0}/{1} [{2}]                              " -f $i,$JunkDefs.Count,$d.cat) -NoNewline -ForegroundColor DarkCyan
    $files=@(); $mb=0.0
    if($d.type -eq 'files'){
      foreach($p in $d.paths){ $files+=@(Get-ChildItem $p -Recurse -File -Force -ErrorAction SilentlyContinue) }
      if($d.age -gt 0){ $cut=(Get-Date).AddHours(-$d.age); $files=@($files | Where-Object { $_.LastWriteTime -lt $cut }) }
      $mb=[math]::Round(($files | Measure-Object Length -Sum).Sum/1MB,1)
    } elseif($d.type -eq 'wu'){
      $files=@(Get-ChildItem "$env:SystemRoot\SoftwareDistribution\Download" -Recurse -File -Force -ErrorAction SilentlyContinue)
      $mb=[math]::Round(($files | Measure-Object Length -Sum).Sum/1MB,1)
    }
    $rows+=[pscustomobject]@{ cat=$d.cat; type=$d.type; mb=$mb; count=$files.Count; files=$files }
  }
  Write-Host ("`r" + (' '*62)) -NoNewline; Write-Host "`r" -NoNewline
  return $rows
}

function Show-ScanTable([object[]]$rows){
  $sumMB=0.0; $sumCnt=0; $cleanCnt=0
  W ''
  W ('  '+'┈'*56) DarkGray
  W ('   '+(PadW '垃圾类别' 22)+(PadW '大小' 12 'r')+(PadW '文件数' 12 'r')) White
  foreach($r in $rows){
    if($r.type -eq 'do'){ W ('   '+(PadW $r.cat 22)+(PadW '系统托管' 12 'r')+(PadW '-' 12 'r')) Gray; continue }
    if($r.count -gt 0){
      $sizeStr= if($r.mb -ge 1024){ '{0:N2} GB' -f ($r.mb/1024) } else { '{0:N1} MB' -f $r.mb }
      W ('   '+(PadW $r.cat 22)+(PadW $sizeStr 12 'r')+(PadW ('{0:N0}' -f $r.count) 12 'r')) Gray
      $sumMB+=$r.mb; $sumCnt+=$r.count
    } else { $cleanCnt++ }
  }
  W ('  '+'┈'*56) DarkGray
  if($cleanCnt -gt 0){ W ('   '+(PadW ('其余 '+$cleanCnt+' 类') 22)+(PadW '干净' 12 'r')) DarkGray }
  if($sumMB -gt 0){
    $tot= if($sumMB -ge 1024){ '{0:N2} GB' -f ($sumMB/1024) } else { '{0:N1} MB' -f $sumMB }
    W ('   合计发现垃圾: {0}   ({1:N0} 个文件)' -f $tot,$sumCnt) Yellow
  } else { W '   未发现垃圾, 系统很干净' Green }
}

function Clean-WU {
  $dir="$env:SystemRoot\SoftwareDistribution\Download"
  if(-not (Test-Path $dir)){ SKIP 'WU 更新缓存 : 路径不存在'; return 0 }
  if(-not $IsAdmin){ WARN 'WU 更新缓存 : 需要管理员权限, 已跳过'; return 0 }
  $files=@(Get-ChildItem $dir -Recurse -File -Force -ErrorAction SilentlyContinue)
  if($files.Count -eq 0){ SKIP 'WU 更新缓存 : 无可清理文件'; return 0 }
  $mb=[math]::Round(($files | Measure-Object Length -Sum).Sum/1MB,1)
  $s1=((Get-Service wuauserv).Status -eq 'Running')
  $s2=((Get-Service bits).Status -eq 'Running')
  WARN ('暂停 Windows 更新服务以解锁文件 ... (共 {0} 个文件)' -f $files.Count)
  try{ Stop-Service wuauserv -Force -ErrorAction Stop }catch{}
  try{ Stop-Service bits -Force -ErrorAction Stop }catch{}
  Start-Sleep -Milliseconds 800
  $tot=$files.Count; $i=0; $showed=$false
  foreach($f in $files){
    Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    $i++
    if(($i % 300) -eq 0){ Write-Host ("`r       实时进度 {0}/{1} ..." -f $i,$tot) -NoNewline -ForegroundColor DarkCyan; $showed=$true }
  }
  if($showed){ Write-Host ("`r       完成 {0}/{1} 个文件          " -f $i,$tot) -ForegroundColor DarkCyan }
  Get-ChildItem $dir -Directory -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  if($s1){ Start-Service wuauserv -ErrorAction SilentlyContinue }
  if($s2){ Start-Service bits -ErrorAction SilentlyContinue }
  OK ('Windows更新缓存 : {0:N1} MB (更新服务已恢复)' -f $mb)
  return $mb
}

function Clean-ScanRows([object[]]$rows){
  $freed=0.0
  foreach($r in $rows){
    if($r.type -eq 'do'){
      if(Get-Command Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue){
        if($IsAdmin){ Delete-DeliveryOptimizationCache -Force -ErrorAction SilentlyContinue; OK '传递优化缓存 : 已清空 (系统托管)' }
        else { WARN '传递优化缓存 : 需要管理员权限, 跳过' }
      }
      continue
    }
    if($r.type -eq 'wu'){ if($r.count -gt 0){ $freed+=(Clean-WU) }; continue }
    if($r.count -eq 0){ continue }
    $i=0; $showed=$false
    foreach($f in $r.files){
      Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
      $i++
      if(($i % 200) -eq 0){ Write-Host ("`r       {0} 实时进度 {1}/{2} ..." -f $r.cat,$i,$r.count) -NoNewline -ForegroundColor DarkCyan; $showed=$true }
    }
    if($showed){ Write-Host ("`r       {0} 完成 {1}/{2}                " -f $r.cat,$i,$r.count) -ForegroundColor DarkCyan }
    OK ('{0} : {1:N1} MB ({2} 个文件)' -f $r.cat,$r.mb,$r.count)
    $freed+=$r.mb
  }
  return $freed
}

# ---------- [1] 一键全面清理 (360 级: 内存 + 19 类垃圾) ----------
function Invoke-FullClean {
  $t0=Get-Date
  $a0=Get-AvailMB; $w0=Get-WSumMB; $c0=Get-CpuLoad; $f0=Get-FreeCMB
  $smiPath=Get-SmiPath; $g0=$null
  if($smiPath){ $g0=(& $smiPath --query-gpu=memory.used --format=csv,noheader,nounits | ForEach-Object { [int]$_ } | Measure-Object -Sum).Sum }

  $killed=0; $killFreed=0
  W ''; W ('  '+'▓'*58) Cyan
  W '   Qian清理 · 一键全面清理 (360级 · 内存 + 磁盘 + 显存)' White
  W ('  '+'▓'*58) Cyan
  Init-Engine

  W ''
  W ('   █ 阶段 1/3 · 内存释放') Cyan
  $hung=@(Get-Hung)
  if($hung.Count -gt 0){
    foreach($p in $hung){
      $note='['+[math]::Round($p.WorkingSet64/1MB)+' MB] '+(Short $p.MainWindowTitle 30)
      $r=End-Proc $p $note
      if($r -ge 0){ $killed++; $killFreed+=$r }
    }
  } else { SKIP '当前没有无响应进程' }
  if($EngineOk){
    $procs=@(Get-Process); $total=$procs.Count; $n=0; $ts=Get-Date
    foreach($p in $procs){
      try{ $h=$p.Handle; if($h){ [void][W32Mem]::EmptyWorkingSet($h); $n++ } }catch{}
      if(($n % 60) -eq 0 -and $n -gt 0){ Write-Host ("`r       修剪工作集 {0}/{1} ..." -f $n,$total) -NoNewline -ForegroundColor DarkCyan }
    }
    Write-Host ("`r       工作集修剪完成: {0}/{1} 个进程 ({2} ms)      " -f $n,$total,[int]((Get-Date)-$ts).TotalMilliseconds) -ForegroundColor DarkCyan
  } else { WARN 'Trim 引擎不可用' }
  if($EngineOk -and $IsAdmin){
    $r=999; try{ $r=[W32Mem]::Command(1) }catch{}
    if($r -eq 0){ OK '全系统工作集已清空' } else { WARN ('系统工作集命令未成功 (0x{0:X8})' -f $r) }
    $r=999; try{ $r=[W32Mem]::Command(3) }catch{}
    if($r -eq 0){ OK '待机列表已清空' } else { WARN ('待机列表命令未成功 (0x{0:X8})' -f $r) }
  } else { WARN '系统级整理: 需要管理员权限, 已跳过' }
  Clear-DnsClientCache; Set-Clipboard -Value ''
  Show-Delta $a0

  W ''
  W ('   █ 阶段 2/3 · 垃圾扫描 ({0} 类无用数据)' -f $JunkDefs.Count) Cyan
  $rows=Scan-Junk
  Show-ScanTable $rows

  W ''
  W ('   █ 阶段 3/3 · 垃圾清理') Cyan
  $diskFreed=Clean-ScanRows $rows

  $a1=Get-AvailMB; $w1=Get-WSumMB; $c1=Get-CpuLoad; $f1=Get-FreeCMB
  $dA=$a1-$a0; $dW=$w0-$w1; $dF=$f1-$f0
  $sec=[int]((Get-Date)-$t0).TotalSeconds

  W ''
  W ('  '+'═'*23+' 总 报 告 '+'═'*24) Cyan
  W ('   内存可用  : {0:N0} → {1:N0} MB' -f $a0,$a1)
  if($dA -ge 0){ W ('   内存净释放: {0:N0} MB  (工作集移出 {1:N0} MB)' -f $dA,$dW) Green }
  else { W ('   内存变化  : {0:N0} MB (系统缓存正常波动) · 工作集移出 {1:N0} MB' -f $dA,$dW) Yellow }
  W ('   结束卡死  : {0} 个进程 (释放约 {1} MB)' -f $killed,$killFreed)
  W ('   磁盘清理  : {0:N1} MB · C 盘可用 {1:N0} → {2:N0} MB (实际释放 {3:N0} MB)' -f $diskFreed,$f0,$f1,$dF) Green
  W ('   CPU 负载  : {0}% → {1}%' -f $c0,$c1)
  if($smiPath -and $null -ne $g0){
    $g1=(& $smiPath --query-gpu=memory.used --format=csv,noheader,nounits | ForEach-Object { [int]$_ } | Measure-Object -Sum).Sum
    if($null -ne $g1){
      W ('   显存(N卡) : {0} → {1} MiB' -f $g0,$g1)
      $dg=$g0-$g1; if($dg -gt 0){ W ('   显存释放  : {0} MiB' -f $dg) Green }
    }
  }
  W ('   耗时 {0} 秒 · 清理后首次启动程序略慢属正常 (缓存重建)' -f $sec) DarkGray
  W ('  '+'═'*58) Cyan
}

# ---------- [2] 内存急救 ----------
function Invoke-MemClean {
  $t0=Get-Date
  $a0=Get-AvailMB;  $w0=Get-WSumMB;  $c0=Get-CpuLoad
  $smiPath=Get-SmiPath; $g0=$null
  if($smiPath){ $g0=(& $smiPath --query-gpu=memory.used --format=csv,noheader,nounits | ForEach-Object { [int]$_ } | Measure-Object -Sum).Sum }

  $killed=0; $killFreed=0
  W ''; W ('  '+'▓'*58) Cyan
  W '   Qian清理 · 内存急救 (纯内存释放, 不动磁盘)' White
  W ('  '+'▓'*58) Cyan
  Init-Engine

  Step '1/5  检测并结束卡死 (无响应) 进程'
  $hung=@(Get-Hung)
  if($hung.Count -gt 0){
    foreach($p in $hung){
      $note='['+[math]::Round($p.WorkingSet64/1MB)+' MB] '+(Short $p.MainWindowTitle 30)
      $r=End-Proc $p $note
      if($r -ge 0){ $killed++; $killFreed+=$r }
    }
  } else { SKIP '当前没有无响应进程' }
  Show-Delta $a0

  Step '2/5  修剪全部进程工作集 (Working Set)'
  if($EngineOk){
    $procs=@(Get-Process); $total=$procs.Count; $n=0; $ts=Get-Date
    foreach($p in $procs){
      try{ $h=$p.Handle; if($h){ [void][W32Mem]::EmptyWorkingSet($h); $n++ } }catch{}
      if(($n % 60) -eq 0 -and $n -gt 0){ Write-Host ("`r       实时进度 {0}/{1} ..." -f $n,$total) -NoNewline -ForegroundColor DarkCyan }
    }
    Write-Host ("`r       完成: 已修剪 {0}/{1} 个进程  ({2} ms)      " -f $n,$total,[int]((Get-Date)-$ts).TotalMilliseconds) -ForegroundColor DarkCyan
  } else { WARN 'Trim 引擎不可用, 已跳过' }
  Show-Delta $a0

  Step '3/5  系统级内存整理 (全系统工作集 + 待机列表 Standby)'
  if($EngineOk -and $IsAdmin){
    $r=999; try{ $r=[W32Mem]::Command(1) }catch{}
    if($r -eq 0){ OK '全系统工作集已清空' } else { WARN ('系统工作集命令未成功 (0x{0:X8})' -f $r) }
    $r=999; try{ $r=[W32Mem]::Command(3) }catch{}
    if($r -eq 0){ OK '待机列表已清空 (缓存冷数据释放为可用内存)' } else { WARN ('待机列表命令未成功 (0x{0:X8})' -f $r) }
  } else { WARN '需要管理员权限或引擎不可用, 已跳过' }
  Show-Delta $a0

  Step '4/5  清空 DNS 缓存 / 剪贴板'
  Clear-DnsClientCache
  Set-Clipboard -Value ''
  OK 'DNS 缓存已刷新, 剪贴板已清空'

  Step '5/5  内存回收结算'
  foreach($i in 3..1){ Write-Host ("`r       结算中, 剩余 {0} 秒 ..." -f $i) -NoNewline -ForegroundColor DarkCyan; Start-Sleep -Seconds 1 }
  Write-Host "`r       结算完成                        " -ForegroundColor DarkCyan

  $a1=Get-AvailMB; $w1=Get-WSumMB; $c1=Get-CpuLoad
  $dA=$a1-$a0; $dW=$w0-$w1
  $sec=[int]((Get-Date)-$t0).TotalSeconds

  W ''
  W ('  '+'═'*23+' 清 理 报 告 '+'═'*23) Cyan
  W ('   可用内存      : {0:N0} MB  →  {1:N0} MB' -f $a0,$a1)
  if($dA -ge 0){ W ('   本次净释放    : {0:N0} MB' -f $dA) Green }
  else { W ('   本次净变化    : {0:N0} MB (系统缓存策略正常波动, 非异常)' -f $dA) Yellow }
  W ('   进程工作集合计: {0:N0} MB  →  {1:N0} MB' -f $w0,$w1)
  if($dW -gt 0){ W ('   已从工作集移出: {0:N0} MB' -f $dW) }
  W ('   CPU 负载      : {0}%  →  {1}%' -f $c0,$c1)
  if($smiPath -and $null -ne $g0){
    $g1=(& $smiPath --query-gpu=memory.used --format=csv,noheader,nounits | ForEach-Object { [int]$_ } | Measure-Object -Sum).Sum
    if($null -ne $g1){
      W ('   显存占用(N卡) : {0} MiB → {1} MiB' -f $g0,$g1)
      $dg=$g0-$g1; if($dg -gt 0){ W ('   显存释放      : {0} MiB' -f $dg) Green }
    }
  }
  W ('   结束无响应进程: {0} 个  (释放约 {1} MB)' -f $killed,$killFreed)
  W ('   耗时 {0} 秒 · 清理后首次切换程序可能略慢, 属正常现象' -f $sec) DarkGray
  W ('  '+'═'*58) Cyan
}

# ---------- [3] 垃圾扫描预览 ----------
function Invoke-ScanPreview {
  Step ('垃圾扫描预览 (只扫描 {0} 类, 不删除任何文件)' -f $JunkDefs.Count)
  $rows=Scan-Junk
  Show-ScanTable $rows
  $sum=($rows | Where-Object { $_.type -ne 'do' } | Measure-Object mb -Sum).Sum
  if($sum -gt 0){
    $c=Read-Host '   立即清理以上垃圾? (Y/N)'
    if($c -match '^[Yy]'){
      $f0=Get-FreeCMB
      $freed=Clean-ScanRows $rows
      $f1=Get-FreeCMB
      W ('  '+'═'*23+' 清 理 报 告 '+'═'*23) Cyan
      OK ('文件清理合计: {0:N1} MB' -f $freed)
      OK ('C 盘空间释放: {0:N0} MB  (可用 {1:N0} → {2:N0} MB)' -f ($f1-$f0),$f0,$f1)
    } else { SKIP '未清理 (本次释放 0 MB)' }
  }
}

# ---------- [4] 深度可选工具 ----------
function Clear-EventLogs {
  if(-not $IsAdmin){ WARN '需要管理员权限'; return }
  WARN '将清空全部 Windows 事件日志 (系统诊断历史, 约 1500+ 条, 需 1~2 分钟)'
  WARN '清除后系统出问题时将无法回溯历史记录'
  $c=Read-Host '   确认清空? (Y/N)'
  if($c -notmatch '^[Yy]'){ SKIP '已取消'; return }
  $sz0=Get-EvtMB
  $logs=@(& wevtutil el)
  $n=0; $fail=0; $tot=$logs.Count
  foreach($l in $logs){
    & wevtutil cl $l 2>$null
    if($LASTEXITCODE -eq 0){ $n++ } else { $fail++ }
    $done=$n+$fail
    if(($done % 40) -eq 0){ Write-Host ("`r       实时进度 {0}/{1} (受保护跳过 {2}) ..." -f $done,$tot,$fail) -NoNewline -ForegroundColor DarkCyan }
  }
  Write-Host ("`r       完成: 共处理 {0} 条日志                                " -f $tot) -ForegroundColor DarkCyan
  $freed=[math]::Round($sz0-(Get-EvtMB),1)
  if($freed -gt 0){ OK ('事件日志已清空 {0} 条 (跳过 {1} 条), 日志文件释放 {2} MB' -f $n,$fail,$freed) }
  else { OK ('事件日志已清空 {0} 条 (跳过 {1} 条), 磁盘释放 0 MB' -f $n,$fail) }
}

function Invoke-DismClean {
  if(-not $IsAdmin){ WARN '需要管理员权限'; return }
  WARN 'DISM 组件存储清理: 安全, 但可能需要几分钟, 请耐心等待'
  WARN '可释放 WinSxS 组件备份占用的空间 (数 GB 级)'
  $c=Read-Host '   确认执行? (Y/N)'
  if($c -notmatch '^[Yy]'){ SKIP '已取消'; return }
  $f0=Get-FreeCMB
  $p=Start-Process dism.exe -ArgumentList '/Online','/Cleanup-Image','/StartComponentCleanup' -NoNewWindow -PassThru -Wait
  $f1=Get-FreeCMB; $dF=$f1-$f0
  if($p.ExitCode -eq 0){ OK ('组件存储清理完成, C 盘释放 {0:N0} MB' -f $dF) }
  else { WARN ('DISM 返回码 {0}, C 盘释放 {1:N0} MB' -f $p.ExitCode,$dF) }
}

function Clean-Prefetch {
  if(-not $IsAdmin){ WARN '需要管理员权限'; return }
  WARN 'Prefetch 是程序预取缓存, 清理后各软件首次启动会略慢'
  $c=Read-Host '   确认清理? (Y/N)'
  if($c -notmatch '^[Yy]'){ SKIP '已取消'; return }
  $files=@(Get-ChildItem "$env:SystemRoot\Prefetch\*.pf" -Force -ErrorAction SilentlyContinue)
  $mb=[math]::Round(($files | Measure-Object Length -Sum).Sum/1MB,1)
  foreach($f in $files){ Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
  OK ('Prefetch : {0:N1} MB ({1} 个文件)' -f $mb,$files.Count)
}

function Clean-DevCaches {
  $defs=@(
    @{ n='npm';    p="$env:LOCALAPPDATA\npm-cache" },
    @{ n='pip';    p="$env:LOCALAPPDATA\pip\cache" },
    @{ n='uv';     p="$env:LOCALAPPDATA\uv\cache" },
    @{ n='Yarn';   p="$env:LOCALAPPDATA\Yarn\Cache" },
    @{ n='NuGet';  p="$env:LOCALAPPDATA\NuGet\v3-cache" },
    @{ n='Gradle'; p="$env:USERPROFILE\.gradle\caches" },
    @{ n='pnpm';   p="$env:LOCALAPPDATA\pnpm\store" }
  )
  $rows=@()
  foreach($d in $defs){
    if(Test-Path $d.p){
      $files=@(Get-ChildItem $d.p -Recurse -File -Force -ErrorAction SilentlyContinue)
      if($files.Count){
        $rows+=[pscustomobject]@{ n=$d.n; mb=[math]::Round(($files | Measure-Object Length -Sum).Sum/1MB,1); cnt=$files.Count; files=$files }
      }
    }
  }
  if($rows.Count -eq 0){ SKIP '未发现开发者缓存'; return }
  Step '发现以下开发者缓存 (清理后首次构建需重新下载)'
  foreach($r in $rows){ Write-Host ('   '+(PadW $r.n 12)+(PadW ('{0:N1} MB' -f $r.mb) 14 'r')+('{0:N0} 个文件' -f $r.cnt)) -ForegroundColor Gray }
  $tot=($rows | Measure-Object mb -Sum).Sum
  WARN ('合计 {0:N1} MB, 清理后需要时将重新下载' -f $tot)
  $c=Read-Host '   确认清理? (Y/N)'
  if($c -notmatch '^[Yy]'){ SKIP '已取消'; return }
  $freed=0.0
  foreach($r in $rows){
    foreach($f in $r.files){ Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    $freed+=$r.mb
    OK ('{0} : {1:N1} MB' -f $r.n,$r.mb)
  }
  OK ('本项释放磁盘: 约 {0:N1} MB' -f $freed)
}

function Restart-Explorer {
  WARN '将重启资源管理器: 桌面与任务栏会闪烁, 已打开的文件夹窗口会关闭'
  $c=Read-Host '   确认重启? (Y/N)'
  if($c -notmatch '^[Yy]'){ SKIP '已取消'; return }
  $ews=[math]::Round(((Get-Process -Name explorer -ErrorAction SilentlyContinue | Measure-Object WorkingSet64 -Sum).Sum)/1MB)
  $a0=Get-AvailMB
  Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
  if(-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)){ Start-Process explorer.exe }
  Start-Sleep -Seconds 1
  $a1=Get-AvailMB; $d=$a1-$a0
  $sign=''; if($d -ge 0){ $sign='+' }
  OK ('资源管理器已重启, 原实例占用约 {0} MB' -f $ews)
  W ('   内存可用: {0:N0} → {1:N0} MB  ({2}{3:N0} MB)' -f $a0,$a1,$sign,$d) DarkCyan
}

function Stop-WSL {
  $vm=@(Get-Process | Where-Object { $_.Name -like 'vmmem*' })
  if($vm.Count -eq 0){ SKIP '未检测到 WSL 虚拟机进程'; return }
  $mb=[math]::Round(($vm | Measure-Object WorkingSet64 -Sum).Sum/1MB)
  WARN ('vmmem 共占用约 {0:N0} MB, 关闭将结束 WSL 与 Docker 容器 (未保存的工作请先保存)' -f $mb)
  $c=Read-Host '   确认关闭? (Y/N)'
  if($c -notmatch '^[Yy]'){ SKIP '已取消'; return }
  wsl.exe --shutdown
  Start-Sleep -Seconds 2
  OK ('WSL 已关闭, 约释放 {0:N0} MB 内存 (逐步归还系统)' -f $mb)
}

function Reset-SysMain {
  $a0=Get-AvailMB
  try{ Restart-Service -Name SysMain -Force -ErrorAction Stop }catch{ WARN 'SysMain 重启失败 (可能已禁用)'; return }
  if($EngineOk -and $IsAdmin){ try{ [void][W32Mem]::Command(3) }catch{} }
  Start-Sleep -Seconds 1
  $a1=Get-AvailMB; $d=$a1-$a0
  $sign=''; if($d -ge 0){ $sign='+' }
  OK 'SysMain 已重置, 待机列表已清空'
  W ('   内存可用: {0:N0} → {1:N0} MB  ({2}{3:N0} MB)' -f $a0,$a1,$sign,$d) DarkCyan
}

function Clear-Bin {
  WARN '回收站内所有文件将不可恢复'
  $c=Read-Host '   确认清空? (Y/N)'
  if($c -notmatch '^[Yy]'){ SKIP '已取消'; return }
  $f0=Get-FreeAllMB
  Clear-RecycleBin -Force -ErrorAction SilentlyContinue
  $f1=Get-FreeAllMB; $dF=$f1-$f0
  if($dF -gt 0){ OK ('回收站已清空, 各盘合计释放 {0:N0} MB' -f $dF) }
  else { OK '回收站已清空 (原本就是空的, 释放 0 MB)' }
}

function Invoke-DeepTools {
  while($true){
    W ''
    W ('  '+'─'*58) DarkGray
    W '   深度可选工具 (每项独立确认, 全部显示释放量)' White
    W ('  '+'─'*58) DarkGray
    W '     [a] 清空事件日志       [b] DISM 组件清理 (可达数 GB)'
    W '     [c] Prefetch 预取缓存  [d] 开发者缓存 (npm/pip/uv/NuGet/Gradle/pnpm)'
    W '     [e] 重启资源管理器     [f] 关闭 WSL 虚拟机 (释放 vmmem)'
    W '     [g] 重置 SysMain       [h] 清空回收站'
    W '     [0] 返回主菜单'
    $k=(Read-Host '   请选择工具').Trim()
    if($k -eq '' -or $k -eq '0' -or $k -eq 'q'){ return }
    if($k -eq 'a'){ Clear-EventLogs }
    elseif($k -eq 'b'){ Init-Engine; Invoke-DismClean }
    elseif($k -eq 'c'){ Clean-Prefetch }
    elseif($k -eq 'd'){ Clean-DevCaches }
    elseif($k -eq 'e'){ Restart-Explorer }
    elseif($k -eq 'f'){ Stop-WSL }
    elseif($k -eq 'g'){ Init-Engine; Reset-SysMain }
    elseif($k -eq 'h'){ Clear-Bin }
    else { Write-Host '   无效选择' -ForegroundColor Red }
  }
}

# ---------- [5] 卡死进程管理 ----------
function Invoke-HungManager {
  $hung=@(Get-Hung -All)
  Step ('无响应进程列表 (共 {0} 个)' -f $hung.Count)
  if($hung.Count -eq 0){ SKIP '当前没有检测到无响应的窗口进程'; return }
  $tbl=$hung | Select-Object Id,Name,@{n='MB';e={[math]::Round($_.WorkingSet64/1MB)}},@{n='窗口标题';e={Short $_.MainWindowTitle 36}}
  Write-Host ($tbl | Format-Table -AutoSize | Out-String) -ForegroundColor Gray
  $ans=Read-Host '   输入 PID 结束指定进程 · 输入 A 结束全部 · 直接回车返回'
  if($ans -eq ''){ return }
  if($ans -match '^[Aa]$'){
    $ok=0; $freed=0
    foreach($p in $hung){ $r=End-Proc $p; if($r -ge 0){ $ok++; $freed+=$r } }
    OK ('共结束 {0}/{1} 个无响应进程' -f $ok,$hung.Count)
    if($freed -gt 0){ OK ('本项释放内存: 约 {0:N0} MB' -f $freed) } else { SKIP '本项释放: 0 MB' }
  } else { Kill-Pids $ans }
}

# ---------- [6] 资源占用 TOP ----------
function Get-CpuTop([int]$top=8,[int]$ms=800){
  $s=@{}
  foreach($p in (Get-Process)){ if($p.TotalProcessorTime){ $s[$p.Id]=$p.TotalProcessorTime.TotalMilliseconds } }
  Start-Sleep -Milliseconds $ms
  $rows=foreach($p in (Get-Process)){
    if($s.ContainsKey($p.Id) -and $p.TotalProcessorTime){
      $d=$p.TotalProcessorTime.TotalMilliseconds-$s[$p.Id]
      if($d -gt 0){
        [pscustomobject]@{ PID=$p.Id; 进程=$p.Name; 'CPU%'=[math]::Round($d/$ms/$Cores*100,1); MB=[math]::Round($p.WorkingSet64/1MB) }
      }
    }
  }
  $rows | Sort-Object 'CPU%' -Descending | Select-Object -First $top
}

function Invoke-TopUsage {
  Step '内存占用 TOP 10'
  $t=Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Id,Name,@{n='MB';e={[math]::Round($_.WorkingSet64/1MB)}},@{n='窗口标题';e={Short $_.MainWindowTitle 26}}
  Write-Host ($t | Format-Table -AutoSize | Out-String) -ForegroundColor Gray
  Step 'CPU 瞬时占用 TOP 8 (采样 0.8 秒)'
  $c=Get-CpuTop 8 800
  Write-Host ($c | Format-Table -AutoSize | Out-String) -ForegroundColor Gray
  $ans=Read-Host '   输入要结束的 PID (多个用空格分隔, 直接回车返回)'
  if($ans -ne ''){ Kill-Pids $ans }
}

# ---------- [7] GPU 状态 ----------
function Invoke-Gpu {
  Step '显卡适配器'
  $g=Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,Status
  Write-Host ($g | Format-Table -AutoSize | Out-String) -ForegroundColor Gray
  $smiPath=Get-SmiPath
  if(-not $smiPath){ SKIP '未检测到 nvidia-smi (AMD/Intel 显卡或未装 NVIDIA 驱动), 已显示适配器信息'; return }
  Step 'NVIDIA GPU 实时状态'
  & $smiPath 2>$null | Out-String -Width 110 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
  Step '占用 GPU 的进程'
  $lines=@(& $smiPath --query-compute-apps=pid,process_name,used_memory --format=csv,noheader | Where-Object { $_ -match '\S' })
  if($lines.Count -gt 0){
    $lines | ForEach-Object { Write-Host ('   '+$_) -ForegroundColor Gray }
    $pids=($lines | ForEach-Object { ($_ -split ',')[0].Trim() }) -join ' '
    $ans=Read-Host '   输入要结束的 PID (A=全部结束, 直接回车跳过)'
    if($ans -ne ''){
      if($ans -match '^[Aa]$'){ $ans=$pids }
      $gb0=(& $smiPath --query-gpu=memory.used --format=csv,noheader,nounits | ForEach-Object { [int]$_ } | Measure-Object -Sum).Sum
      Kill-Pids $ans
      $gb1=(& $smiPath --query-gpu=memory.used --format=csv,noheader,nounits | ForEach-Object { [int]$_ } | Measure-Object -Sum).Sum
      $dg=$gb0-$gb1
      if($dg -gt 0){ OK ('显存释放: {0} MiB  ({1} → {2} MiB)' -f $dg,$gb0,$gb1) }
      else { SKIP '显存释放: 0 MiB (进程结束后由驱动逐步回收)' }
    } else { SKIP '未结束进程, 显存释放 0 MiB' }
  } else { SKIP '当前没有进程独占 GPU 计算资源' }
}

# ---------- 界面 ----------
function Show-Banner {
  Clear-Host
  $availGB=[math]::Round((Get-CimInstance Win32_OperatingSystem -Property FreePhysicalMemory).FreePhysicalMemory/1MB,1)
  $usedPct=[int][math]::Round((1-($availGB/$TotalGB))*100)
  $cpu=Get-CpuLoad
  $cfreeGB=[math]::Round((Get-FreeCMB)/1024,1)
  $up=(Get-Date)-$OSc.LastBootUpTime
  $fill=[int]($usedPct/5); if($fill -gt 20){$fill=20}; if($fill -lt 0){$fill=0}
  $bar=('■'*$fill).PadRight(20,'□')
  $memColor = if($usedPct -ge 85){'Red'} elseif($usedPct -ge 65){'Yellow'} else {'Green'}
  $barline='  '+'═'*58
  W ''; W $barline DarkCyan
  W '        ◆   Q i a n 清 理   ·   360 级 全 面 清 理 工 具   ◆' Cyan
  W $barline DarkCyan; W ''
  W ('   系统 : {0}   已运行 {1}天{2}小时{3}分' -f $OSc.Caption,$up.Days,$up.Hours,$up.Minutes)
  if($IsAdmin){ W '   权限 : 管理员 (完整功能可用)' Green } else { W '   权限 : 普通用户 (部分功能受限, 建议以管理员身份运行)' Yellow }
  W ('   CPU  : 当前负载 {0}%    逻辑核心 {1} 个' -f $cpu,$Cores)
  W ('   内存 : [{0}] {1}%    可用 {2} / {3} GB' -f $bar,$usedPct,$availGB,$TotalGB) $memColor
  W ('   磁盘 : C 盘可用 {0:N1} GB' -f $cfreeGB)
  if($GpuNames){ W ('   显卡 : {0}' -f (Short $GpuNames 54)) } else { W '   显卡 : 未检测到' }
  W ''
  W ('  '+'─'*58) DarkGray
}

function Show-Menu {
  Show-Banner
  W '    [1]  一键全面清理     内存释放 + 19 类垃圾扫描清理 (直接回车 = 此项)' White
  W '    [2]  内存急救        卡死进程 + 工作集 + 待机列表 (纯内存, 快)' White
  W '    [3]  垃圾扫描预览    先看明细再决定, 不删文件' White
  W '    [4]  深度可选工具    事件日志 / DISM / 开发者缓存 / WSL / 回收站 ...' White
  W '    [5]  卡死进程管理    查看 / 选择性结束无响应进程' White
  W '    [6]  资源占用 TOP    内存 Top10 / CPU Top8, 可结束指定 PID' White
  W '    [7]  GPU 状态        显卡信息 / GPU 占用进程管理' White
  W '    [0]  退出' White
  W ''
  W '    提示: 支持一次多选依次执行, 如输入 23 = 先内存急救再垃圾扫描' DarkGray
  W '    Qian清理 v1.0.0 · 开源协议 AGPL-3.0 · 作者: 白小谦 · 反馈: qianxlfk@163.com' DarkGray
  W ''
}

# ---------- 多选解析 (支持: 1 3 4 / 134 / 1,3,4) ----------
$OpNames=@{ '1'='一键全面清理'; '2'='内存急救'; '3'='垃圾扫描预览'; '4'='深度可选工具'; '5'='卡死进程管理'; '6'='资源占用 TOP'; '7'='GPU 状态' }
function Parse-Choices([string]$s){
  $s=($s -replace '[,，、;；+]+',' ').Trim()
  if($s -eq ''){ return @('1') }
  $out=@()
  foreach($p in ($s -split '\s+' | Where-Object { $_ -ne '' })){
    if($p -match '^[0-9]+$'){ foreach($ch in $p.ToCharArray()){ $out+=[string]$ch } }
    else { $out+=$p }
  }
  return $out
}

# ---------- 主循环 (多选依次执行) ----------
$emptyGuard=0
while($true){
  Show-Menu
  $c=Read-Host '   请选择 (可多选: 1 3 4 或 134, 直接回车 = 1)'
  if($null -eq $c){ break }
  if($c.Trim() -eq ''){ $emptyGuard++ } else { $emptyGuard=0 }
  if($emptyGuard -gt 3){ break }
  $choices=@(Parse-Choices $c)
  $quit=$false; $ran=0
  foreach($ch in $choices){
    if($ch -eq '0' -or $ch -eq 'q' -or $ch -eq 'Q'){ $quit=$true; break }
    if(-not $OpNames.ContainsKey($ch)){
      Write-Host ("   忽略无效选择: {0}" -f $ch) -ForegroundColor Red
      Start-Sleep -Milliseconds 500
      continue
    }
    W ''
    W ('   ▶▶ 执行操作 [{0}] {1}' -f $ch,$OpNames[$ch]) Magenta
    $ran++
    if($ch -eq '1'){ Invoke-FullClean }
    elseif($ch -eq '2'){ Invoke-MemClean }
    elseif($ch -eq '3'){ Invoke-ScanPreview }
    elseif($ch -eq '4'){ Invoke-DeepTools }
    elseif($ch -eq '5'){ Invoke-HungManager }
    elseif($ch -eq '6'){ Invoke-TopUsage }
    elseif($ch -eq '7'){ Invoke-Gpu }
  }
  if($quit){ break }
  if($ran -gt 0){
    W ''
    W ('   ✔ 本轮共执行 {0} 项操作, 各项释放量见上方报告' -f $ran) DarkCyan
    Pause-Return
  }
}
W ''
W '   Qian清理 已退出, 本窗口可以关闭了.' DarkGray
W '   v1.0.0 · AGPL-3.0 · 白小谦 · qianxlfk@163.com' DarkGray
