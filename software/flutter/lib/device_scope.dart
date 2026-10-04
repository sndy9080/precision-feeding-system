import 'package:firebase_database/firebase_database.dart';

class DeviceScope {
  const DeviceScope(this.id);

  final String id;

  DatabaseReference get ref => FirebaseDatabase.instance.ref('devices/$id');
}
