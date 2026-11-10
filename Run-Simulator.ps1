param([ValidateRange(1,100)][int]$Count=100,[ValidateRange(5,3600)][int]$Seconds=120,[switch]$Menu,[switch]$PrepareOnly,[switch]$Parallel)
$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot 'simulator-data'
New-Item -ItemType Directory -Force $root | Out-Null
$base=Join-Path $root 'window-placeholder-v3.exe'
$source=@'
using System;
using System.Windows.Forms;
class Placeholder {
 [STAThread] static void Main(string[] args) {
  if(args.Length>2) {
   DateTime deadline=DateTime.UtcNow.AddSeconds(60);
   while(!System.IO.File.Exists(args[2])) {
    if(DateTime.UtcNow>deadline) return;
    System.Threading.Thread.Sleep(25);
   }
  }
  Application.EnableVisualStyles();
  Form f=new Form(); f.Text=args[1]; f.Width=460; f.Height=140;
  Label l=new Label(); l.Text="Local activity simulator: "+args[1]; l.Dock=DockStyle.Fill; f.Controls.Add(l);
  Timer t=new Timer(); t.Interval=int.Parse(args[0])*1000; t.Tick+=(s,e)=>f.Close(); t.Start();
  Application.Run(f);
 }
}
'@
function Banner {
 Clear-Host
 Write-Host ' ============================================================' -ForegroundColor Cyan
 Write-Host '                  DISCORD GAME SIMULATOR' -ForegroundColor White
 Write-Host ' ============================================================' -ForegroundColor Cyan
 Write-Host '  Local simulation | Discord badge credit: UNVERIFIED' -ForegroundColor Yellow
 Write-Host ''
}
try {
 if($Menu) {
  Banner
  Write-Host '  [1] Test: 3 games x 60 seconds'
  Write-Host '  [2] Full: 100 games x 120 seconds'
  Write-Host '  [3] FAST SEQUENTIAL: 100 games x 6 seconds'
  Write-Host '  [0] Exit'
  switch(Read-Host '  Choose') {
   '1' {$Count=3;$Seconds=60}
   '2' {$Count=100;$Seconds=120}
   '3' {$Count=100;$Seconds=6;$Parallel=$false}
   default {exit}
  }
 }
 if(!(Test-Path -LiteralPath $base)) { Add-Type -TypeDefinition $source -ReferencedAssemblies System.Windows.Forms,System.Drawing -OutputAssembly $base -OutputType WindowsApplication }
 Write-Host 'Loading public Discord catalog. No login required.'
 $catalog=Invoke-RestMethod 'https://discord.com/api/v9/applications/detectable' -TimeoutSec 30
 $selected=@(); $seen=@{}
 foreach($game in $catalog) {
  foreach($entry in $game.executables) {
   $name=([string]$entry.name).Replace('\','/')
   if($entry.os -ne 'win32' -or $entry.is_launcher -eq $true -or $name -notmatch '^[a-zA-Z0-9_ -][a-zA-Z0-9_./ -]*\.exe$' -or $name.Length -gt 140) { continue }
   if(@($name.Split('/') | Where-Object {$_ -in @('','.','..')}).Count) {continue}
   $leaf=($name.Split('/') | Select-Object -Last 1).ToLowerInvariant()
   if($seen.ContainsKey($leaf)) { continue }
   $seen[$leaf]=$true
   $selected+=[pscustomobject]@{game=[string]$game.name; executable=$name}
   break
  }
  if($selected.Count -ge $Count) { break }
 }
 if(!$selected.Count) { throw 'No compatible executable names found.' }
 $selected | Export-Csv (Join-Path $root 'selected-games.csv') -NoTypeInformation -Encoding UTF8
 if($PrepareOnly) {Write-Host ('Prepared {0} games and window executable.' -f $selected.Count);exit 0}
 Write-Host 'EXPERIMENT: Discord detection and badge credit are NOT guaranteed.'
 Write-Host 'Keep Discord desktop open. Ctrl+C stops the experiment.'
 if($Parallel) {
  $jobs=@();$prepared=@()
  $gate=Join-Path $root ('start-'+[guid]::NewGuid().ToString('N')+'.signal')
  try {
   foreach($game in $selected) {
    $dir=Join-Path $root ('parallel\'+$prepared.Count)
    $exe=Join-Path $dir $game.executable.Replace('/','\')
    New-Item -ItemType Directory -Force (Split-Path $exe -Parent) | Out-Null
    Copy-Item -LiteralPath $base -Destination $exe -Force
    $prepared+=[pscustomobject]@{game=$game;path=$exe}
   }
   Banner
   Write-Host '  Preparing simultaneous start...' -ForegroundColor Cyan
   foreach($item in $prepared) {
    $title=$item.game.game.Replace('"','')
    $p=Start-Process -FilePath $item.path -ArgumentList @([string]$Seconds,('"'+$title+'"'),('"'+$gate+'"')) -WorkingDirectory (Split-Path $item.path -Parent) -PassThru
    $jobs+=[pscustomobject]@{process=$p;game=$item.game;time=(Get-Date)}
    Write-Host ('  READY  PID {0,-7} {1}' -f $p.Id,$item.game.game) -ForegroundColor Green
   }
   New-Item -ItemType File -Path $gate | Out-Null
   $batchStart=Get-Date
   do {
    $active=0
    foreach($job in $jobs) {$job.process.Refresh();if(!$job.process.HasExited){$active++}}
    Write-Host ("`r  RUNNING: {0}/{1} | elapsed: {2}s     " -f $active,$jobs.Count,[int]((Get-Date)-$batchStart).TotalSeconds) -NoNewline -ForegroundColor Cyan
    if($active -gt 0) {Start-Sleep -Milliseconds 250}
    if(((Get-Date)-$batchStart).TotalSeconds -gt ($Seconds+30)) {throw 'Some windows did not close within the timeout.'}
   } while($active -gt 0)
   Write-Host "`n  Batch finished. Discord credit is unverified."
  } finally {
   foreach($job in $jobs) {
    $job.process.Refresh()
    $status='local process completed; Discord credit unverified'
    if(!$job.process.HasExited) {$job.process.Kill();$status='interrupted'}
    elseif($job.process.ExitCode -ne 0) {$status='process error: '+$job.process.ExitCode}
    [pscustomobject]@{time=$job.time.ToString('o');game=$job.game.game;executable=$job.game.executable;status=$status} | Export-Csv (Join-Path $root 'history.csv') -Append -NoTypeInformation -Encoding UTF8
   }
   if(Test-Path -LiteralPath $gate) {Remove-Item -LiteralPath $gate}
  }
  exit 0
 }
 for($i=0;$i -lt $selected.Count;$i++) {
  $game=$selected[$i]
  $dir=Join-Path $root ([string]$i)
  $exe=Join-Path $dir $game.executable.Replace('/','\')
  New-Item -ItemType Directory -Force (Split-Path $exe -Parent) | Out-Null
  Copy-Item -LiteralPath $base -Destination $exe -Force
  Write-Host ('[{0}/{1}] {2} - {3}s' -f ($i+1),$selected.Count,$game.game,$Seconds)
  $process=$null
  $started=Get-Date
  $status='interrupted'
  try {
   $title=$game.game.Replace('"','')
   $process=Start-Process -FilePath $exe -ArgumentList @([string]$Seconds,('"'+$title+'"')) -WorkingDirectory (Split-Path $exe -Parent) -PassThru
   while(!$process.HasExited) {
    $elapsed=[int]((Get-Date)-$started).TotalSeconds
    $fill=[Math]::Min(30,[int](30*$elapsed/$Seconds))
    Banner
    Write-Host ('  NOW        : '+$game.game) -ForegroundColor Green
    Write-Host ('  EXE        : '+$game.executable)
    Write-Host ('  PID        : '+$process.Id+' (running)')
    Write-Host ('  QUEUE      : {0} / {1}' -f ($i+1),$selected.Count)
    Write-Host ('  REMAINING  : {0}s' -f [Math]::Max(0,$Seconds-$elapsed))
    Write-Host ('  [{0}{1}]' -f ('#'*$fill),('.'*(30-$fill))) -ForegroundColor Cyan
    $discord=@(Get-Process -Name Discord,DiscordPTB,DiscordCanary -ErrorAction SilentlyContinue)
    Write-Host ('  DISCORD    : '+$(if($discord.Count){'client process found'}else{'NOT RUNNING'}))
    Write-Host '  DETECTION  : check Registered Games in Discord' -ForegroundColor Yellow
    if($i -gt 0) {Write-Host ('  PREVIOUS   : '+$selected[$i-1].game) -ForegroundColor DarkGray}
    Write-Host ''
    Write-Host '  Ctrl+C stops. Each game window closes by timer.'
    Start-Sleep -Milliseconds 100
    $process.Refresh()
   }
   if($process.ExitCode -ne 0) {throw ('Process failed: '+$process.ExitCode)}
   $status='local process completed; Discord credit unverified'
  } finally {
   if($process -and !$process.HasExited) { $process.Kill() }
   [pscustomobject]@{time=$started.ToString('o');game=$game.game;executable=$game.executable;status=$status} | Export-Csv (Join-Path $root 'history.csv') -Append -NoTypeInformation -Encoding UTF8
  }
 }
 Write-Host 'Finished. Check the badge manually in Discord.'
} catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
