# 05_do_rpo.ps1
# Do do tre tu luc COMMIT mot giao dich den luc file WAL chua no nam trong kho archive.
# Day la do GIAN TIEP khoang du lieu co the mat (RPO) voi archive_timeout = 60;
# khong phai mo phong mat o dia.
#   .\05_do_rpo.ps1            (3 lan do)
#   .\05_do_rpo.ps1 -SoLan 5
# Chay khi server cong 55491 dang chay (co the chay sau 01, khong can sau 03).
param([int]$SoLan = 3)

. "$PSScriptRoot\00_cau_hinh.ps1"
Test-Cau-Hinh
Bat-Nhat-Ky '05_do_rpo'

try {
    if (-not (Server-Dang-Chay "$Lab\data")) { throw 'Server thu nghiem chua chay.' }
    Chay-Sql $PortGoc 'CREATE TABLE IF NOT EXISTS rpo_test(id serial, t timestamptz DEFAULT now());'

    $ketqua = @()
    for ($i = 1; $i -le $SoLan; $i++) {
        # Dua WAL cu sang kho de bat dau tu trang thai sach, doi 8 giay roi moi COMMIT
        $null = Lay-Gia-Tri $PortGoc 'SELECT pg_switch_wal();'
        Start-Sleep 8
        $t0 = Get-Date
        Chay-Sql $PortGoc 'INSERT INTO rpo_test DEFAULT VALUES;' | Out-Null
        $wal = Lay-Gia-Tri $PortGoc 'SELECT pg_walfile_name(pg_current_wal_lsn());'
        $daLuu = $false
        for ($k = 0; $k -lt 300; $k++) {
            $r = Lay-Gia-Tri $PortGoc "SELECT COALESCE((SELECT last_archived_wal FROM pg_stat_archiver) >= '$wal', false);"
            if ($r -eq 't') { $daLuu = $true; break }
            Start-Sleep 1
        }
        $giay = [math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
        $trangThai = if ($daLuu) { 'da archive' } else { 'QUA THOI GIAN CHO' }
        Write-Host ("Lan {0}: do tre COMMIT -> da archive = {1:N1} giay (WAL {2}, {3})" -f $i, $giay, $wal, $trangThai) -ForegroundColor Cyan
        Ghi-So-Do "RPO lan $i (do tre archive)" $giay "WAL $wal; archive_timeout = 60"
        $ketqua += $giay
    }
    Chay-Sql $PortGoc 'DROP TABLE rpo_test;'

    $tb = [math]::Round(($ketqua | Measure-Object -Average).Average, 1)
    Write-Host ("Cac lan do (giay): {0} | trung binh {1}" -f ($ketqua -join ' / '), $tb) -ForegroundColor Green
    Write-Host 'Ghi chu cho bao cao: day la do tre luu WAL (do gian tiep), khong phai mo phong mat o dia.' -ForegroundColor Yellow
}
finally { Tat-Nhat-Ky }
