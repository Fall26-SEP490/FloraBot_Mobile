typedef Json = Map<String, dynamic>;

Json objectOf(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  throw const FormatException('Dữ liệu máy chủ không đúng định dạng.');
}

List<Json> itemsOf(dynamic value) {
  final data = value is List ? value : objectOf(value)['items'];
  if (data is! List) {
    throw const FormatException('Không đọc được danh sách từ máy chủ.');
  }
  return data.map(objectOf).toList();
}

enum AppRole {
  technician('TECHNICIAN', 'Kỹ thuật viên', 'Kiểm tra, lắp đặt và sửa tủ'),
  staff('SELLER_STAFF', 'Nhân viên shop', 'Nhận việc và nạp hoa đúng ô'),
  seller('SELLER', 'Chủ shop', 'Vận hành tủ và đơn đặt trước'),
  customer('CUSTOMER', 'Khách đặt trước', 'Đặt hoa và theo dõi lịch nhận');

  const AppRole(this.code, this.label, this.description);
  final String code, label, description;
  static AppRole parse(String code) => values.firstWhere(
    (r) => r.code == code,
    orElse: () => throw const FormatException(
      'Vai trò này không được hỗ trợ trong ứng dụng.',
    ),
  );
}

class Session {
  Session.fromJson(Json json)
    : id = json['id'] as String,
      name = json['name'] as String,
      role = AppRole.parse(json['role'] as String),
      sellerId = json['sellerId'] as String?,
      sellerStatus = json['sellerStatus'] as String? {
    if ((role == AppRole.seller || role == AppRole.staff) && sellerId == null) {
      throw const FormatException(
        'Tài khoản chưa được liên kết với shop hợp lệ.',
      );
    }
  }
  final String id, name;
  final AppRole role;
  final String? sellerId, sellerStatus;
}

String valueOf(Json row, String key, [String fallback = 'Chưa có']) =>
    row[key] == null || row[key].toString().isEmpty
    ? fallback
    : row[key].toString();

const statusLabels = {
  'ASSIGNED': 'Đã giao',
  'IN_PROGRESS': 'Đang thực hiện',
  'SUBMITTED': 'Chờ duyệt',
  'COMPLETED': 'Hoàn tất',
  'CANCELLED': 'Đã hủy',
  'ACTIVE': 'Hoạt động',
  'DISABLED': 'Đã khóa',
  'PAST_DUE': 'Quá hạn',
  'ONLINE': 'Trực tuyến',
  'OFFLINE': 'Ngoại tuyến',
  'STOCKED': 'Đang có hoa',
  'RENTED_EMPTY': 'Ô trống',
  'LOCKED': 'Đang giữ để xử lý',
  'FAULT': 'Có sự cố',
  'PENDING_REMOVAL': 'Chờ thu hồi',
  'HELD': 'Đang được giữ',
  'AwaitRemoval': 'Chờ lấy hoa cũ',
  'AwaitLoading': 'Chờ nạp hoa',
  'Completed': 'Hoàn tất',
  'NeedsInspection': 'Cần kiểm tra',
  'PAID': 'Đã thanh toán',
  'AWAITING_PAYMENT': 'Chờ thanh toán',
  'DISPENSING': 'Đang giao hoa',
  'DISPENSE_FAILED': 'Chưa giao được hoa',
  'REFUNDED': 'Đã hoàn tiền',
  'REQUESTED': 'Đã gửi yêu cầu',
  'QUOTED': 'Đã báo giá',
  'ACCEPTED': 'Đã chấp nhận',
  'REJECTED': 'Đã từ chối',
  'EXPIRED': 'Đã hết hạn',
  'FULFILLED': 'Đã nạp hoa',
};
String statusText(dynamic status) =>
    statusLabels[status] ?? status?.toString() ?? 'Chưa xác định';
