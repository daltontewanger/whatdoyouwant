const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

const HERE_API_KEY = defineSecret("HERE_API_KEY");

const MONTHLY_LIMIT = 29500;
const CALLS_PER_SEARCH = 4;

function getMonthKey() {
    const now = new Date();
    return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
}

exports.fetchNearbyRestaurants = onCall(
    {
        secrets: [HERE_API_KEY],
        enforceAppCheck: true,

        cors: [
            "https://daltontewanger.github.io",
        ],
    },
    async (request) => {
        const { baseLat, baseLon } = request.data || {};

        if (typeof baseLat !== "number" || typeof baseLon !== "number") {
            throw new HttpsError("invalid-argument", "baseLat and baseLon are required.");
        }

        const db = admin.firestore();
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
                    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
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
            const response = await axios.get(
                "https://discover.search.hereapi.com/v1/discover",
                {
                    params: {
                        at: `${center.lat},${center.lon}`,
                        q: "restaurant",
                        limit: 100,
                        apiKey: HERE_API_KEY.value(),
                    },
                }
            );

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
    }
);