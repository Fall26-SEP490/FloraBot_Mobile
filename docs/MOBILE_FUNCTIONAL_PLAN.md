# FloraBot Mobile — chức năng và kế hoạch nghiệm thu

Ngày: 13/11/2026. Công nghệ: Flutter, Dart, Material 3; Android/iOS, Web dùng để kiểm tra giao diện. Đây là app dùng API thật, không có tài khoản hoặc dữ liệu giả để thay thế backend.

## 1. Vai trò và giới hạn

| Persona trên app | Role Backend | Mục đích | Không được cấp quyền |
|---|---|---|---|
| Technical | TECHNICIAN | Việc kỹ thuật được giao, lắp đặt, bằng chứng, quyền kiểm tra tủ | Tài chính của shop; tự giao/duyệt việc của Manager |
| Seller staff | SELLER_STAFF | Công việc của chính mình, nạp/thu hồi/thay hoa theo nhiệm vụ, trao đổi với chủ shop | Mượn sellerId để quản trị shop, nhân viên, sản phẩm hoặc tiền |
| Seller | SELLER | Tủ, kho hoa, nhân viên, đơn đặt, phê duyệt quyền sửa chữa | Công việc quản trị hệ thống/Manager |
| Khách preorder | CUSTOMER | Chọn mẫu, yêu cầu báo giá, thanh toán, theo dõi nhận hoa và hỗ trợ | Quyền thiết bị hoặc OTP bảo trì |

Preorder là nhóm chức năng của CUSTOMER, không tạo role PREORDER mới trong DB. Manager tiếp tục dùng Web để điều phối và bàn giao.

## 2. Chức năng chung đã có trong code

1. Chọn vai trò, email và mật khẩu; máy chủ kiểm tra role thực của tài khoản. Không cho người dùng tự nâng quyền qua dropdown.
2. Access token chỉ trong RAM; refresh token lưu trong bộ nhớ bảo mật Android/iOS, tách theo API origin. Web preview giữ token trong RAM.
3. Tự gia hạn phiên một lần khi nhận 401, gộp các yêu cầu gia hạn đồng thời. Không tự gửi lại thao tác khi mất mạng/timeout vì máy chủ có thể đã xử lý.
4. Mất mạng không tự đăng xuất. Giữ workspace khi lỗi tải/gia hạn; cold start có refresh đã lưu nhưng chưa kết nối được thì hiện màn hình thử lại. Chỉ kết luận phiên không hợp lệ khi máy chủ từ chối refresh; không cho sửa dữ liệu khi không kết nối được.
5. Đăng xuất chủ động xóa phiên trên thiết bị kể cả khi offline. Nếu offline thì chưa thể xác nhận thu hồi token trên server; token server vẫn có thời hạn.
6. Hồ sơ cá nhân: xem/sửa tên, số điện thoại, địa chỉ; xác minh email liên hệ. Email đăng nhập không bị đổi ngầm bởi email liên hệ.
7. Đổi mật khẩu cho cả bốn role qua API Mobile; yêu cầu đăng nhập lại sau khi đổi. Quên mật khẩu CUSTOMER/SELLER qua email; Technical/Staff được hướng dẫn liên hệ nơi cấp tài khoản.
8. CUSTOMER đăng ký và xác minh email rồi đăng nhập Mobile; CUSTOMER có đóng tài khoản theo API hiện hữu.
9. Danh sách phân trang, kéo tải lại, xử lý quyền từ chối, xung đột phiên bản và lỗi mạng; không hiển thị thành công giả khi chỉ quay về từ trình duyệt thanh toán.
10. OTP không lưu vào thiết bị/clipboard. Màn hình OTP xóa mã khi hết hạn hoặc chuyển app sang nền; quay lại cần cấp lại nếu mã đã ẩn. Có màn che nội dung khi app chạy nền; chưa có cơ chế chống chụp màn hình toàn app.

## 3. Technical: luồng từ đăng nhập đến kết thúc việc

| Bước | Màn hình/hành động đã có | Điều kiện / bên chịu trách nhiệm |
|---|---|---|
| 1 | Tổng quan và danh sách việc, lọc trạng thái, xem lịch sử | Chỉ việc do API cấp cho người đang đăng nhập |
| 2 | Xem kiosk, địa chỉ; mở bản đồ; bắt đầu công việc | Trạng thái và version lấy lại từ API chi tiết |
| 3 | Xin OTP kiểm tra sửa chữa | Task IN_PROGRESS; cần owner grant hợp lệ và tình trạng ô phù hợp do BE kiểm tra |
| 4 | Nhập OTP tại đúng kiosk và kiểm tra thực tế | App không chứa apiKey/MQTT key và không tự xác nhận OTP thay kiosk |
| 5 | Chụp/chọn ảnh JPEG/PNG; tải và gắn bằng chứng; nhập báo cáo | Không tự phát lại upload khi mạng đứt |
| 6 | Gửi kết quả xử lý sự cố | BE quyết định điều kiện hợp lệ; không tự sửa trạng thái cảm biến |
| 7 | Danh sách lắp đặt; bắt đầu lắp; ảnh; gửi nghiệm thu | Manager tiếp tục bàn giao trên Web; Technical không tự bàn giao |
| 8 | Tài khoản, đổi mật khẩu, đăng xuất | Không có chức năng tài chính |

## 4. Seller staff: nhận việc và thao tác tại tủ

1. Đăng nhập SELLER_STAFF, xem danh sách công việc được giao; bắt đầu việc.
2. Xem đúng kiosk/ô, hành động được giao, sản phẩm dự kiến, hướng dẫn và lịch sử.
3. Việc kho: lấy OTP cho START, OPEN_NEXT hoặc OPEN_FOR_CHECK theo nhiệm vụ; nhập mã trên kiosk. BE tiếp tục chặn các hành động vượt phạm vi.
4. Việc preorder: chọn đơn/ô trong phạm vi được giao, gửi OTP nạp tới email người thực hiện; sau khi nạp và đóng cửa mới xác nhận bằng loadingAccessId. API không trả OTP email cho app.
5. Tải ảnh bằng chứng, viết báo cáo, gửi SUBMITTED; chủ shop duyệt. Không tự nâng công việc thành hoàn thành khi API yêu cầu duyệt.
6. Nhắn tin với chủ shop, xem tin, gửi văn bản và ảnh. Cập nhật bằng tải lại; chưa có push nền.
7. Sửa hồ sơ cá nhân, đổi mật khẩu, đăng xuất. Không có quản lý nhân viên, giá sản phẩm, doanh thu hoặc quản lý tài khoản owner.

## 5. Seller: vận hành shop

| Nhóm | Chức năng đã triển khai |
|---|---|
| Tổng quan | Đơn gần đây, lối tắt; số đếm được ghi rõ theo trang hiện tại, không giả tổng toàn hệ thống |
| Tủ và ô | Danh sách kiosk, danh sách ô, chi tiết hoa/trạng thái/cảm biến/phiên bảo trì |
| Nạp/thu hồi/thay hoa | Cấp OTP theo session/action; mở bước kế tiếp, kiểm tra và thử lại nếu API cho phép; kiểm tra tiến độ; ghi nhận sự cố |
| Giao việc | Tạo nhiệm vụ kho cho nhân viên theo kiosk/ô/sản phẩm; xem nhiệm vụ; duyệt/hủy theo điều kiện BE |
| Quyền sửa chữa | Danh sách yêu cầu Technical và owner xác nhận cấp quyền |
| Sản phẩm | Danh sách, tạo/sửa thông tin, giá, kích thước, số lượng, tags; tải ảnh |
| Nhân viên | Tạo tài khoản nhân viên; xem và chuyển ACTIVE/DISABLED |
| Preorder | Xem yêu cầu, báo giá/cập nhật/từ chối; chọn lịch; xem đơn đã thanh toán |
| Nạp preorder | Chủ shop nạp qua OTP email hoặc giao Staff; xác nhận nạp sau chu kỳ cửa hợp lệ |
| Nhận hoa | Gửi/gửi lại OTP 8 số tới email đăng nhập CUSTOMER qua BE; owner không được xem mã của khách |
| Trao đổi | Chat khách hàng và chat nhân viên, ảnh và trạng thái đọc |
| Shop | Xem/sửa tên shop, điện thoại, email liên hệ |
| Phân tích | Thống kê bán theo mùa; yêu cầu dự báo; thể hiện rõ dữ liệu thiếu/cảnh báo từ AI |
| Gói thuê | Xem gói và kỳ thuê, yêu cầu gia hạn và mở thanh toán; quy trình thuê mới/ngoại lệ mở cổng Web để đăng nhập bình thường |

Sản phẩm chưa có nút chuyển toàn bộ trạng thái khả dụng; quy trình duyệt sản phẩm, kế toán/đối soát/rút tiền, chấm dứt thuê, hồ sơ thuê mới tiếp tục trên Web. Đây là phạm vi mở rộng riêng, không giả lập bằng thao tác đổi trạng thái tại app.

## 6. CUSTOMER/preorder: mua và nhận hoa

1. Đăng ký, xác minh email, đăng nhập; khôi phục mật khẩu và quản lý hồ sơ.
2. Khám phá mẫu đang cho đặt trước; tìm kiếm, xem ảnh/giá tham khảo/shop/kiosk/địa chỉ; mở chat hỏi shop.
3. Nhập yêu cầu và chọn ngày giờ nhận; kiểm tra chỗ trống dự kiến; gửi CUSTOM preorder bằng request UUID.
4. Xem yêu cầu, báo giá, thời hạn; chấp nhận chính xác giá/lịch/note đã được shop báo. BE kiểm tra lại khi có thay đổi.
5. Tạo link payOS, xem số tiền và người nhận trước khi mở trình duyệt HTTPS. Trở lại app và tải trạng thái; chỉ BE xác nhận đã thanh toán.
6. Xem kiosk và khung giờ nhận, trạng thái đã nạp; nhận OTP 8 số qua email đăng nhập khi shop gửi, nhập tại kiosk. Không có API lấy lại mã email trực tiếp trong app.
7. Hủy theo điều kiện BE; không hứa hủy/hoàn tiền ngoài điều kiện hệ thống.
8. Biên nhận: xem dòng hàng, tổng tiền, đã hoàn/chờ hoàn; gửi khiếu nại kèm ảnh trong thời hạn máy chủ cho phép; gửi/cập nhật thông tin tài khoản nhận hoàn khi có khoản chờ hoàn.
9. Chat shop; thông tin biên nhận/tracking token và ngân hàng chỉ ở RAM và body/header HTTPS, không ghép vào URL.

App phục vụ preorder. Mua walk-in tại màn kiosk vẫn theo luồng kiosk hiện hữu; không tạo giả tính năng mở cửa bằng điện thoại cho CUSTOMER.

## 7. Backend đi kèm và khoảng trống cần xử lý

Đã viết thêm trong FloraBot_BE:

- POST /api/mobile/auth/login, /refresh, /logout: token JSON cho native, không phụ thuộc cookie Web; role whitelist; refresh lưu Redis namespace riêng, dùng một lần, 7 ngày; access 10 phút CUSTOMER/15 phút các role khác.
- POST /api/mobile/auth/password: đổi mật khẩu bốn role theo kiểm tra mật khẩu hiện tại, policy Account và credential version.
- Chi tiết công việc Staff trả thêm version/status để cập nhật đúng phiên bản.
- Quy trình xuất OpenAPI hiện hữu đã bao gồm endpoint mới; không sửa generated contract FE bằng tay.

Chưa triển khai những thay đổi này lên server. Không đổi schema DB. API/domain hiện hữu tiếp tục quyết định tenant, task assignment, owner grant và chuyển trạng thái.

Các hạng mục chưa có trong bản này:

1. Nối report-issue bảo trì thành incident và tạo/điều phối task Technical tự động. BE hiện ghi nhận báo cáo nhưng không bảo đảm sinh task. App không thể tự giải quyết SessionExpired bằng đổi nhãn FE; Manager vẫn cần quy trình xử lý hợp lệ.
2. Khôi phục loadingAccessId sau khi đóng app: hiện ID chỉ trong màn hình; cần BE cung cấp API khôi phục phiên theo actor/task/order nếu muốn tiếp tục an toàn sau process death. Không lưu OTP để lách hạn chế này.
3. Push FCM/APNs, badge nền, realtime chat/công việc; deep link thanh toán/reset; Google OAuth native; QR scanner và offline cache nghiệp vụ. Hiện có tải lại và trình duyệt ngoài.
4. Idempotent retry/grace khi refresh token đã bị server consume nhưng phản hồi mất trên đường truyền: hiện giữ phiên khi lỗi mạng; nếu token cũ sau đó bị server xác nhận đã dùng/hết hạn thì phải đăng nhập lại. Cần thiết kế BE riêng nếu muốn phục hồi tình huống này mà vẫn chống replay.
5. Xác minh chính sách phát hành, icon/splash riêng, ký release, App Links, cấu hình production và đánh giá accessibility trên thiết bị thật trước store release.

## 8. Nghiệm thu trên staging với bốn tài khoản thử

| Nhóm kiểm tra | Kết quả cần đạt |
|---|---|
| Đăng nhập | Chọn sai role bị từ chối; disabled không truy cập; mỗi actor chỉ thấy phạm vi của mình |
| Mạng | Tắt Wi-Fi không tự logout; bật lại tải được; cold start offline có Thử lại; chủ động logout offline xóa phiên máy |
| Token | Nhiều 401 chỉ một refresh; refresh chỉ dùng một lần, không dùng token Web cho native; đổi mật khẩu thu hồi phiên cũ |
| Technical | Việc đúng người; owner grant; OTP đúng tủ; cửa/cảm biến thật; ảnh/báo cáo; Manager nghiệm thu |
| Staff | Không truy cập owner API; việc đúng người; version conflict tải lại; nạp xong đóng cửa mới xác nhận |
| Seller | OTP kho đúng action; không tự hoàn thành phiên kẹt; giao việc, duyệt, grant sửa; khóa tài khoản Staff |
| Preorder | Yêu cầu → báo giá → accept → thanh toán webhook → nạp → email OTP → nhận; kiểm tra cả hết hạn/hủy |
| Hỗ trợ | Khiếu nại chỉ trong cửa sổ cho phép, ảnh thật và token đúng đơn; không in/log tracking token hoặc số ngân hàng |
| Thiết bị | Android thật: camera/gallery/quyền/lifecycle; iPhone qua Mac: build, Keychain và quyền ảnh; mạng yếu và process death |

Unit/widget tests không thay cho nghiệm thu cảm biến, email, thanh toán và thiết bị thật. Không dùng API key kiosk trong app.
