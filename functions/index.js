const functions = require("firebase-functions");
const https = require("https");
const cors = require("cors")({origin: true});

exports.googleApiProxy = functions.https.onRequest((request, response) => {
  cors(request, response, () => {
    // Get the full Google API URL from the request query parameters.
    const googleApiUrl = request.query.url;

    if (!googleApiUrl) {
      return response.status(400).send("Missing 'url' query parameter.");
    }

    https.get(googleApiUrl, (apiResponse) => {
      let data = "";
      apiResponse.on("data", (chunk) => {
        data += chunk;
      });
      apiResponse.on("end", () => {
        response.status(200).send(data);
      });
    }).on("error", (err) => {
      functions.logger.error("Error calling Google API:", err);
      response.status(500).send("Failed to call Google API.");
    });
  });
});
