import 'package:flutter/material.dart';

import 'app/app.dart';

/// Executive Fleet Mobility — frontend prototype with four connected
/// workspaces (Employee, Driver, Employer Admin, Fleet Manager Admin)
/// sharing one local database. No production backend in this phase.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BootstrapApp());
}
