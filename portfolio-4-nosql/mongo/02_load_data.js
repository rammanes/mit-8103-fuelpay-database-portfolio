// FuelPay Network: sample documents. Codes match the PostgreSQL data from Portfolio 1
// (accounts FPC0000001-FPC0000200, stations STN-001 to STN-020, payments PUR-00000001 onwards).
db = db.getSiblingDB('fuelpay');
db.payment_events.deleteMany({});
db.pump_telemetry.deleteMany({});

// Simple seeded random numbers so every run produces the same documents
let seed = 42;
const rand = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const pick = arr => arr[Math.floor(rand() * arr.length)];
const pad = (n, w) => String(n).padStart(w, '0');
const now = new Date();
const minutesAfter = (d, m) => new Date(d.getTime() + m * 60000);

// ---------------------------------------------------------------- payment_events
const payments = [];
for (let i = 1; i <= 2000; i++) {
  const started = new Date(now.getTime() - rand() * 30 * 24 * 3600 * 1000);
  const station = 'STN-' + pad(1 + Math.floor(rand() * 20), 3);
  const r = rand();
  const channel = r < 0.6 ? 'nfc_card' : r < 0.85 ? 'nfc_tag' : 'mobile_app';
  const declined = rand() < 0.08;
  const doc = {
    transaction_ref: 'PUR-' + pad(i, 8),
    account_number: 'FPC' + pad(1 + Math.floor(rand() * 200), 7),
    station_code: station,
    channel: channel,
    started_at: started,
    outcome: declined ? 'declined' : 'approved',
    events: []
  };

  // Each channel records different device details and different steps
  if (channel === 'mobile_app') {
    doc.device = { platform: pick(['android', 'ios']), app_version: pick(['2.3.1', '2.4.0']),
                   phone_model: pick(['Tecno Spark 20', 'Infinix Hot 40', 'Samsung A15', 'iPhone 13']) };
    doc.location = { type: 'Point', coordinates: [3 + rand() * 5, 6 + rand() * 6] };
    doc.events.push({ type: 'app_opened', at: started });
    doc.events.push({ type: 'qr_scanned', at: minutesAfter(started, 0.2), pump_no: 1 + Math.floor(rand() * 6) });
    doc.events.push({ type: 'otp_verified', at: minutesAfter(started, 0.6) });
  } else {
    doc.device = { reader_id: 'RDR-' + station.slice(4) + '-' + (1 + Math.floor(rand() * 4)), firmware: pick(['3.1.4', '3.2.0']) };
    if (channel === 'nfc_tag') doc.device.vehicle_plate = 'FP' + pad(1 + Math.floor(rand() * 40), 3) + 'KJA';
    doc.events.push({ type: channel === 'nfc_card' ? 'card_tapped' : 'tag_read', at: started });
    if (channel === 'nfc_card') doc.events.push({ type: 'pin_entered', at: minutesAfter(started, 0.25) });
  }

  // Seconds to authorise: tags are fastest, cards need a PIN, the app needs an OTP
  let seconds = channel === 'nfc_tag' ? 5 + rand() * 10 : channel === 'nfc_card' ? 20 + rand() * 20 : 50 + rand() * 40;
  // Some requests time out and are retried with the same transaction_ref, which adds about 30 seconds
  if (rand() < 0.1) {
    doc.events.push({ type: 'network_timeout', at: minutesAfter(started, seconds / 60), retry_count: 1 });
    seconds += 30;
  }
  const authAt = minutesAfter(started, seconds / 60);
  if (declined) {
    doc.events.push({ type: 'declined', at: authAt, reason: pick(['insufficient_funds', 'insufficient_funds', 'card_blocked', 'allowance_exceeded']) });
  } else {
    const litres = Math.round((5 + rand() * 45) * 100) / 100;
    doc.events.push({ type: 'authorised', at: authAt });
    doc.events.push({ type: 'pump_started', at: minutesAfter(authAt, 0.5) });
    doc.events.push({ type: 'pump_stopped', at: minutesAfter(authAt, 3), litres: litres });
    if (channel !== 'mobile_app') doc.events.push({ type: 'receipt_printed', at: minutesAfter(authAt, 3.2) });
  }
  payments.push(doc);
}
db.payment_events.insertMany(payments);

// ---------------------------------------------------------------- pump_telemetry
const telemetry = [];
for (let i = 0; i < 1000; i++) {
  const model = pick(['PX-100', 'PX-200', 'PX-300']);
  const doc = {
    station_code: 'STN-' + pad(1 + Math.floor(rand() * 20), 3),
    pump_no: 1 + Math.floor(rand() * 6),
    recorded_at: new Date(now.getTime() - rand() * 7 * 24 * 3600 * 1000),
    device: { model: model, firmware: model === 'PX-300' ? '5.0.2' : '4.8.1' },
    readings: { flow_rate_lpm: Math.round((30 + rand() * 20) * 10) / 10 }
  };
  // Newer models send extra readings
  if (model !== 'PX-100') doc.readings.nozzle_temp_c = Math.round((25 + rand() * 15) * 10) / 10;
  if (model === 'PX-300') doc.readings.tank_level_pct = Math.round(rand() * 1000) / 10;
  if (model === 'PX-300' && doc.readings.tank_level_pct < 15) {
    doc.alerts = [{ code: 'LOW_TANK', level: 'warning' }];
  }
  if (rand() < 0.02) {
    (doc.alerts = doc.alerts || []).push({ code: 'METER_DRIFT', level: 'critical' });
  }
  telemetry.push(doc);
}
db.pump_telemetry.insertMany(telemetry);

print('payment_events: ' + db.payment_events.countDocuments());
print('pump_telemetry: ' + db.pump_telemetry.countDocuments());
