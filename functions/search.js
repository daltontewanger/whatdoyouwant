const { HttpsError } = require("firebase-functions/v2/https");

const MONTHLY_LIMIT = 29500;
const CALLS_PER_SEARCH = 4;

function getMonthKey() {
    const now = new Date();
    return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
}


function createSearchHandler({ db, serverTimestamp, discover }) {
    return async (request) => {
        const { baseLat, baseLon } = request.data || {};

        if (typeof baseLat !== "number" || typeof baseLon !== "number") {
            throw new HttpsError("invalid-argument", "baseLat and baseLon are required.");
        }


        const monthKey = getMonthKey();
        const usageRef = db.collection("hereUsage").doc(monthKey);

        await db.runTransaction(async (transaction) => {
            const snapshot = await transaction.get(usageRef);
            const currentCount = snapshot.exists ? snapshot.data().count || 0 : 0;

            if (currentCount + CALLS_PER_SEARCH > MONTHLY_LIMIT) {
                throw new HttpsError("resource-exhausted", "Monthly HERE API limit reached.");
            }

            transaction.set(
                usageRef,
                {
                    count: currentCount + CALLS_PER_SEARCH,
                    limit: MONTHLY_LIMIT,
                    updatedAt: serverTimestamp(),
                },
                { merge: true }
            );
        });

        const latOffset = 5.0 / 69.0;
        const lonOffset = 5.0 / (Math.cos((baseLat * Math.PI) / 180) * 69.0);

        const centers = [
            { lat: baseLat + latOffset, lon: baseLon },
            { lat: baseLat - latOffset, lon: baseLon },
            { lat: baseLat, lon: baseLon + lonOffset },
            { lat: baseLat, lon: baseLon - lonOffset },
        ];

        const allRestaurants = [];

        for (const center of centers) {
            const response = await discover({ at: `${center.lat},${center.lon}`, q: "restaurant", limit: 100 });

            const items = response.data.items || [];

            for (const item of items) {
                allRestaurants.push({
                    id: item.id,
                    name: item.title,
                    address: item.address?.label || "Address not available",
                    distance: Number(item.distance || 0) * 0.000621371,
                });
            }
        }

        const uniqueByName = {};

        for (const restaurant of allRestaurants) {
            const key = restaurant.name.toLowerCase();

            if (!uniqueByName[key] || restaurant.distance < uniqueByName[key].distance) {
                uniqueByName[key] = restaurant;
            }
        }

        return {
            restaurants: Object.values(uniqueByName),
            usageMonth: monthKey,
        };
    };
}

module.exports = { createSearchHandler };
