const { onCall } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { createSearchHandler } = require("./search");

initializeApp();
const HERE_API_KEY = defineSecret("HERE_API_KEY");
const axios = require("axios");
const options = {
    secrets: [HERE_API_KEY],
    enforceAppCheck: true,
    cors: ["https://daltontewanger.github.io"],
};
const discover = (params) => axios.get("https://discover.search.hereapi.com/v1/discover", {
    params: { ...params, apiKey: HERE_API_KEY.value() },
});

exports.fetchNearbyRestaurants = onCall(options, createSearchHandler({
    db: getFirestore(),
    serverTimestamp: () => FieldValue.serverTimestamp(),
    discover,
}));
