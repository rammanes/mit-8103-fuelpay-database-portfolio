// FuelPay Network: MongoDB collections, validation rules and indexes. Safe to re-run.
db = db.getSiblingDB('fuelpay');
db.payment_events.drop();
db.pump_telemetry.drop();

// One document per payment attempt, holding its full event history from the card reader or app.
// transaction_ref is the idempotency_key of the matching PostgreSQL transaction.
db.createCollection('payment_events', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['transaction_ref', 'account_number', 'station_code', 'channel', 'started_at', 'outcome', 'events'],
      properties: {
        transaction_ref: { bsonType: 'string' },
        channel: { enum: ['nfc_card', 'nfc_tag', 'mobile_app'] },
        outcome: { enum: ['approved', 'declined'] },
        events: {
          bsonType: 'array',
          minItems: 1,
          items: { bsonType: 'object', required: ['type', 'at'] }
        }
      }
    }
  }
});

// One document per pump reading. Different pump models report different fields.
db.createCollection('pump_telemetry', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['station_code', 'pump_no', 'recorded_at', 'device', 'readings'],
      properties: { pump_no: { bsonType: 'number', minimum: 1 } }
    }
  }
});

db.payment_events.createIndex({ transaction_ref: 1 }, { unique: true });
db.payment_events.createIndex({ station_code: 1, started_at: -1 });
db.pump_telemetry.createIndex({ station_code: 1, recorded_at: -1 });

print('Collections: ' + db.getCollectionNames().sort().join(', '));
print('payment_events indexes: ' + db.payment_events.getIndexes().map(i => i.name).join(', '));
print('pump_telemetry indexes: ' + db.pump_telemetry.getIndexes().map(i => i.name).join(', '));
