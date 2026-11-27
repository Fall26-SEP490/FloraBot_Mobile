# FloraBot Mobile — chức năng và kế hoạch nghiệm thu

Ngày cập nhật: 27/11/2026. Công nghệ: Flutter, Dart, Material 3; Android/iOS, Web dùng để kiểm tra giao diện. Đây là app dùng API thật, không có tài khoản hoặc dữ liệu giả để thay thế backend.

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
6. Nhắn tin với chủ shop, xem tin, gửi văn bản và ảnh. Chat tự cập nhật qua SignalR khi app đang hoạt động; chưa có push nền.
7. Sửa hồ sơ cá nhân, đổi mật khẩu, đăng xuất. Không có quản lý nhân viên, giá sản phẩm, doanh thu hoặc quản lý tài khoản owner.

## 5. Seller: vận hành shop

| Nhóm | Chức năng đã triển khai |
|---|---|
| Tổng quan | Đơn gần đây, lối tắt; số đếm được ghi rõ theo trang hiện tại, không giả tổng toàn hệ thống |
| Tủ và ô | Danh sách kiosk, danh sách ô, chi tiết hoa/trạng thái/cảm biến/phiên bảo trì |
| Nạp/thu hồi/thay hoa | Cấp OTP theo session/action; mở bước kế tiếp, kiểm tra và thử lại nếu API cho phép; kiểm tra tiến độ; ghi nhận sự cố |
| Giao việc | Tạo nhiệm vụ kho cho nhân viên theo kiosk/ô/sản phẩm; xem nhiệm vụ; duyệt/hủy theo điều kiện BE |
| Quyền sửa chữa | Danh sách yêu cầu Technical và owner xác nhận cấp quyền |
| Sản phẩm | Danh sách, tạo/sửa thông tin, giá, kích thước, số lượng; chọn tag loại hoa, màu sắc, chất liệu theo mã Web; tải ảnh |
| Nhân viên | Tạo tài khoản nhân viên; xem và chuyển ACTIVE/DISABLED |
| Preorder | Xem yêu cầu, báo giá/cập nhật/từ chối; chọn lịch; xem đơn đã thanh toán |
| Nạp preorder | Chủ shop nạp qua OTP email hoặc giao Staff; xác nhận nạp sau chu kỳ cửa hợp lệ |
| Nhận hoa | Gửi/gửi lại OTP 8 số tới email đăng nhập CUSTOMER qua BE; owner không được xem mã của khách |
| Trao đổi | Chat khách hàng và nhân viên, ảnh, trạng thái đọc; SignalR cập nhật hội thoại và danh sách khi đang mở app |
| Phụ kiện | Tạo/sửa phụ kiện kho SHOP, nhập kho, bật/dừng bán |
| Phản ánh chất lượng | Tiếp nhận, giao kiểm tra, lập phương án thay hoa, duyệt báo cáo, hủy phương án theo version BE |
| Kênh thanh toán | Xem, xác minh, tạm dừng/bật lại; chỉ ADMIN gắn cấu hình payOS |
| Hoàn tiền trực tiếp | Xem khoản hoàn, mở tài khoản nhận hoàn theo lý do; gửi ảnh chứng từ và thông tin giao dịch đã chuyển |
| Chấm dứt thuê | Xem yêu cầu theo kiosk, gửi yêu cầu, rút yêu cầu REQUESTED đúng version |
| Shop | Xem/sửa tên shop, điện thoại, email liên hệ |
| Phân tích | Thống kê bán theo mùa; yêu cầu dự báo; thể hiện rõ dữ liệu thiếu/cảnh báo từ AI |
| Gói thuê | Xem gói và kỳ thuê, yêu cầu gia hạn và mở thanh toán; quy trình thuê mới/ngoại lệ mở cổng Web để đăng nhập bình thường |

Mẫu hoa có bật/ngừng bán theo API. Admin và Operations Manager tiếp tục dùng Web; mobile chỉ có Customer, Seller, Seller Staff và Technician.

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

Đã đối chiếu hợp đồng với BE main; trạng thái triển khai host cần kiểm tra riêng. Mobile không đổi schema DB. API/domain hiện hữu tiếp tục quyết định tenant, task assignment, owner grant và chuyển trạng thái.

Các hạng mục chưa có trong bản này:

1. Nối report-issue bảo trì thành incident và tạo/điều phối task Technical tự động. BE hiện ghi nhận báo cáo nhưng không bảo đảm sinh task. App không thể tự giải quyết SessionExpired bằng đổi nhãn FE; Manager vẫn cần quy trình xử lý hợp lệ.
2. Khôi phục nạp preorder: khi thiếu ID cục bộ, app gọi lại loading-access đúng actor/task/order/slot. Backend trả phiên còn hiệu lực hoặc cấp mới. Phiên mới yêu cầu nhập OTP và hoàn thành chu kỳ cửa trước khi xác nhận; BE vẫn kiểm tra cửa/phiên. Không lưu OTP.
3. Chưa có push FCM/APNs, badge nền, realtime công việc; App Links thanh toán/reset; Google OAuth native; offline cache nghiệp vụ. Chat đã có SignalR. Có quét QR cho liên kết HTTPS trên các domain FloraBot cho phép; QR được mở trong trình duyệt sau xác nhận. Khi quay lại app, ResourceView tải lại dữ liệu để kiểm tra trạng thái thật.
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

## Bổ sung Customer ngày 21/11/2026

- Mục Khám phá có Gợi ý chọn hoa bằng AI, gọi POST /api/shop/flower-chat với mode PREORDER và ngân sách. Ba lựa chọn loại hoa/màu/chất liệu dùng cùng mã của form seller; được đưa vào câu hỏi tư vấn. Các đặc điểm được gửi trong câu hỏi tư vấn; trước khi hiển thị, app đối chiếu từng gợi ý với API catalog theo productId/kioskId, yêu cầu đủ tag đã chọn và giá hiện tại trong ngân sách. Không xác minh được thì không hiển thị gợi ý đó. Mỗi tên tìm tối đa 10 trang; không bù thêm mẫu ngoài danh sách AI. Nút Xem mẫu đưa tên gợi ý về danh mục để tiếp tục chọn/đặt.
- Các thao tác tiền/OTP chỉ được nghiệm thu qua API staging và thiết bị thật; unit/widget tests không chứng minh thanh toán hoặc cửa.
- Push, Google OAuth native và verified App Links chưa cấu hình theo xác nhận của chủ dự án. Không thêm Firebase credentials giả hoặc hạ quyền bảo mật để thay thế.


## 9. Đối chiếu Web bổ sung ngày 27/11/2026

- Customer: xem/gửi đánh giá một lần khi BE cho phép; ảnh JPEG/PNG/WebP tối đa 2 MB; đọc đánh giá cả shop và phân trang. Nút đánh giá nằm trong chi tiết mẫu hoa.
- Customer: tìm kiosk theo tên/mã/địa chỉ, lọc trạng thái, ưu tiên trực tuyến, tìm gần tôi khi được cấp vị trí, xem bản đồ Goong và chỉ đường. Khi không có khóa bản đồ vẫn dùng được danh sách/chỉ đường. Không lấy vị trí nền.
- Customer: từ Tài khoản → Thuê kiosk / Mở shop, tạo hồ sơ lần đầu với shop, ngân hàng, số ô, vị trí và phiên bản bảng giá; thanh toán/đối chiếu/hủy theo trạng thái BE. Chỉ đăng nhập lại dưới Seller sau khi BE hoàn tất chuyển vai trò; app không tự nâng quyền.
- Seller: tư vấn bán theo dịp gọi seasonal-advice độc lập với seasonal-forecast; xuất tệp XLSX từ endpoint sales.csv đúng bộ lọc ngày qua màn chia sẻ của thiết bị. ID và dữ liệu người dùng là ô chữ, không chạy công thức từ CSV.
- Seller Staff: ngoài nhiệm vụ kho và preorder, có nạp hoa bán tại tủ cho task tổng quát qua stock. Khi mất phản hồi giữ mã thao tác, kiểm tra actions trước khi gửi lại để tránh nạp trùng.
- Technician/Seller Staff: xem ảnh riêng tư, phóng to, phân trang; lịch sử công việc truy xuất được các trang cũ. Technician có bảng lý do BE chặn gửi báo cáo và kiểm tra lại.
- Technician: INCIDENT gửi resolve-incident, KIOSK_REMOVAL gửi transition SUBMITTED. Lắp đặt vẫn do Manager nghiệm thu trên Web; ảnh lắp đặt có danh sách xem lại.
- Chung: tải nền gộp yêu cầu đang chạy và giữ nội dung; chuyển trang/bộ lọc không dùng dữ liệu của trang trước. Thanh phân trang tự xuống dòng ở màn hình hẹp.

### Kiểm chứng

- flutter analyze; flutter test; flutter build apk --debug.
- Test bổ sung kiểm tra payload Customer, nạp hoa khi mất phản hồi, quyền đánh giá/ảnh, phân trang ảnh/lịch sử, giới hạn báo giá, xử lý refresh khi xuất CSV, XLSX không chạy công thức và vị trí bị từ chối.
- Thanh toán thật, camera/GPS trên thiết bị thật, thao tác cửa/cảm biến và nghiệm thu Manager cần nghiệm thu liên vai trò với dữ liệu test được nhóm cho phép. Bộ test không tự tạo dữ liệu thật trên host.
- Khóa Goong truyền bằng dart-define hoặc cấu hình local bị Git ignore; không đưa khóa, token hay ngân hàng vào mã nguồn/log.


## 10. UI/UX mobile

- Giữ đầy đủ nghiệp vụ và quyền của bốn vai trò; thay đổi trong phần này chỉ là trình bày/điều hướng.
- Tổng quan Technician/Staff tập trung vào công việc, lắp đặt/trao đổi và thiết bị; bỏ banner quảng bá và số đếm của riêng trang đầu dễ gây hiểu nhầm.
- Trạng thái có chữ, biểu tượng và màu riêng cho đã giao, đang làm, chờ duyệt, hoàn tất và sự cố. Kiểm thử độ tương phản chữ tối thiểu 4,5:1.
- Thẻ danh sách có dấu mở chi tiết, nội dung dài xem đầy đủ trong chi tiết; lịch sử thu gọn nhưng vẫn truy cập tất cả trang.
- Bộ lọc công việc tự xuống dòng; phân trang một trang được ẩn; màn vận hành dùng nền dịu, Customer giữ nhận diện hoa.
- Form đăng nhập bỏ tiêu đề và câu hướng dẫn lặp. Không đổi cách xác thực, endpoint hay điều kiện chuyển trạng thái.

### Rà tiếp UI/UX ngày 27/11/2026

- Thiết bị: đổi tiêu đề thành “Tín hiệu thiết bị”, nhóm riêng từng ô, bỏ tên linh kiện khỏi dòng chính; phần hướng dẫn phần cứng vẫn mở xem được. Không suy diễn tín hiệu phát hiện vật thành đã giao hoa và không hiển thị số đo cũ như dữ liệu mới.
- Customer: thống nhất tên “Yêu cầu đặt trước”; giá tạm tính vẫn ở chân form. Seller vẫn dùng báo giá đúng nghiệp vụ.
- Kỳ thuê và nhân viên/công việc: dùng chung kiểu trạng thái có màu và biểu tượng, giữ nhãn riêng theo ngữ cảnh; phân trang tự xuống dòng khi thiếu chỗ.
- Form dùng chung: thêm nút đóng, cho thông báo lỗi xuống dòng; kiểm tra khả năng cuộn khi mở bàn phím ở màn rộng 320 px.
- Xác minh: 177 unit/widget tests đạt; flutter analyze không báo lỗi. Không thay endpoint, payload, phân quyền hoặc guard nghiệm thu BE. Chưa thay thế kiểm thử thiết bị và các luồng thanh toán/cửa thật.
