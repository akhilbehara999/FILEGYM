import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConversionQualityNotifier extends Notifier<double> {
  @override
  double build() {
    return 80.0;
  }

  void setQuality(double value) {
    state = value;
  }
}

final conversionQualityProvider = NotifierProvider<ConversionQualityNotifier, double>(ConversionQualityNotifier.new);

class SoundAlertsNotifier extends Notifier<bool> {
  @override
  bool build() {
    return true;
  }

  void setEnabled(bool value) {
    state = value;
  }
}

final soundAlertsProvider = NotifierProvider<SoundAlertsNotifier, bool>(SoundAlertsNotifier.new);

class PushNotificationsNotifier extends Notifier<bool> {
  @override
  bool build() {
    return true;
  }

  void setEnabled(bool value) {
    state = value;
  }
}

final pushNotificationsProvider = NotifierProvider<PushNotificationsNotifier, bool>(PushNotificationsNotifier.new);
