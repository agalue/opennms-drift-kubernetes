// @author Alejandro Galue <agalue@opennms.org>
//
// Inspiration:
// https://github.com/fission/fission/blob/master/examples/nodejs/kubeEventsSlack.js
//
// Deployment:
// zip pod2slack.zip package.json pod2slack.js
// fission environment create --name nodejs --image fission/node-env:latest --builder fission/node-builder:latest --poolsize 1
// fission function create --name pod2slack --src pod2slack.zip --env nodejs --entrypoint pod2slack --secret serverless-config
// fission watch create --function pod2slack --type pod --ns opennms
//
// Future Enhancements:
// 1. Elements to consider:
//    - metadata.creationTimestamp
//    - metadata.labels
//    - spec.nodeName
//    - status.hostIp
//    - status.podIp
// 2. Headers to consider:
//    - x-fission-function-name
//    - x-fission-function-namespace
// 3. Use the OpenNMS ReST API to add/remove nodes based on Pods.
//    - Provide ONMS_URL, ONMS_USERNAME, ONMS_PASSWORD as secrets.

'use strict';

const axios = require('axios');
const fs = require('fs');

const configPath = '/secrets/default/serverless-config/SLACK_URL';

var slackUrl = process.env.SLACK_URL;
if (fs.existsSync(configPath)) {
  slackUrl = fs.readFileSync(configPath,'utf8');
  console.log(`Slack URL: ${slackUrl}`);
}

function upcaseFirst(s) {
  return s.charAt(0).toUpperCase() + s.slice(1).toLowerCase();
}

module.exports = async function(context) {
  if (!slackUrl) {
    return { status: 400, body: 'Missing Slack Webhook URL.' };
  }
  try {
    let eventType = context.request.get('X-Kubernetes-Event-Type');
    let objType = context.request.get('X-Kubernetes-Object-Type');
    let obj = context.request.body;
    let objName = obj.metadata.name;
    let objNamespace = obj.metadata.namespace;
    let objVersion = obj.metadata.resourceVersion;
    let text = `${upcaseFirst(eventType)} ${objType} ${objName}@${objNamespace} (version ${objVersion})`;
    console.debug(JSON.stringify(obj, null, 2));
    console.log(text);
    const response = await axios.post(slackUrl, { text });
    console.log(response.statusText);
    return { status: 200, body: response.statusText };
  } catch (error) {
    console.error(error);
    return { status: 500, body: 'ERROR: something went wrong. ' + error };
  }
}
