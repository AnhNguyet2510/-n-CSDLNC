# Task 5: Sao lưu, WAL archiving và PITR

Bộ script dựng một cluster PostgreSQL thử nghiệm riêng, sao lưu (logic, vật lý toàn phần và gia tăng), bật WAL archiving, giả lập xóa nhầm dữ liệu đã COMMIT rồi khôi phục về thời điểm trước lúc xóa (PITR). Mọi số đo được ghi ra file để dùng cho báo cáo.

## Yêu cầu

- Windows, PowerShell 5.1 trở lên.
- PostgreSQL **17 trở lên** (cần `pg_basebackup --incremental` và `pg_combinebackup`). Đã viết cho PostgreSQL 18 tại `C:\Program Files\PostgreSQL\18\bin`.
- Bộ SQL của phần cơ sở dữ liệu: `01_tao_bang.sql`, `02_rang_buoc_trigger_thu_tuc.sql`, `03_du_lieu_mau.sql`.
- Các cổng 55491, 55492, 55493 còn trống. Cluster thử nghiệm không ảnh hưởng PostgreSQL chính của máy.
- Ổ đĩa còn trống vài trăm MB (kho WAL lớn dần, mỗi file 16 MB).

## Cấu trúc

```
sao_luu/
├── 00_cau_hinh.ps1          cấu hình và hàm dùng chung (không chạy trực tiếp)
├── 01_dung_cluster.ps1      dựng cluster, bật WAL archiving, nạp dữ liệu mẫu
├── 02_sao_luu.ps1           sao lưu logic, vật lý toàn phần và gia tăng
├── 03_xoa_nham.ps1          giả lập xóa nhầm (TRUNCATE đã COMMIT)
├── 04_phuc_hoi_pitr.ps1     PITR theo tên mốc hoặc theo thời điểm
├── 05_do_rpo.ps1            đo độ trễ lưu WAL (RPO)
├── cau_hinh/
│   ├── postgresql_archive.conf    cấu hình WAL archiving (tham khảo)
│   └── postgresql_recovery.conf   cấu hình phục hồi PITR (tham khảo)
├── ket_qua_lan1/            kết quả lần chạy 1 (gõ lệnh tay)
├── ket_qua_lan2/            kết quả lần chạy 2 (gõ lệnh tay)
├── ket_qua_lan3/            kết quả lần chạy 3 (chạy bằng script)
├── KET_QUA_SAO_LUU.md       tổng hợp số đo và phân tích của ba lần
├── Bao_cao_Task5.docx       mục Task 5 của báo cáo
├── Ke_hoach_sao_luu_de_xuat.docx   kế hoạch sao lưu đề xuất
└── README.md
```

Đặt thư mục `sao_luu` trong thư mục chứa `01_tao_bang.sql` (hoặc cùng cấp với nó); script tự tìm các file SQL. Nếu không tìm thấy, gán tay biến `$SqlDir` trong `00_cau_hinh.ps1`.

Các thư mục `ket_qua_lanN` là kết quả đã lưu của từng lần chạy. Script không ghi vào các thư mục này mà ghi vào `$Lab\ket_qua` (xem mục "Kết quả được ghi ở đâu").

## Cấu hình trước khi chạy

Mở `00_cau_hinh.ps1`, sửa hai dòng:

```powershell
$Bin = 'C:\Program Files\PostgreSQL\18\bin'
$Lab = 'F:\lab5'
```

`$Lab` là thư mục làm việc (chứa dữ liệu cluster, bản sao lưu, kho WAL và thư mục `ket_qua`). Nên đặt ở ổ khác với ổ hệ điều hành. Không dùng đường dẫn có dấu cách.

## Cách chạy

Mở PowerShell, chuyển vào thư mục `sao_luu`. Nếu bị chặn chạy script: `Set-ExecutionPolicy -Scope Process Bypass`.

| Bước | Lệnh | Việc làm | Kết quả mong đợi |
|---|---|---|---|
| 1 | `.\01_dung_cluster.ps1` | `initdb`, bật WAL archiving, nạp 01–03 | `PASS`: 9 chứng từ, 30 dòng sổ cái, `lech` = 0, `failed_count` = 0 |
| 2 | `.\02_sao_luu.ps1` | `pg_dump`, `pg_restore` thử, `pg_basebackup` toàn phần, thêm 2 chứng từ, gia tăng, ghép | Bản khôi phục logic khớp bản gốc; sau khi thêm: 11 chứng từ, 34 dòng sổ cái; `pg_verifybackup` thành công |
| 3 | `.\03_xoa_nham.ps1` | thêm 2 chứng từ, đặt mốc `truoc_xoa_nham`, `TRUNCATE` | Trước xóa 13 chứng từ, 38 dòng sổ cái; sau xóa `chung_tu` rỗng |
| 4a | `.\04_phuc_hoi_pitr.ps1 -Mode Ten` | PITR theo tên mốc (cổng 55492) | `PASS`: 13 chứng từ, 38 dòng sổ cái, `lech` = 0, đủ 4 chứng từ `LAB5-` |
| 4b | `.\04_phuc_hoi_pitr.ps1 -Mode Gio` | PITR theo thời điểm (cổng 55493) | Như 4a; log có `recovery stopping before commit` |
| 5 | `.\05_do_rpo.ps1` | đo độ trễ lưu WAL, 3 lần | Mỗi lần mất khoảng một phút chờ; kết thúc bằng dòng trung bình |

Mỗi script tự in `PASS` hoặc `FAIL` ở cuối. Thêm `-GiuChay` vào bước 4 để giữ server phục hồi đang chạy (ví dụ để mở pgAdmin xem bảng): kết nối `127.0.0.1`, cổng 55492 hoặc 55493, database `ketoan_lab`, user `postgres`, không mật khẩu. Tắt bằng `pg_ctl stop -D <thư mục> -m fast`.

## Chạy lại từ đầu

```powershell
.\01_dung_cluster.ps1 -Reset
```

`-Reset` dừng các server của lab rồi **xóa** `data`, `backup`, `wal_archive`, `base_*`, `restore*` trong `$Lab` (giữ lại `ket_qua`). Hãy chép minh chứng cũ sang nơi khác trước.

Thư mục `ket_qua` không bị xóa nên số đo của các lần chạy được ghi nối tiếp vào cùng file CSV (cột `Thoi_diem` để phân biệt lần chạy), và các file trùng tên như log PITR sẽ bị ghi đè. **Trước mỗi lần chạy lại, đổi tên `$Lab\ket_qua`** (ví dụ `ket_qua_cu`), và sau khi chạy xong chép kết quả mới vào một thư mục có tên riêng trong repo (ví dụ `ket_qua_lan4`) thay vì chép chung vào thư mục cũ.

## Kết quả được ghi ở đâu

Tất cả nằm trong `$Lab\ket_qua`:

| File | Nội dung |
|---|---|
| `so_do_thuc_te.csv` | Thời gian từng bước (sao lưu, khôi phục, RTO, độ trễ lưu WAL) |
| `kich_thuoc_sao_luu_logic.csv`, `kich_thuoc_sao_luu_vat_ly.csv` | Kích thước các bản sao lưu |
| `trang_thai_truoc_xoa.json`, `gio_muc_tieu.txt` | Trạng thái đúng trước khi xóa nhầm và giờ mục tiêu cho PITR |
| `ket_qua_pitr_Ten.json`, `ket_qua_pitr_Gio.json` | Kết quả đối chiếu sau PITR |
| `pitr_theo_ten_moc_restore.log`, `pitr_theo_thoi_diem_restore.log` | Log phục hồi của PostgreSQL |
| `cau_hinh_archive_them_vao.conf` | Các dòng cấu hình đã thêm vào `postgresql.conf` |
| `nhat_ky_<script>.txt` | Nhật ký toàn bộ lệnh và kết quả của từng script |

## Phân biệt số đo thực tế với phân tích lý thuyết

- **Đo thực tế:** thời gian sao lưu và khôi phục, kích thước, RTO (từ lúc chép bản sao lưu đến khi server hết chế độ phục hồi), độ trễ lưu WAL. Mọi số này lấy từ `so_do_thuc_te.csv` và các CSV kích thước.
- **Lý thuyết hoặc đề xuất:** lịch sao lưu, mục tiêu RPO/RTO và replication (xem file kế hoạch sao lưu đề xuất).

## Giới hạn cần nêu trong báo cáo

- Chạy trên một máy cá nhân, dữ liệu rất nhỏ (vài chục chứng từ). Số đo mang tính tương đối và không suy ra được thời gian với dữ liệu thật.
- Mỗi chỉ tiêu chỉ đo một đến vài lần. Nếu chạy lại, ghi các lần như những lần đo độc lập, đừng kết luận lần nào nhanh hơn.
- RPO đo ở đây là độ trễ lưu WAL (đo gián tiếp), không phải mô phỏng mất ổ đĩa. Kho WAL nằm cùng máy, thường cùng ổ vật lý với dữ liệu, nên chưa đại diện cho bản sao tách khỏi máy chủ.
- `TRUNCATE` là cách giả lập xóa nhầm của người có quyền cao. Nó đi vòng qua trigger chặn xóa chứng từ đã ghi sổ vì trigger đó chỉ chặn `DELETE` từng dòng.
- Replication chưa được thực nghiệm, chỉ đề xuất.

## Lỗi thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| `Da co '...\data'` | Chạy `01_dung_cluster.ps1 -Reset` |
| Cổng 55491 hoặc 5549x đang bận | Còn server lab đang chạy: `pg_ctl status -D "$Lab\data"` rồi tắt; hoặc đổi cổng trong `00_cau_hinh.ps1` |
| `failed_count` tăng, kho WAL rỗng | Xem `server.log`; thường do `archive_command` sai đường dẫn hoặc ổ lab không ghi được |
| Chữ tiếng Việt hiển thị sai trong thông báo | Chỉ là lỗi hiển thị của console, dữ liệu không bị ảnh hưởng |
| `pg_combinebackup` hoặc `--incremental` không có | Cần PostgreSQL 17 trở lên |
| `04` báo FAIL, `ct` = 0 khi PITR theo giờ | Giờ mục tiêu nằm sau lệnh xóa. Chạy lại bước 3 từ đầu bằng `-Reset` để lấy giờ mới |
