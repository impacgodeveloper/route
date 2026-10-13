/// Centralized honest wording for simulated behaviour. Use these strings
/// instead of ad-hoc copies so every workspace says the same thing.
abstract final class DemoLabels {
  static const demoData = 'DEMO DATA';
  static const localOnly =
      'Prototype — all data is stored locally on this device.';
  static const simulatedLocation = 'Simulated location · not a real GPS fix';
  static const schematicMap =
      'Schematic route · fictional demo coordinates, not a real map';
  static const sosDemo =
      'Demo only — no real emergency service or control room was contacted.';
  static const sosAlternative =
      'In a real emergency call 112 (India emergency number) directly from your phone.';
  static const incidentDemo =
      'Recorded locally for the Fleet Manager console. Not sent to a real control room.';
  static const credentialDemo =
      'Demo credential · not valid for real travel or access';
  static const optimizer =
      'Local demo optimizer · deterministic heuristic, not OR-Tools or production AI';
  static const notificationDemo =
      'Local in-app notification · no SMS or push message was sent';
  static const paymentDemo = 'Demo status only · no payment was processed';
  static const launcherNotAuth =
      'Workspace selection is a demo convenience and is not real authorization.';
  static const trafficSimulated =
      'Simulated demo traffic · not live traffic data';
  static const invoiceDemo =
      'Generated locally (demo) · not emailed, submitted to an accounting system or paid';
  static const auditNotTamperProof =
      'Local prototype audit trail · not tamper-proof';
  static const fictionalCoordinates =
      'Fictional demo coordinates · not real locations';
  static const controlRoomDemo =
      'Simulated control-room contact · no call was placed';
}
