// Local harness only; not included in the production Functions source directory.
const PROJECT = "demo-whatdoyouwant";

function assertLocalEnvironment(env) {
    if (env.GCLOUD_PROJECT !== PROJECT || env.FUNCTIONS_EMULATOR !== "true" ||
        env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:8080" ||
        env.FIREBASE_AUTH_EMULATOR_HOST !== "127.0.0.1:9099") {
        throw new Error("Local tests require the demo project and loopback Auth/Firestore/Functions emulators.");
    }
    if (env.GOOGLE_APPLICATION_CREDENTIALS || env.HERE_API_KEY) {
        throw new Error("Remove cloud credentials and HERE_API_KEY from the local-test process.");
    }
}

// Fictional fixtures only: no HTTP client or secret access.
async function discover() {
    return { data: { items: [
        { id: "fixture-pizza", title: "Demo Pizza", address: { label: "1 Example Street" }, distance: 400 },
        { id: "fixture-tacos", title: "Demo Tacos", address: { label: "2 Example Street" }, distance: 800 },
        { id: "fixture-noodles", title: "Demo Noodles", address: { label: "3 Example Street" }, distance: 1200 },
        { id: "fixture-salad", title: "Demo Salad", address: { label: "4 Example Street" }, distance: 1600 },
        { id: "fixture-cafe", title: "Demo Cafe", address: { label: "5 Example Street" }, distance: 2000 },
    ] } };
}

module.exports = { PROJECT, assertLocalEnvironment, discover };
