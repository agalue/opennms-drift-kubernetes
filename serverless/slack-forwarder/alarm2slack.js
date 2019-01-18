// @author Alejandro Galue <agalue@opennms.org>

const axios = require('axios');
const fs = require('fs');

const configPath = '/configs/default/alarms2kafka-config/SLACK_URL';

var slackUrl;
if (fs.existsSync(configPath)) {
  slackUrl = fs.readFileSync(configPath);
  console.log('Slack URL: ' + slackUrl);
}

module.exports = async function(context) {
  if (slackUrl === undefined) {
    return { status: 404, body: 'The slackUrl is not defined on the config-map.' };
  }
  try {
    const alarm = context.request.body;
    console.log('Posting alarm with ID ' + alarm.id + ' to ' + slackUrl);
    const response = await axios.post(slackUrl, {
      text: alarm.logMessage
    });
    console.log(response.statusText);
    return { status: 200, body: response.statusText };
  } catch (error) {
    console.error(error);
    return { status: 500, body: 'ERROR: something went wrong. ' + error };
  }
}
