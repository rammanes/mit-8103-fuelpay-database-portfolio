// FuelPay Network: MongoDB queries.
db = db.getSiblingDB('fuelpay');
const show = (title, result) => { print('\n== ' + title + ' =='); printjson(result); };

// 1. Full history of one payment in a single read (no joins: the events are inside the document)
show('Q1. Full event history of payment PUR-00000007',
  db.payment_events.findOne({ transaction_ref: 'PUR-00000007' }, { _id: 0 }));

// 2. Two documents in the same collection with different shapes
show('Q2. A mobile app payment and an NFC tag payment have different fields',
  [db.payment_events.findOne({ channel: 'mobile_app' }, { _id: 0, transaction_ref: 1, channel: 1, device: 1, location: 1 }),
   db.payment_events.findOne({ channel: 'nfc_tag' }, { _id: 0, transaction_ref: 1, channel: 1, device: 1 })]);

// 3. Why payments are declined
show('Q3. Declined payments by reason',
  db.payment_events.aggregate([
    { $match: { outcome: 'declined' } },
    { $unwind: '$events' },
    { $match: { 'events.type': 'declined' } },
    { $group: { _id: '$events.reason', payments: { $sum: 1 } } },
    { $sort: { payments: -1 } }
  ]).toArray());

// 4. Approval rate and network timeouts per channel
show('Q4. Approval rate and timeouts per channel',
  db.payment_events.aggregate([
    { $group: {
        _id: '$channel',
        payments: { $sum: 1 },
        approved: { $sum: { $cond: [{ $eq: ['$outcome', 'approved'] }, 1, 0] } },
        with_timeout: { $sum: { $cond: [{ $in: ['network_timeout', '$events.type'] }, 1, 0] } } } },
    { $project: { payments: 1, with_timeout: 1, approval_rate_pct: { $round: [{ $multiply: [{ $divide: ['$approved', '$payments'] }, 100] }, 1] } } },
    { $sort: { _id: 1 } }
  ]).toArray());

// 5. Average seconds from first tap or scan to authorisation, per channel
show('Q5. Average seconds from start to authorisation, per channel',
  db.payment_events.aggregate([
    { $match: { outcome: 'approved' } },
    { $set: { auth: { $first: { $filter: { input: '$events', cond: { $eq: ['$$this.type', 'authorised'] } } } } } },
    { $group: { _id: '$channel', avg_seconds: { $avg: { $divide: [{ $subtract: ['$auth.at', '$started_at'] }, 1000] } } } },
    { $project: { avg_seconds: { $round: ['$avg_seconds', 1] } } },
    { $sort: { _id: 1 } }
  ]).toArray());

// 6. Pumps that raised alerts in the last 7 days (only some documents have an alerts field)
show('Q6. Pump alerts in the last 7 days',
  db.pump_telemetry.aggregate([
    { $match: { alerts: { $exists: true } } },
    { $unwind: '$alerts' },
    { $group: { _id: { station: '$station_code', pump: '$pump_no', alert: '$alerts.code' }, times: { $sum: 1 } } },
    { $sort: { times: -1, '_id.station': 1 } },
    { $limit: 10 }
  ]).toArray());

// 7. Average flow rate and tank level per pump model (tank level only exists on PX-300)
show('Q7. Readings per pump model',
  db.pump_telemetry.aggregate([
    { $group: { _id: '$device.model', readings: { $sum: 1 },
                avg_flow_lpm: { $avg: '$readings.flow_rate_lpm' },
                avg_tank_level_pct: { $avg: '$readings.tank_level_pct' } } },
    { $project: { readings: 1, avg_flow_lpm: { $round: ['$avg_flow_lpm', 1] }, avg_tank_level_pct: { $round: ['$avg_tank_level_pct', 1] } } },
    { $sort: { _id: 1 } }
  ]).toArray());

// 8. Index use: station activity lookup
const plan = db.payment_events.find({ station_code: 'STN-007', started_at: { $gte: new Date(Date.now() - 7 * 24 * 3600 * 1000) } })
  .explain('executionStats');
const stages = [];
for (let s = plan.queryPlanner.winningPlan; s; s = s.inputStage) stages.push(s.stage + (s.indexName ? ' (' + s.indexName + ')' : ''));
show('Q8. Plan for "station STN-007, last 7 days"', {
  plan: stages.join(' <- '),
  documents_returned: plan.executionStats.nReturned,
  documents_examined: plan.executionStats.totalDocsExamined,
  collection_size: db.payment_events.countDocuments()
});

// 9. The validation rule rejects a document with no events
try {
  db.payment_events.insertOne({ transaction_ref: 'BAD-1', account_number: 'FPC0000001', station_code: 'STN-001',
                                channel: 'nfc_card', started_at: new Date(), outcome: 'approved', events: [] });
  show('Q9. Insert a payment with no events', 'ACCEPTED (unexpected)');
} catch (e) {
  show('Q9. Insert a payment with no events', 'REJECTED: ' + e.errmsg);
}
