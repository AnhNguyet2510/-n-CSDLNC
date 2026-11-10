# 01_dung_cluster.ps1
# Dung cluster PostgreSQL rieng cho Task 5, bat WAL archiving, nap du lieu mau (01..03 cua My).
# Chay:   .\01_dung_cluster.ps1            (lan dau)
#         .\01_dung_cluster.ps1 -Reset     (xoa lab cu roi dung lai; GIU thu muc ket_qua)
# Luu y: -Reset xoa data, backup, wal_archive, base_*, restore*. Hay chep minh chung cu truoc.
param([switch]$Reset)

. "$PSScriptRoot\00_cau_hinh.ps1"
Test-Cau-Hinh
New-Item -ItemType Directory -Force $Lab, $KetQua | Out-Null
Bat-Nhat-Ky '01_dung_cluster'

try {
    if ($Reset) { Xoa-Lab }
    if (Test-Path "$Lab\data") {
        throw "Da co '$Lab\data'. Chay lai voi tham so -Reset de xoa lab cu (nho chep minh chung truoc)."
    }
    New-Item -ItemType Directory -Force "$Lab\wal_archive", "$Lab\backup" | Out-Null

    Write-Host '== Buoc 1: initdb ==' -ForegroundColor Green
    & "$Bin\initdb.exe" -D "$Lab\data" -U postgres --auth=trust --encoding=UTF8 --no-locale
    if ($LASTEXITCODE -ne 0) { throw 'initdb that bai.' }

    Write-Host '== Buoc 2: ghi cau hinh WAL archiving ==' -ForegroundColor Green
    $cfg = @"

# ---- Cau hinh Task 5: WAL archiving ----
port = $PortGoc
listen_addresses = '127.0.0.1'
cluster_name = 'task5_lab'
archive_mode = on
archive_command = 'if not exist "$Arch\\%f" copy "%p" "$Arch\\%f"'
archive_timeout = 60
summarize_wal = on
log_line_prefix = '%m [%p] '
logging_collector = off
"@
    Add-Content "$Lab\data\postgresql.conf" -Value $cfg -Encoding ASCII
    Set-Content "$KetQua\cau_hinh_archive_them_vao.conf" -Value $cfg.TrimStart() -Encoding ASCII
    Get-Content "$Lab\data\postgresql.conf" | Select-Object -Last 12

    Write-Host '== Buoc 3: khoi dong server va tao database ==' -ForegroundColor Green
    Bat-Server "$Lab\data" "$Lab\server.log"
    Chay-Sql $PortGoc "CREATE DATABASE $Db" 'postgres'

    Write-Host '== Buoc 4: nap 01..03 (DDL, trigger/thu tuc, du lieu mau) ==' -ForegroundColor Green
    foreach ($f in '01_tao_bang.sql','02_rang_buoc_trigger_thu_tuc.sql','03_du_lieu_mau.sql') {
        Chay-File-Sql $PortGoc (Join-Path $SqlDir $f)
        Write-Host "  da nap $f"
    }

    Write-Host '== Buoc 5: kiem tra du lieu va WAL archiving ==' -ForegroundColor Green
    Hien-So $PortGoc
    $so = Lay-So $PortGoc
    Chay-Sql $PortGoc 'SELECT pg_switch_wal();'
    Start-Sleep 5
    Chay-Sql $PortGoc 'SELECT archived_count, failed_count, last_archived_wal FROM pg_stat_archiver;'
    Get-ChildItem "$Lab\wal_archive" -File | Select-Object Name, Length | Format-Table -AutoSize
    $failed = [int](Lay-Gia-Tri $PortGoc 'SELECT failed_count FROM pg_stat_archiver;')
    $nWal = (Get-ChildItem "$Lab\wal_archive" -File | Measure-Object).Count

    $ok = ($so.Ct -eq 9) -and ($so.Sc -eq 30) -and ($so.Lech -eq 0) -and ($failed -eq 0) -and ($nWal -ge 1)
    if ($ok) { Write-Host 'KET QUA: PASS (9 chung tu, 30 dong so cai, lech = 0, archive khong loi)' -ForegroundColor Green }
    else { Write-Host "KET QUA: FAIL (ct=$($so.Ct) sc=$($so.Sc) lech=$($so.Lech) failed_count=$failed file_wal=$nWal)" -ForegroundColor Red }
}
finally { Tat-Nhat-Ky }
