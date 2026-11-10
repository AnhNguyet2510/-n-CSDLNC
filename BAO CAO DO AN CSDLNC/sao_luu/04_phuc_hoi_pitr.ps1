# 04_phuc_hoi_pitr.ps1
# Khoi phuc ve thoi diem truoc khi xoa nham (PITR) tu base_full + WAL da archive.
#   .\04_phuc_hoi_pitr.ps1 -Mode Ten    : dung theo ten moc  (cong 55492, thu muc restore)
#   .\04_phuc_hoi_pitr.ps1 -Mode Gio    : dung theo thoi diem (cong 55493, thu muc restore_time)
#   them -GiuChay de giu server phuc hoi dang chay sau khi kiem tra (de chup man hinh / xem bang)
# Chay sau 03_xoa_nham.ps1. Moi che do co the chay lai nhieu lan (se lam lai tu dau).
param(
    [ValidateSet('Ten', 'Gio')][string]$Mode = 'Ten',
    [switch]$GiuChay
)

. "$PSScriptRoot\00_cau_hinh.ps1"
Test-Cau-Hinh
Bat-Nhat-Ky "04_phuc_hoi_pitr_$Mode"

try {
    $tt_file = "$KetQua\trang_thai_truoc_xoa.json"
    if (-not (Test-Path $tt_file)) { throw 'Chua co trang_thai_truoc_xoa.json. Chay 03_xoa_nham.ps1 truoc.' }
    if (-not (Test-Path "$Lab\base_full\backup_manifest")) { throw 'Chua co base_full.' }
    $tt = Get-Content $tt_file -Raw | ConvertFrom-Json

    if ($Mode -eq 'Ten') {
        $dir = "$Lab\restore"; $port = $PortTen; $log = "$Lab\restore.log"; $nhan = 'ten_moc'
        $muctieu = "recovery_target_name = '$($tt.ten_moc)'"
    } else {
        $dir = "$Lab\restore_time"; $port = $PortGio; $log = "$Lab\restore_time.log"; $nhan = 'thoi_diem'
        $muctieu = "recovery_target_time = '$($tt.gio_muc_tieu)'"
    }

    Write-Host "== PITR theo $Mode : thu muc $dir, cong $port ==" -ForegroundColor Green
    Write-Host "Muc tieu: $muctieu"

    # Don dep ban phuc hoi cu cua che do nay (neu co)
    Tat-Server $dir
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    if (Test-Path $log) { Remove-Item $log -Force }

    # ---- Do RTO: tu luc chep ban sao luu den luc server het che do phuc hoi ----
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Copy-Item "$Lab\base_full" $dir -Recurse
    $cfg = @"

# ---- Cau hinh Task 5: phuc hoi PITR ----
port = $port
archive_mode = off
restore_command = 'copy "$Arch\\%f" "%p"'
$muctieu
recovery_target_action = 'promote'
"@
    Add-Content "$dir\postgresql.conf" -Value $cfg -Encoding ASCII
    New-Item "$dir\recovery.signal" -ItemType File | Out-Null
    Get-Content "$dir\postgresql.conf" | Select-Object -Last 8

    $global:LASTEXITCODE = 0
    & "$Bin\pg_ctl.exe" start -D $dir -l $log -w
    $khoiDong = ($LASTEXITCODE -eq 0)
    $xong = $false
    if ($khoiDong) { $xong = Doi-Het-Phuc-Hoi $port 180 }
    $sw.Stop()
    $rto = [math]::Round($sw.Elapsed.TotalSeconds, 1)

    if (-not $xong) {
        if (Test-Path $log) { Get-Content $log -Tail 25 }
        throw "Server phuc hoi khong hoan tat trong thoi gian cho (xem log o tren)."
    }
    Write-Host ("RTO (chep + phuc hoi) PITR theo {0}: {1:N1} giay" -f $Mode, $rto) -ForegroundColor Cyan
    Ghi-So-Do "RTO PITR theo $Mode" $rto 'chep base_full + phat lai WAL den het che do recovery'

    # ---- Kiem tra ket qua ----
    Write-Host '== Doi chieu du lieu sau khoi phuc ==' -ForegroundColor Green
    Hien-So $port
    Chay-Sql $port "SELECT SoCT FROM chung_tu WHERE SoCT LIKE 'LAB5-%' ORDER BY SoCT;"
    $kp = Lay-So $port
    $soLab5 = [int](Lay-Gia-Tri $port "SELECT count(*) FROM chung_tu WHERE SoCT LIKE 'LAB5-%';")

    Write-Host '== Cac dong log quan trong ==' -ForegroundColor Green
    $dong = Select-String $log -Pattern 'point-in-time|redo starts|redo done|recovery stopping|archive recovery complete|ready to accept'
    $dong | ForEach-Object { $_.Line }
    Copy-Item $log "$KetQua\pitr_theo_${nhan}_restore.log" -Force

    $ok = ($kp.Ct -eq $tt.ct) -and ($kp.Sc -eq $tt.sc) -and ($kp.Lech -eq 0) -and ($soLab5 -eq 4)
    [pscustomobject]@{
        che_do        = $Mode
        muc_tieu      = $muctieu
        rto_giay      = $rto
        ct_mong_doi   = $tt.ct
        sc_mong_doi   = $tt.sc
        ct_thuc_te    = $kp.Ct
        sc_thuc_te    = $kp.Sc
        lech          = $kp.Lech
        so_chung_tu_LAB5 = $soLab5
        dat           = $ok
    } | ConvertTo-Json | Set-Content "$KetQua\ket_qua_pitr_$Mode.json" -Encoding UTF8

    if ($ok) { Write-Host "KET QUA PITR ($Mode): PASS (ct=$($kp.Ct) sc=$($kp.Sc) lech=0, du 4 chung tu LAB5-)" -ForegroundColor Green }
    else { Write-Host "KET QUA PITR ($Mode): FAIL (mong doi $($tt.ct)/$($tt.sc)/0 va 4 chung tu LAB5-; thuc te $($kp.Ct)/$($kp.Sc)/$($kp.Lech), LAB5-=$soLab5)" -ForegroundColor Red }

    if ($GiuChay) { Write-Host "Server phuc hoi van chay o cong $port. Tat bang: pg_ctl stop -D $dir -m fast" -ForegroundColor Yellow }
    else { Tat-Server $dir }
}
finally { Tat-Nhat-Ky }
