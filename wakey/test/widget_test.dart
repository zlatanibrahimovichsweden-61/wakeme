import 'package:flutter_test/flutter_test.dart';
import 'package:wakey/core/models/destination_model.dart';

void main() {
  test('DestinationModel round-trips through JSON', () {
    final DestinationModel original = DestinationModel.create(
      name: 'Cairo',
      address: 'Tahrir Square',
      lat: 30.0444,
      lng: 31.2357,
      iconName: 'home',
    );
    final DestinationModel copy =
        DestinationModel.fromJson(original.toJson());
    expect(copy.name, original.name);
    expect(copy.lat, original.lat);
    expect(copy.lng, original.lng);
    expect(copy.iconName, original.iconName);
  });
}
