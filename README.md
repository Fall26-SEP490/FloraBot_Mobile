# FloraBot Mobile (Flutter)

Ứng dụng Android/iOS cho TECHNICIAN, SELLER_STAFF, SELLER và CUSTOMER đặt trước. Giao diện tiếng Việt, gọi API thật. Kế hoạch chức năng, quyền và phần còn phụ thuộc hệ thống: [docs/MOBILE_FUNCTIONAL_PLAN.md](docs/MOBILE_FUNCTIONAL_PLAN.md).

## Lấy code về và chạy lần đầu

Cài Git, Flutter SDK, Chrome để xem giao diện Web và Android Studio kèm Android SDK để chạy Android. Bộ dependency hiện tại yêu cầu Flutter >=3.44 và Dart >=3.12 <4. Kiểm tra môi trường bằng `flutter doctor`.

Code Mobile đang ở nhánh `feature/flutter-role-workspaces`. Mở terminal tại thư mục muốn lưu dự án rồi chạy:

```bash
git clone -b feature/flutter-role-workspaces https://github.com/Fall26-SEP490/FloraBot_Mobile.git
cd FloraBot_Mobile
flutter pub get
flutter run -d chrome --web-hostname=localhost --web-port=57466
```

Lệnh cuối mở giao diện trên Chrome. Repository riêng tư yêu cầu tài khoản GitHub đã được cấp quyền truy cập.

Dùng cổng cố định `57466` để origin luôn là `http://localhost:57466`; Backend phải cho phép chính xác origin này. Cổng ngẫu nhiên của Flutter có thể thay đổi mỗi lần chạy. Nếu gặp lỗi CORS, xem phần bên dưới trước khi thử đăng nhập lại.

Để chạy trên điện thoại Android, cắm cáp USB, bật Developer options và USB debugging, chấp nhận kết nối trên điện thoại rồi chạy:

```bash
flutter devices
flutter run -d <device-id>
```

Thay `<device-id>` bằng ID thiết bị được liệt kê, không gõ nguyên dấu `< >`. Có thể dùng ID Android Emulator đang chạy thay cho điện thoại thật.

Các lệnh trên dùng API mặc định `https://api.florabot.site`. Giao diện có thể mở trước; đăng nhập và chức năng dùng dữ liệu thật cần Backend có API Mobile đã được triển khai. Xem phần Chuẩn bị Backend bên dưới.

## Tiếp tục phát triển cùng nhóm

Tạo nhánh riêng trước khi sửa code:

```bash
git switch -c feature/mobile-ten-chuc-nang
```

Sau khi hoàn thành, kiểm tra, commit các file đã sửa và push nhánh đó:

```bash
flutter analyze
flutter test
git status
git add <cac-file-da-sua>
git commit -m "feat(mobile): mo ta chuc nang"
git push -u origin feature/mobile-ten-chuc-nang
```

Thay tên nhánh và `<cac-file-da-sua>` bằng giá trị thực tế; không commit mật khẩu, token, khóa ký hoặc cấu hình máy cá nhân. Tạo Pull Request để nhóm review và thống nhất nhánh đích trước khi merge.

## Hình ảnh thương hiệu

Ảnh trong `assets/images/` được dùng lại từ `FloraBot_FE/apps/web/public/images/generated/`: `florabot-hero.webp` cho màn hình chào/đăng nhập, `florabot-pattern.webp` cho nền trang đăng nhập, `florabot-step-stock.webp` cho trang tổng quan Seller/Staff và `florabot-process.png` cho thẻ hành trình hoa. App đóng gói ảnh cục bộ, không cần tải ảnh thương hiệu qua mạng. Các widget dùng chung nằm ở `lib/ui/brand.dart`.

## Chuẩn bị Backend

Triển khai nhánh `feature/mobile-token-auth` của repository FloraBot_BE trước khi đăng nhập Mobile. Bản app yêu cầu `/api/mobile/auth/*` và trường version/status trên chi tiết công việc. Không cần thay schema DB. Xem `FloraBot_BE/docs/mobile-auth.md`.

Push code không tự triển khai Backend. Nếu nhận 404 ở đăng nhập Mobile, cần kiểm tra bản Backend đã triển khai có endpoint tương ứng. Lỗi CORS là bước kiểm tra riêng, không chứng minh API đăng nhập chưa có.

## Chạy bằng PowerShell

```powershell
Set-Location 'D:\caption florabot\FloraBot_Mobile'
flutter pub get
flutter devices
flutter run --dart-define=API_BASE_URL=https://api.florabot.site
```

Chọn device Android trong danh sách hoặc thêm `-d <device-id>`. Cắm điện thoại, bật Developer options và USB debugging để chạy trên Android thật. Không cần lưu mật khẩu, OTP hay kiosk apiKey vào code.

Thử giao diện trên trình duyệt:

```powershell
flutter run -d chrome --web-hostname=localhost --web-port=57466 --dart-define=API_BASE_URL=https://api.florabot.site
```

Web preview không lưu phiên qua lần đóng tab. Backend phải cho phép đúng origin CORS để đăng nhập từ trình duyệt. Android/iOS không dùng cookie Web. API_BASE_URL phải là HTTPS origin, không có path/query/credentials. Nếu dùng HTTP local, chỉ cho bản debug với `--dart-define=ALLOW_LOCAL_HTTP=true`; cần cấu hình mạng riêng của nền tảng, không bật cleartext cho bản release.

## Khi Chrome báo lỗi CORS

Ví dụ: `No 'Access-Control-Allow-Origin' header` khi gọi API từ `http://localhost:57466`. Đây là trình duyệt chặn trước khi app nhận được phản hồi đăng nhập/đăng ký; nhập lại mật khẩu không giải quyết được.

1. Dừng Flutter Web rồi chạy lại bằng lệnh cổng cố định ở trên.
2. Người quản trị Backend đọc giá trị `ALLOWED_ORIGINS` đang dùng bởi FloraBot.Api, giữ nguyên các origin hiện có và thêm `http://localhost:57466` vào danh sách phân cách bằng dấu phẩy. Đây là cấu hình của **Backend**, không phải dart-define của app. Không thêm dấu `/` cuối origin. `localhost` và `127.0.0.1` là hai origin khác nhau.
3. Áp dụng cấu hình theo môi trường triển khai và khởi động lại ứng dụng API (recycle App Pool tương ứng nếu dùng IIS). Thay file `.env.example` trong repository không cập nhật server đang chạy.
4. Kiểm tra preflight mà không gửi tài khoản/mật khẩu:

```powershell
.\scripts\check-web-cors.ps1
```

Script kiểm tra OPTIONS cho đăng nhập và đăng ký, yêu cầu header cho đúng origin, POST và content-type/authorization. Chỉ có status 204 chưa đủ: phải có `Access-Control-Allow-Origin: http://localhost:57466`. Kiểm tra preflight đạt không thay thế việc kiểm tra endpoint đăng nhập thật.

Không tắt bảo mật Chrome, không dùng `no-cors` và không thay allowlist bằng `*`. Nếu chạy staging/local Backend, sửa cấu hình origin ở chính Backend đó và truyền `--dart-define=API_BASE_URL=https://<api-origin>` cho Flutter. Android/iOS native không chịu cơ chế CORS của trình duyệt; vẫn cần API, mạng và thông tin đăng nhập hợp lệ.

## Kiểm tra và build

```powershell
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug --dart-define=API_BASE_URL=https://api.florabot.site
```

APK thử ở `build\app\outputs\flutter-apk\app-debug.apk`. Đây là debug build; cấu hình ký release trong template chưa phải cấu hình phát hành store. Kotlin incremental đã tắt để tránh lỗi Windows khi Pub cache nằm C: và project nằm D:.

iOS cần macOS/Xcode, cấu hình signing và kiểm tra Keychain/camera/photo trên iPhone; chưa được build iOS trên Windows. Đã có project iOS và mô tả quyền camera/thư viện ảnh.

SDK đã kiểm tra trên máy: Flutter 3.51.0-0.1.pre (master), Dart 3.13.0-103.1.beta; đây là SDK sẵn có, không nâng cấp máy. Các dependency đã khóa yêu cầu Flutter >=3.44 và Dart >=3.12 <4; pubspec ghi cùng giới hạn. Cần xác minh lại trên Flutter stable đã chọn của nhóm trước CI/phát hành.

## Hành vi mạng và OTP

Mất mạng giữ phiên hiện tại; thao tác server báo lỗi và cho tải lại. Khi mở app offline với phiên lưu sẵn sẽ có màn hình chờ kết nối. Chỉ chủ động đăng xuất hoặc server xác nhận phiên hết hạn/thu hồi mới xóa phiên. Nếu một refresh bị consume trên server nhưng phản hồi mất, có thể cần đăng nhập lại sau lần xác minh kế tiếp; đây là giới hạn refresh một lần của BE, đã ghi trong kế hoạch.

OTP bảo trì 6 số lấy theo quyền từ BE; OTP nạp preorder/nhận hoa được gửi qua email theo API. App không gọi relay, không lưu OTP và không chứa khóa thiết bị. Cấp được OTP không đồng nghĩa cửa đã mở: phải kiểm tra trạng thái thật và phản hồi cảm biến.

Kiểm thử tự động dùng MockClient/fake Redis, không tác động DB hoặc thiết bị thật. Toàn bộ luồng role, mail, thanh toán và cửa cần nghiệm thu staging trước vận hành.
