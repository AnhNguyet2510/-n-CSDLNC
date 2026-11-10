# 03_xoa_nham.ps1
# Gia lap xoa nham du lieu tren cluster THU NGHIEM (cong 55491), da COMMIT.
# Ghi lai trang thai dung (so chung tu, so dong so cai) va thoi diem muc tieu cho PITR.
# Chay sau 02_sao_luu.ps1. Script nay CO CHU Y lam mat du lieu cua cluster thu nghiem.

. "$PSScriptRoot\00_cau_hinh.ps1"
Test-Cau-Hinh
Bat-Nhat-Ky '03_xoa_nham'

try {
    if (-not (Server-Dang-Chay "$Lab\data")) { throw 'Server thu nghiem chua chay. Chay 01 va 02 truoc.' }
    if (-not (Test-Path "$Lab\base_full\backup_manifest")) { throw 'Chua co base_full. Chay 02_sao_luu.ps1 truoc.' }
    if (Test-Path "$KetQua\trang_thai_truoc_xoa.json") {
        throw 'Da chay buoc xoa nham tren lab nay. Muon lam lai tu dau, chay 01_dung_cluster.ps1 -Reset.'
    }

    Write-Host '== Buoc 1: them 2 chung tu moi (chi co trong WAL, khong co trong ban sao luu nao) ==' -ForegroundColor Green
    Them-CT 'LAB5-B1'
    Them-CT 'LAB5-B2'
    Chay-Sql $PortGoc 'SELECT (SELECT count(*) FROM chung_tu) AS ct, (SELECT count(*) FROM so_cai) AS sc, (SELECT count(*) FROM v_chung_tu_lech) AS lech, now();'
    $truoc = Lay-So $PortGoc
    if (($truoc.Ct -ne 13) -or ($truoc.Sc -ne 38) -or ($truoc.Lech -ne 0)) {
        Write-Host "CANH BAO: mong doi 13/38/0 nhung duoc $($truoc.Ct)/$($truoc.Sc)/$($truoc.Lech). Van tiep tuc, PITR se doi chieu voi so thuc te nay." -ForegroundColor Yellow
    }

    Write-Host '== Buoc 2: dat moc phuc hoi co ten ==' -ForegroundColor Green
    $tenMoc = 'truoc_xoa_nham'
    Chay-Sql $PortGoc "SELECT pg_create_restore_point('$tenMoc');"
    Start-Sleep 5

    Write-Host '== Buoc 3: lay gio muc tieu (sau moc, truoc lenh xoa) ==' -ForegroundColor Green
    $gio = Lay-Gia-Tri $PortGoc 'SELECT clock_timestamp()::text;'
    Write-Host "Gio muc tieu cho PITR theo thoi diem: $gio"
    Start-Sleep 3

    Write-Host '== Buoc 4: gia lap xoa nham bang TRUNCATE (da COMMIT) ==' -ForegroundColor Green
    # TRUNCATE khong kich hoat trigger chan xoa tung dong cua My, mo phong nguoi co quyen cao xoa nham.
    Chay-Sql $PortGoc 'TRUNCATE chung_tu, chi_tiet_chung_tu, so_cai;'
    Chay-Sql $PortGoc 'SELECT pg_switch_wal();'
    Start-Sleep 5
    Chay-Sql $PortGoc 'SELECT count(*) AS ct_sau_xoa FROM chung_tu;'
    Chay-Sql $PortGoc 'SELECT archived_count, failed_count FROM pg_stat_archiver;'
    $sau = Lay-So $PortGoc

    [pscustomobject]@{
        ct           = $truoc.Ct
        sc           = $truoc.Sc
        ten_moc      = $tenMoc
        gio_muc_tieu = $gio
        ct_sau_xoa   = $sau.Ct
        thoi_diem_ghi = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    } | ConvertTo-Json | Set-Content "$KetQua\trang_thai_truoc_xoa.json" -Encoding UTF8
    $gio | Set-Content "$KetQua\gio_muc_tieu.txt" -Encoding ASCII

    if ($sau.Ct -eq 0) { Write-Host 'KET QUA: PASS (da xoa nham, chung_tu rong tren cluster goc). Chay tiep 04_phuc_hoi_pitr.ps1.' -ForegroundColor Green }
    else { Write-Host "KET QUA: FAIL (ct_sau_xoa = $($sau.Ct), mong doi 0)" -ForegroundColor Red }
}
finally { Tat-Nhat-Ky }
