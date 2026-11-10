# 02_sao_luu.ps1
# Sao luu logic (pg_dump), sao luu vat ly toan phan va gia tang, kiem tra tung ban.
# Chay sau 01_dung_cluster.ps1, khi server cong 55491 dang chay.
# Ket qua: thoi gian trong ket_qua\so_do_thuc_te.csv, kich thuoc trong ket_qua\kich_thuoc_*.csv

. "$PSScriptRoot\00_cau_hinh.ps1"
Test-Cau-Hinh
Bat-Nhat-Ky '02_sao_luu'

try {
    if (-not (Server-Dang-Chay "$Lab\data")) { throw 'Server thu nghiem chua chay. Chay 01_dung_cluster.ps1 truoc.' }
    foreach ($d in 'base_full','base_inc1','base_combined') {
        if (Test-Path "$Lab\$d") { throw "Da co '$Lab\$d'. Chay 01_dung_cluster.ps1 -Reset de lam lai tu dau." }
    }
    New-Item -ItemType Directory -Force "$Lab\backup" | Out-Null
    $conn = @('-h', '127.0.0.1', '-p', $PortGoc, '-U', 'postgres')

    Write-Host '== A. Sao luu logic ==' -ForegroundColor Green
    $null = Chay-Do 'pg_dump -Fc (nen)' { & "$Bin\pg_dump.exe" @conn -Fc -f "$Lab\backup\ketoan_full.dump" $Db }
    $null = Chay-Do 'pg_dump -Fp (SQL thuan)' { & "$Bin\pg_dump.exe" @conn -Fp -f "$Lab\backup\ketoan_full.sql" $Db }
    $null = Chay-Do 'pg_dumpall --globals-only' { & "$Bin\pg_dumpall.exe" @conn --globals-only -f "$Lab\backup\globals.sql" }
    Get-ChildItem "$Lab\backup" -File | Select-Object Name, Length |
        Export-Csv "$KetQua\kich_thuoc_sao_luu_logic.csv" -NoTypeInformation -Encoding UTF8
    Get-ChildItem "$Lab\backup" -File | Select-Object Name, Length | Format-Table -AutoSize

    Write-Host '-- Khoi phuc thu ban logic vao database moi ketoan_restored --' -ForegroundColor Green
    Chay-Sql $PortGoc 'DROP DATABASE IF EXISTS ketoan_restored' 'postgres'
    Chay-Sql $PortGoc 'CREATE DATABASE ketoan_restored' 'postgres'
    $null = Chay-Do 'pg_restore (khoi phuc logic)' { & "$Bin\pg_restore.exe" @conn -d ketoan_restored "$Lab\backup\ketoan_full.dump" }
    Hien-So $PortGoc 'ketoan_restored'
    $goc = Lay-So $PortGoc
    $kp  = Lay-So $PortGoc 'ketoan_restored'
    if (($goc.Ct -eq $kp.Ct) -and ($goc.Sc -eq $kp.Sc) -and ($kp.Lech -eq 0)) {
        Write-Host 'KET QUA logic: PASS (ban khoi phuc khop ban goc, lech = 0)' -ForegroundColor Green
    } else {
        Write-Host "KET QUA logic: FAIL (goc $($goc.Ct)/$($goc.Sc) - khoi phuc $($kp.Ct)/$($kp.Sc)/lech $($kp.Lech))" -ForegroundColor Red
    }

    Write-Host '== B. Sao luu vat ly toan phan ==' -ForegroundColor Green
    $null = Chay-Do 'pg_basebackup toan phan' { & "$Bin\pg_basebackup.exe" @conn -D "$Lab\base_full" -Fp -X stream -c fast -P }
    Kiem-Tra-Ban-Sao "$Lab\base_full"

    Write-Host '== C. Them 2 chung tu roi sao luu gia tang ==' -ForegroundColor Green
    Them-CT 'LAB5-A1'
    Them-CT 'LAB5-A2'
    Hien-So $PortGoc
    $so = Lay-So $PortGoc
    if (($so.Ct -eq 11) -and ($so.Sc -eq 34) -and ($so.Lech -eq 0)) { Write-Host 'Du lieu sau khi them: PASS (11 chung tu, 34 dong so cai)' -ForegroundColor Green }
    else { Write-Host "Du lieu sau khi them: FAIL (ct=$($so.Ct) sc=$($so.Sc) lech=$($so.Lech), mong doi 11/34/0)" -ForegroundColor Red }

    $null = Chay-Do 'pg_basebackup gia tang' {
        & "$Bin\pg_basebackup.exe" @conn -D "$Lab\base_inc1" -Fp -X stream -c fast "--incremental=$Lab\base_full\backup_manifest"
    }
    $null = Chay-Do 'pg_combinebackup (ghep)' { & "$Bin\pg_combinebackup.exe" "$Lab\base_full" "$Lab\base_inc1" -o "$Lab\base_combined" }
    Kiem-Tra-Ban-Sao "$Lab\base_combined"

    $kt = foreach ($d in 'base_full','base_inc1','base_combined') {
        [pscustomobject]@{ Thu_muc = $d; MB = (Kich-Thuoc-MB "$Lab\$d") }
    }
    $kt | Export-Csv "$KetQua\kich_thuoc_sao_luu_vat_ly.csv" -NoTypeInformation -Encoding UTF8
    $kt | Format-Table -AutoSize
    Write-Host 'Xong buoc sao luu. Chay tiep 03_xoa_nham.ps1.' -ForegroundColor Green
}
finally { Tat-Nhat-Ky }
