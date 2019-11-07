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

func TestProcessAlarm(t *testing.T) {
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
		assert.Equal(t, "Alarm ID: 666", att.Title)
		assert.Equal(t, "Something **bad** happened", att.PreText)
		assert.Equal(t, 3, len(att.Fields))
		res.WriteHeader(http.StatusOK)
	}))
	defer testServer.Close()

	slackURL := testServer.URL
	onmsURL := "https://onms.aws.agalue.net/opennms"
	alarm := Alarm{
		ID:          666,
		UEI:         "uei.opennms.org/test",
		LogMessage:  "<p>Something <b>bad</b> happened</p>",
		Description: "<p>Check your stuff</p>",
		Severity:    6,
		NodeCriteria: &NodeCriteria{
			ID:            1,
			ForeignSource: "Test",
			ForeignID:     "001",
		},
		LastEventTime: 1000000,
		LastEvent: &Event{
			ID: 66,
			Parameters: []EventParameter{
				{
					Name:  "Owner",
					Value: "agalue",
				},
			},
		},
	}

	ProcessAlarm(alarm, onmsURL, slackURL)
}
