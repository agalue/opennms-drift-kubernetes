package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/http/httptest"
	"testing"

	"gotest.tools/assert"
)

func TestGet(t *testing.T) {
	testServer := httptest.NewServer(http.HandlerFunc(func(res http.ResponseWriter, req *http.Request) {
		assert.Equal(t, http.MethodPost, req.Method)
		bytes, err := ioutil.ReadAll(req.Body)
		assert.NilError(t, err)
		msg := SlackMessage{}
		err = json.Unmarshal(bytes, &msg)
		assert.NilError(t, err)
		assert.Assert(t, len(msg.Attachments) == 1)
		bytes, err = json.MarshalIndent(msg, "", "  ")
		assert.NilError(t, err)
		fmt.Println(string(bytes))
		att := msg.Attachments[0]
		assert.Equal(t, "Alarm ID: 1", att.Title)
		assert.Equal(t, "Something **bad** happened", att.PreText)
		res.WriteHeader(http.StatusOK)
	}))
	defer testServer.Close()

	slackURL = testServer.URL
	onmsURL = "https://onms.aws.agalue.net/opennms"
	alarm := Alarm{
		ID:            1,
		LogMessage:    "<p>Something <b>bad</b> happened</p>",
		Description:   "<p>Check just stuff</p>",
		Severity:      "MAJOR",
		LastEventTime: 1000000,
		NodeLabel:     "testsrv01",
		Parameters: []AlarmParameter{
			{
				Name:  "owner",
				Value: "agalue",
			},
		},
	}
	processAlarm(alarm)
}
