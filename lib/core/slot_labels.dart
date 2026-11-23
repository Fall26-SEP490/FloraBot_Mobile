import 'models.dart';

bool slotOrderBlocked(Json slot) =>
    slot['bouquetStatus'] == 'HELD' ||
    slot['bouquetStatus'] == 'SOLD' ||
    [
      'AWAITING_PAYMENT',
      'PAID',
      'DISPENSING',
      'DISPENSE_FAILED',
    ].contains(slot['orderStatus']);

String slotZoneLabel(dynamic zone) => switch (zone) {
  'WALK_IN' => 'Tại chỗ',
  'PREORDER' => 'Đặt trước',
  _ => 'Chưa phân loại',
};
String slotStateLabel(Json slot) {
  if (slot['status'] == 'LOCKED') {
    final stage = slot['maintenanceStage'];
    if (stage == 'NeedsInspection') return 'Cần kiểm tra ô';
    if (slot['doorState'] == 'OPEN') return 'Cửa đang mở';
    if (stage == 'AwaitLoading' || stage == 'AwaitRemoval') {
      if (slot['doorState'] == 'CLOSED') {
        return stage == 'AwaitLoading'
            ? 'Đang xác nhận nạp'
            : 'Đang xác nhận thu hồi';
      }
      return 'Chờ mở cửa';
    }
  }
  if (slot['orderStatus'] == 'DISPENSE_FAILED') {
    return 'Nhận hoa thất bại — cần xử lý';
  }
  if (slot['bouquetStatus'] == 'SOLD' && slot['paymentStatus'] == 'SUCCEEDED') {
    if (slot['orderStatus'] == 'PAID') return 'Đã bán — chờ khách nhận';
    if (slot['orderStatus'] == 'DISPENSING') {
      return 'Đã bán — đang xử lý nhận hoa';
    }
  }
  if (slot['bouquetStatus'] == 'HELD' &&
      slot['orderStatus'] == 'AWAITING_PAYMENT' &&
      slot['paymentStatus'] == 'PENDING') {
    return 'Khách đang thanh toán';
  }
  if (slot['status'] == 'STOCKED' &&
      slot['bouquetStatus'] == 'STOCKED' &&
      slot['orderId'] == null &&
      slot['orderCode'] == null &&
      slot['orderStatus'] == null) {
    return 'Đang bán';
  }
  if (slot['status'] == 'RENTED_EMPTY') {
    return slot['bouquetId'] == null ? 'Ô trống' : 'Cần kiểm tra dữ liệu ô';
  }
  const labels = {
    'FREE': 'Chưa cho thuê',
    'STOCKED': 'Đã nạp hoa',
    'HELD': 'Ô đang được giữ',
    'PENDING_REMOVAL': 'Chờ thu hồi hoa',
    'PENDING_RELEASE': 'Chờ lấy hoa về để trả ô',
    'FAULT': 'Có sự cố',
    'LOCKED': 'Đang khóa',
  };
  return labels[slot['status']] ?? statusText(slot['status']);
}
