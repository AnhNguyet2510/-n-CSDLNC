DO $$
DECLARE v_ct bigint;
BEGIN
  INSERT INTO CHUNG_TU (SoCT, NgayLap, NgayGhiSo, MaLoaiCT, MaKy, LyDo)
  VALUES ('LAB5-B2', '2026-03-20', '2026-03-20', 'PKT', '2026-M03', 'Du lieu lab5')
  RETURNING MaCT INTO v_ct;
  INSERT INTO CHI_TIET_CHUNG_TU (MaCT, SttDong, MaTKNo, MaTKCo, SoTien)
  VALUES (v_ct, 1, '1111', '411', 100000);
  CALL sp_post_voucher(v_ct);
END $$;
