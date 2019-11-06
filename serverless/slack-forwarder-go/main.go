package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"

	cloudevents "github.com/cloudevents/sdk-go"
	"github.com/lunny/html2md"
	"knative.dev/eventing-contrib/pkg/kncloudevents"
)

var onmsURL string
var slackURL string

var severityColors = map[string]string{
	"CRITICAL":      "#cc0000",
	"MAJOR":         "#ff3300",
	"MINOR":         "#ff9900",
	"WARNING":       "#ffcc00",
	"INDETERMINATE": "#999000",
	"NORMAL":        "#336600",
	"CLEARED":       "#999",
}

// AlarmParameter represents a parameter of an OpenNMS Alarm
type AlarmParameter struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

// Alarm represents the simplified structure of an OpenNMS Alarm
type Alarm struct {
	ID            int              `json:"id"`
	LogMessage    string           `json:"logMessage"`
	Description   string           `json:"description"`
	Severity      string           `json:"severity"`
	LastEventTime int              `json:"lastEventTime"`
	NodeLabel     string           `json:"nodeLabel"`
	Parameters    []AlarmParameter `json:"parameters"`
}

// SlackField represents a field object of an attachment
type SlackField struct {
	Title string `json:"title"`
	Value string `json:"value"`
	Short bool   `json:"short"`
}

// SlackAttachment represents an attachment of a Slack Message
type SlackAttachment struct {
	Title     string       `json:"title"`
	TitleLink string       `json:"title_link"`
	Color     string       `json:"color"`
	PreText   string       `json:"pretext"`
	Text      string       `json:"text"`
	Timestamp int          `json:"ts"`
	Fields    []SlackField `json:"fields"`
}

// SlackMessage represents the simplified structure of a Slack Message
type SlackMessage struct {
	Attachments []SlackAttachment `json:"attachments"`
}

func convertAlarm(alarm Alarm, onmsURL string) SlackMessage {
	att := SlackAttachment{
		Title:     fmt.Sprintf("Alarm ID: %d", alarm.ID),
		TitleLink: fmt.Sprintf("%s/alarm/detail.htm?id=%d", onmsURL, alarm.ID),
		Color:     severityColors[alarm.Severity],
		PreText:   html2md.Convert(alarm.LogMessage),
		Text:      html2md.Convert(alarm.Description),
		Timestamp: alarm.LastEventTime / 1000,
		Fields: []SlackField{
			{
				Title: "Severity",
				Value: alarm.Severity,
				Short: true,
			},
		},
	}
	if alarm.NodeLabel != "" {
		att.Fields = append(att.Fields, SlackField{
			Title: "Node",
			Value: alarm.NodeLabel,
			Short: false,
		})
	}
	if len(alarm.Parameters) > 0 {
		for _, p := range alarm.Parameters {
			att.Fields = append(att.Fields, SlackField{
				Title: p.Name,
				Value: p.Value,
				Short: false,
			})
		}
	}
	return SlackMessage{[]SlackAttachment{att}}
}

func processAlarm(alarm Alarm) {
	msg := convertAlarm(alarm, onmsURL)
	jsonBytes, err := json.Marshal(msg)
	if err != nil {
		log.Printf("Error while converting Slack Message to JSON: %v\n", err)
		return
	}
	request, err := http.NewRequest(http.MethodPost, slackURL, bytes.NewBuffer(jsonBytes))
	if err != nil {
		log.Printf("Error while creating HTTP request: %v\n", err)
		return
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		log.Printf("Error while sending Slack Message: %v\n", err)
		return
	}
	code := response.StatusCode
	if code != http.StatusOK && code != http.StatusAccepted && code != http.StatusNoContent {
		log.Printf("Error, invalid Response: %s", response.Status)
	}
}

func run(event cloudevents.Event) {
	log.Printf("Processing %s\n", event.String())
	alarm := Alarm{}
	if err := event.DataAs(&alarm); err != nil {
		log.Printf("Error while parsing alarm: %v\n", err)
		return
	}
	processAlarm(alarm)
}

func main() {
	var ok bool
	if onmsURL, ok = os.LookupEnv("ONMS_URL"); !ok {
		log.Fatal("Environment variable ONMS_URL must exist")
	}
	if slackURL, ok = os.LookupEnv("SLACK_URL"); !ok {
		log.Fatal("Environment variable SLACK_URL must exist")
	}

	c, err := kncloudevents.NewDefaultClient()
	log.Println("Listening for Knative cloud events")
	if err != nil {
		log.Fatal("Failed to create client, ", err)
	}

	log.Fatal(c.StartReceiver(context.Background(), run))
}
