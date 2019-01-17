// @author Alejandro Galue <agalue@opennms.org>

const axios = require('axios');
const fs = require('fs');

var slackUrl = fs.readFileSync('/configs/default/alarms2kafka-config/SLACK_URL', 'utf8');

module.exports = async function(context) {
  const alarm = context.request.body;
  console.log('Processing alarm with ID ' + alarm.id);
  try {
    const response = await axios.post(slackUrl, {
      text: alarm.logMessage
    });
    console.log(response.statusText);
    return { status: 200, body: response.statusText };
  } catch (error) {
    console.error(error);
    return { status: 500, body: JSON.stringify(error) };
  }
}
