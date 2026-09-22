// Deterministic 0-100 health score for a device, computed on request from its
// stored snapshots (nothing is persisted). The weights differ per device
// type because laptops report real battery capacity and phones only a
// coarse health enum.

const WEIGHTS = {
  laptop: { battery: 35, storage: 20, memory: 15, thermal: 10, habits: 20 },
  phone: { battery: 30, storage: 20, memory: 15, thermal: 20, habits: 15 },
};

// Charging habits need real history to mean anything. Below either threshold
// the component is NOT measured: it falls back to this neutral placeholder and
// the result says so, so the app can show it to the user.
const NEUTRAL_HABITS_SCORE = 70;
const MIN_HISTORY_SNAPSHOTS = 10;
const MIN_HISTORY_HOURS = 24;

const HOT_PHONE_TENTHS_C = 400; // 40 C battery temperature
const HOT_THERMAL_LEVELS = new Set(["FAIR", "SERIOUS", "MODERATE", "SEVERE", "CRITICAL", "EMERGENCY", "SHUTDOWN"]);

// Android BatteryManager.EXTRA_HEALTH -> score.
const HEALTH_ENUM_SCORE = { 2: 100, 7: 70, 3: 40, 5: 30, 6: 20, 4: 0 };
const HEALTH_ENUM_NAME = { 2: "Good", 3: "Overheat", 4: "Dead", 5: "Over voltage", 6: "Failure", 7: "Cold" };
const UNKNOWN_HEALTH_SCORE = 60;

// Android PowerManager thermal statuses plus macOS ProcessInfo thermal states.
const THERMAL_STATUS_SCORE = {
  NONE: 100,
  NOMINAL: 100,
  LIGHT: 80,
  FAIR: 80,
  MODERATE: 60,
  SERIOUS: 40,
  SEVERE: 30,
  CRITICAL: 10,
  EMERGENCY: 0,
  SHUTDOWN: 0,
};

const clamp = (n, lo = 0, hi = 100) => Math.min(hi, Math.max(lo, n));
const round = (n) => Math.round(n);
const toNumber = (v) => (v == null ? null : Number(v));

function capacityRatio(s) {
  const full = toNumber(s.fullChargeCapacityMah);
  const design = toNumber(s.designCapacityMah);
  if (!full || !design) return null;
  return full / design;
}

function scoreBattery(profile, s) {
  if (profile === "laptop") {
    const ratio = capacityRatio(s);
    if (ratio == null) return unavailable("No battery capacity reported yet");
    const healthPct = Math.min(ratio, 1) * 100;
    const cycles = s.cycleCount;
    const penalty = cycles == null ? 0 : Math.min(15, Math.max(0, cycles - 300) * 0.03);
    return measured(
      clamp(healthPct - penalty),
      `${round(healthPct)}% of design capacity${cycles == null ? "" : `, ${cycles} charge cycles`}`
    );
  }
  if (s.healthEnum == null) return unavailable("No battery health reported yet");
  const known = s.healthEnum in HEALTH_ENUM_SCORE;
  return measured(
    known ? HEALTH_ENUM_SCORE[s.healthEnum] : UNKNOWN_HEALTH_SCORE,
    `Android reports battery health: ${HEALTH_ENUM_NAME[s.healthEnum] ?? "Unknown"}`
  );
}

// Free space at or above `fullMarkFraction` scores 100, scaling linearly to 0.
function scoreFreeFraction(free, total, fullMarkFraction, what) {
  const f = toNumber(free);
  const t = toNumber(total);
  if (f == null || !t) return unavailable(`No ${what} reading yet`);
  const fraction = clamp(f / t, 0, 1);
  return measured(
    clamp((fraction / fullMarkFraction) * 100),
    `${round(fraction * 100)}% free (100 needs at least ${round(fullMarkFraction * 100)}% free)`
  );
}

function scoreThermal(s) {
  const parts = [];
  const notes = [];
  if (s.temperatureTenthsC != null) {
    const c = s.temperatureTenthsC / 10;
    // 35 C or cooler is fine, 50 C or hotter scores 0.
    parts.push(clamp(100 - (c - 35) * (100 / 15)));
    notes.push(`battery ${c.toFixed(1)}°C`);
  }
  const level = s.thermalStatus ? String(s.thermalStatus).toUpperCase() : null;
  if (level && level in THERMAL_STATUS_SCORE) {
    parts.push(THERMAL_STATUS_SCORE[level]);
    notes.push(`system thermal state ${level.toLowerCase()}`);
  }
  if (!parts.length) return unavailable("This device does not report temperature or thermal state");
  return measured(Math.min(...parts), notes.join(", "));
}

function isHot(s) {
  if (s.temperatureTenthsC != null) return s.temperatureTenthsC >= HOT_PHONE_TENTHS_C;
  if (s.thermalStatus) return HOT_THERMAL_LEVELS.has(String(s.thermalStatus).toUpperCase());
  return null; // this snapshot carries no heat signal
}

// Plain history statistics (oldest -> newest snapshots). Shared by the habits
// score and by the AI summary, which is given trends, not raw readings.
function computeTrend(profile, snapshots) {
  const count = snapshots.length;
  const spanHours = count > 1 ? (snapshots[count - 1].capturedAt - snapshots[0].capturedAt) / 36e5 : 0;

  let hotChargingSharePct = null;
  const withHeat = snapshots.filter((s) => isHot(s) !== null && s.isCharging != null);
  if (withHeat.length >= MIN_HISTORY_SNAPSHOTS) {
    const hotCharging = withHeat.filter((s) => s.isCharging && isHot(s)).length;
    hotChargingSharePct = (hotCharging / withHeat.length) * 100;
  }

  let capacityDropPct = null;
  const withCapacity = snapshots.filter((s) => capacityRatio(s) != null);
  if (profile === "laptop" && withCapacity.length >= 4) {
    const avg = (arr) => arr.reduce((a, s) => a + capacityRatio(s), 0) / arr.length;
    capacityDropPct = Math.max(0, (avg(withCapacity.slice(0, 3)) - avg(withCapacity.slice(-3))) * 100);
  }

  return { snapshotCount: count, spanHours, hotChargingSharePct, capacityDropPct };
}

// `snapshots` is oldest -> newest.
function scoreHabits(profile, snapshots) {
  const trend = computeTrend(profile, snapshots);
  const count = trend.snapshotCount;
  const spanHours = trend.spanHours;
  const enough = count >= MIN_HISTORY_SNAPSHOTS && spanHours >= MIN_HISTORY_HOURS;

  const placeholder = (reason) => ({
    score: NEUTRAL_HABITS_SCORE,
    status: "placeholder",
    note: reason,
  });

  if (!enough) {
    return placeholder(
      `Not enough history yet: ${count} snapshot${count === 1 ? "" : "s"} over ${spanHours.toFixed(1)} hours ` +
        `(needs at least ${MIN_HISTORY_SNAPSHOTS} over ${MIN_HISTORY_HOURS} hours). ` +
        `A neutral ${NEUTRAL_HABITS_SCORE} is shown as a placeholder. It is not measured from your usage.`
    );
  }

  const signals = [];
  const notes = [];

  if (trend.hotChargingSharePct != null) {
    signals.push(clamp(100 - trend.hotChargingSharePct * 2));
    notes.push(`${round(trend.hotChargingSharePct)}% of readings were taken while charging and hot`);
  }
  if (trend.capacityDropPct != null) {
    signals.push(clamp(100 - trend.capacityDropPct * 20));
    notes.push(
      `battery capacity drifted down ${trend.capacityDropPct.toFixed(1)} percentage points over ${round(spanHours)} hours`
    );
  }

  if (!signals.length) {
    return placeholder(
      `Enough history (${count} snapshots over ${round(spanHours)} hours) but this device does not report the ` +
        `signals needed (charging state with temperature, or battery capacity). ` +
        `A neutral ${NEUTRAL_HABITS_SCORE} is shown as a placeholder. It is not measured from your usage.`
    );
  }
  return measured(signals.reduce((a, b) => a + b, 0) / signals.length, notes.join("; "));
}

function measured(score, note) {
  return { score: round(score), status: "measured", note };
}

function unavailable(note) {
  return { score: null, status: "unavailable", note };
}

const NAMES = {
  battery: "Battery",
  storage: "Storage",
  memory: "Memory",
  thermal: "Thermal",
  habits: "Charging habits",
};

/**
 * @param device    { deviceType: "phone" | "laptop" }
 * @param snapshots array of snapshot rows, oldest -> newest, non-empty
 */
function computeScore(device, snapshots) {
  const profile = device.deviceType === "laptop" ? "laptop" : "phone";
  const latest = snapshots[snapshots.length - 1];

  const results = {
    battery: scoreBattery(profile, latest),
    storage: scoreFreeFraction(latest.storageFreeBytes, latest.storageTotalBytes, 0.3, "storage"),
    memory: scoreFreeFraction(latest.ramFreeBytes, latest.ramTotalBytes, 0.2, "memory"),
    thermal: scoreThermal(latest),
    habits: scoreHabits(profile, snapshots),
  };

  const weights = WEIGHTS[profile];
  const components = Object.keys(weights).map((key) => ({
    key,
    name: NAMES[key],
    weight: weights[key],
    ...results[key],
  }));

  // Components a device cannot report at all are left out and the remaining
  // weights are rescaled. The habits placeholder stays IN the total (that is
  // the neutral 70) but is flagged so the app can say so.
  const counted = components.filter((c) => c.score != null);
  const weightSum = counted.reduce((a, c) => a + c.weight, 0);
  const total = weightSum ? round(counted.reduce((a, c) => a + c.score * c.weight, 0) / weightSum) : null;

  const notices = [];
  const habits = components.find((c) => c.key === "habits");
  if (habits.status === "placeholder") {
    notices.push(habits.note);
  }
  for (const c of components) {
    if (c.status === "unavailable") {
      notices.push(`${c.name} is left out of the total: ${c.note}.`);
    }
  }

  return {
    deviceId: latest.deviceId,
    profile,
    total,
    // true when part of the total is the neutral placeholder rather than a measurement
    includesPlaceholder: habits.status === "placeholder",
    components,
    notices,
    basedOn: {
      snapshotCount: snapshots.length,
      firstSnapshotAt: snapshots[0].capturedAt,
      latestSnapshotAt: latest.capturedAt,
    },
    computedAt: new Date(),
  };
}

module.exports = { computeScore, computeTrend, NEUTRAL_HABITS_SCORE, MIN_HISTORY_SNAPSHOTS, MIN_HISTORY_HOURS };
