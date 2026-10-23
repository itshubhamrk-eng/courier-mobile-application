/// Permission codes issued by courier-service (`LoginResponse.permissions`).
///
/// The app uses them only to hide actions a user cannot take; the server still
/// checks every call.
class Permissions {
  const Permissions._();

  static const dashboardRead = 'DASHBOARD_READ';
  static const shipmentCreate = 'SHIPMENT_CREATE';
  static const shipmentRead = 'SHIPMENT_READ';
  static const shipmentPrint = 'SHIPMENT_PRINT';
  static const manifestCreate = 'MANIFEST_CREATE';
  static const manifestRead = 'MANIFEST_READ';
  static const manifestDispatch = 'MANIFEST_DISPATCH';
  static const deliveryAssign = 'DELIVERY_ASSIGN';
  static const deliveryRead = 'DELIVERY_READ';
  static const deliveryDeliver = 'DELIVERY_DELIVER';
  static const deliveryUpload = 'DELIVERY_UPLOAD';
}
