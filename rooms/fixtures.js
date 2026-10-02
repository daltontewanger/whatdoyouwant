// Fictional restaurants used until a reviewed provider and cost controls exist.
// Nothing here comes from or is sent to a real provider.
const fixtureCandidates = Object.freeze([
  { id: 'fixture-pizza', title: 'Demo Pizza', address: '1 Example Street', distanceMiles: 0.25 },
  { id: 'fixture-tacos', title: 'Demo Tacos', address: '2 Example Street', distanceMiles: 0.5 },
  { id: 'fixture-noodles', title: 'Demo Noodles', address: '3 Example Street', distanceMiles: 0.75 },
  { id: 'fixture-salad', title: 'Demo Salad', address: '4 Example Street', distanceMiles: 1 },
  { id: 'fixture-cafe', title: 'Demo Cafe', address: '5 Example Street', distanceMiles: 1.25 },
]);

module.exports = { fixtureCandidates };
