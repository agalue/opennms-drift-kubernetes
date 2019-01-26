// @author Alejandro Galue <agalue@opennms.org>

// Deployment:
// zip pod2slack.zip package.json pod.js
// fission function create --name pod2slack --src pod2slack.zip --env nodejs --configmap serverless-config
// fission watch create --function pod2slack --type pod --ns opennms

// Future Enhancements:
// Update an OpenNMS requisition to monitor Pods (requires access to Kubernetes API)

const axios = require('axios');
const fs = require('fs');

const configPath = '/configs/default/serverless-config/SLACK_URL';

var slackUrl;
if (fs.existsSync(configPath)) {
  slackUrl = fs.readFileSync(configPath,'utf8');
  console.log('Slack URL: ' + slackUrl);
}

module.exports = async function(context) {
  if (slackUrl === undefined) {
    return { status: 404, body: 'The slackUrl is not defined on the config-map.' };
  }
  try {
    let obj = context.request.body;
    let version = obj.metadata.resourceVersion;
    let eventType = context.request.get('X-Kubernetes-Event-Type');
    let objType = context.request.get('X-Kubernetes-Object-Type');
    let text = `${eventType} ${objType} ${obj.metadata.name} (version ${version})`;
    console.log(text);
    const response = await axios.post(slackUrl, { text });
    console.log(response.statusText);
    return { status: 200, body: response.statusText };
  } catch (error) {
    console.error(error);
    return { status: 500, body: 'ERROR: something went wrong. ' + error };
  }
}
