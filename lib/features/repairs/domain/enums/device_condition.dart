enum DeviceCondition { working, intermittent, notWorking, damaged }

extension DeviceConditionLabel on DeviceCondition {
  String get arabicLabel {
    switch (this) {
      case DeviceCondition.working:
        return 'يعمل';
      case DeviceCondition.intermittent:
        return 'يعمل بشكل متقطع';
      case DeviceCondition.notWorking:
        return 'لا يعمل';
      case DeviceCondition.damaged:
        return 'متضرر';
    }
  }
}
