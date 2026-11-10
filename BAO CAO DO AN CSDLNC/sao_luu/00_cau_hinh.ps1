# 00_cau_hinh.ps1
# Cau hinh va ham dung chung cho cac script Task 5. KHONG chay truc tiep file nay;
# cac script 01..05 se nap file nay bang: . "$PSScriptRoot\00_cau_hinh.ps1"

$ErrorActionPreference = 'Continue'

# ===================== SUA CAC DONG NAY CHO DUNG MAY CUA BAN =====================
$Bin = 'C:\Program Files\PostgreSQL\18\bin'   # thu muc bin cua PostgreSQL (can 17 tro len)
$Lab = 'F:\lab5'                              # thu muc lam viec cua lab (se tao neu chua co)
# =================================================================================

# Tu tim thu muc chua 01_tao_bang.sql (script nam trong BAO CAO DO AN CSDLNC\sao_luu)
$SqlDir = $null
foreach ($cand in @("$PSScriptRoot\..", "$PSScriptRoot\..\BAO CAO DO AN CSDLNC", "$PSScriptRoot")) {
    if (Test-Path (Join-Path $cand '01_tao_bang.sql')) { $SqlDir = (Resolve-Path $cand).Path; break }
}
# Neu khong tu tim duoc, bo dau # o dong duoi va gan duong dan dung:
# $SqlDir = 'F:\Github\-n-CSDLNC\BAO CAO DO AN CSDLNC'

$Db       = 'ketoan_lab'
$PortGoc  = 55491      # cluster thu nghiem (co bat WAL archiving)
$PortTen  = 55492      # ban phuc hoi PITR theo ten moc
$PortGio  = 55493      # ban phuc hoi PITR theo thoi diem
$KetQua   = "$Lab\ket_qua"
# Duong dan kho WAL, moi dau \ nhan doi vi se ghi vao postgresql.conf
$Arch     = ($Lab + '\wal_archive') -replace '\\', '\\'

$env:PGCLIENTENCODING = 'UTF8'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Test-Cau-Hinh {
    foreach ($f in 'initdb.exe','psql.exe','pg_ctl.exe','pg_dump.exe','pg_dumpall.exe','pg_restore.exe',
                   'pg_basebackup.exe','pg_combinebackup.exe','pg_verifybackup.exe') {
        if (-not (Test-Path (Join-Path $Bin $f))) {
            throw "Khong thay $f trong '$Bin'. Kiem tra bien `$Bin (can PostgreSQL 17 tro len de co pg_combinebackup)."
        }
    }
    if (-not $SqlDir) { throw "Khong tim thay 01_tao_bang.sql. Gan tay bien `$SqlDir trong 00_cau_hinh.ps1." }
    foreach ($f in '01_tao_bang.sql','02_rang_buoc_trigger_thu_tuc.sql','03_du_lieu_mau.sql') {
        if (-not (Test-Path (Join-Path $SqlDir $f))) { throw "Thieu file $f trong '$SqlDir'." }
    }
}

# ---------- Chay SQL ----------
function Chay-Sql([int]$Port, [string]$Sql, [string]$Database = $Db) {
    & "$Bin\psql.exe" -h 127.0.0.1 -p $Port -U postgres -d $Database -X -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "psql loi khi chay: $Sql" }
}
function Lay-Gia-Tri([int]$Port, [string]$Sql, [string]$Database = $Db) {
    $r = & "$Bin\psql.exe" -h 127.0.0.1 -p $Port -U postgres -d $Database -X -At -v ON_ERROR_STOP=1 -c $Sql
    if ($LASTEXITCODE -ne 0) { throw "psql loi khi chay: $Sql" }
    return (($r | Out-String).Trim())
}
function Chay-File-Sql([int]$Port, [string]$Path, [string]$Database = $Db) {
    & "$Bin\psql.exe" -h 127.0.0.1 -p $Port -U postgres -d $Database -X -q -v ON_ERROR_STOP=1 -f $Path
    if ($LASTEXITCODE -ne 0) { throw "psql loi khi chay file: $Path" }
}
function Lay-So([int]$Port, [string]$Database = $Db) {
    $r = Lay-Gia-Tri $Port "SELECT (SELECT count(*)::text FROM chung_tu)||'|'||(SELECT count(*)::text FROM so_cai)||'|'||(SELECT count(*)::text FROM v_chung_tu_lech)" $Database
    $p = $r.Split('|')
    return [pscustomobject]@{ Ct = [int]$p[0]; Sc = [int]$p[1]; Lech = [int]$p[2] }
}
function Hien-So([int]$Port, [string]$Database = $Db) {
    Chay-Sql $Port "SELECT (SELECT count(*) FROM chung_tu) AS ct, (SELECT count(*) FROM so_cai) AS sc, (SELECT count(*) FROM v_chung_tu_lech) AS lech;" $Database
}

# ---------- Them mot chung tu 100.000 dong va ghi so ----------
function Them-CT([string]$So) {
    $tpl = @'
DO $$
DECLARE v_ct bigint;
BEGIN
  INSERT INTO CHUNG_TU (SoCT, NgayLap, NgayGhiSo, MaLoaiCT, MaKy, LyDo)
  VALUES ('__SO__', '2026-03-20', '2026-03-20', 'PKT', '2026-M03', 'Du lieu lab5')
  RETURNING MaCT INTO v_ct;
  INSERT INTO CHI_TIET_CHUNG_TU (MaCT, SttDong, MaTKNo, MaTKCo, SoTien)
  VALUES (v_ct, 1, '1111', '411', 100000);
  CALL sp_post_voucher(v_ct);
END $$;
'@
    $f = "$Lab\them_ct.sql"
    Set-Content -Path $f -Value ($tpl -replace '__SO__', $So) -Encoding ASCII
    Chay-File-Sql $PortGoc $f
}

# ---------- Dieu khien server ----------
function Server-Dang-Chay([string]$Dir) {
    if (-not (Test-Path "$Dir\PG_VERSION")) { return $false }
    & "$Bin\pg_ctl.exe" status -D $Dir *> $null
    return ($LASTEXITCODE -eq 0)
}
function Bat-Server([string]$Dir, [string]$Log) {
    & "$Bin\pg_ctl.exe" start -D $Dir -l $Log -w
    if ($LASTEXITCODE -ne 0) {
        if (Test-Path $Log) { Get-Content $Log -Tail 20 }
        throw "Khong khoi dong duoc server trong $Dir"
    }
}
function Tat-Server([string]$Dir) {
    if (Server-Dang-Chay $Dir) { & "$Bin\pg_ctl.exe" stop -D $Dir -m fast | Out-Null }
}
# Doi cho den khi server het che do phuc hoi (pg_ctl -w co the tra ve som khi con dang phat lai WAL)
function Doi-Het-Phuc-Hoi([int]$Port, [int]$GioiHanGiay = 180) {
    $han = (Get-Date).AddSeconds($GioiHanGiay)
    while ((Get-Date) -lt $han) {
        $r = & "$Bin\psql.exe" -h 127.0.0.1 -p $Port -U postgres -d $Db -X -Atc "SELECT pg_is_in_recovery()" 2>$null
        if (($r | Out-String).Trim() -eq 'f') { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

# ---------- Do thoi gian va ghi so do ----------
function Ghi-So-Do([string]$Buoc, [double]$Giay, [string]$GhiChu = '') {
    New-Item -ItemType Directory -Force $KetQua | Out-Null
    [pscustomobject]@{
        Thoi_diem = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        Buoc      = $Buoc
        Giay      = [math]::Round($Giay, 2)
        Ghi_chu   = $GhiChu
    } | Export-Csv "$KetQua\so_do_thuc_te.csv" -Append -NoTypeInformation -Encoding UTF8
}
# Chay mot khoi lenh goi chuong trinh ngoai, bam gio, bao loi neu ma thoat khac 0
function Chay-Do([string]$Ten, [scriptblock]$Khoi, [string]$GhiChu = '') {
    $global:LASTEXITCODE = 0
    $sw = [Diagnostics.Stopwatch]::StartNew()
    & $Khoi | Out-Host
    $sw.Stop()
    if ($LASTEXITCODE -ne 0) { throw "Buoc '$Ten' that bai (ma thoat $LASTEXITCODE)." }
    $giay = $sw.Elapsed.TotalSeconds
    Ghi-So-Do $Ten $giay $GhiChu
    Write-Host ("[{0}] {1:N2} giay" -f $Ten, $giay) -ForegroundColor Cyan
    return $giay
}
function Kich-Thuoc-MB([string]$Path) {
    $s = (Get-ChildItem $Path -Recurse -File | Measure-Object Length -Sum).Sum
    return [math]::Round($s / 1MB, 1)
}
function Kiem-Tra-Ban-Sao([string]$Path) {
    & "$Bin\pg_verifybackup.exe" $Path
    if ($LASTEXITCODE -ne 0) { throw "pg_verifybackup bao loi voi $Path" }
}

# ---------- Nhat ky tu dong ----------
function Bat-Nhat-Ky([string]$Ten) {
    New-Item -ItemType Directory -Force $KetQua | Out-Null
    try { Start-Transcript -Path "$KetQua\nhat_ky_$Ten.txt" -Append | Out-Null } catch { }
}
function Tat-Nhat-Ky { try { Stop-Transcript | Out-Null } catch { } }

# ---------- Xoa lab cu (chi cac thu muc cua lab, GIU LAI ket_qua) ----------
function Xoa-Lab {
    if ($Lab.Length -lt 6 -or $Lab -match '^[A-Za-z]:\\?$') { throw "Duong dan lab '$Lab' qua ngan, tu choi xoa." }
    foreach ($d in 'data','restore','restore_time') { Tat-Server "$Lab\$d" }
    foreach ($d in 'data','restore','restore_time','base_full','base_inc1','base_combined','backup','wal_archive') {
        $p = "$Lab\$d"
        if (Test-Path $p) { Remove-Item $p -Recurse -Force }
    }
    foreach ($f in 'restore.log','restore_time.log','server.log','them_ct.sql') {
        if (Test-Path "$Lab\$f") { Remove-Item "$Lab\$f" -Force }
    }
    Write-Host "Da xoa du lieu lab trong '$Lab' (giu lai thu muc ket_qua)." -ForegroundColor Yellow
}
