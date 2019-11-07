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

var severityColors = []string{
	"#000",
	"#999000",
	"#999",
	"#336600",
	"#ffcc00",
	"#ff9900",
	"#ff3300",
	"#cc0000",
}

var severityNames = []string{
	"Unknown",
	"Indeterminate",
	"Cleared",
	"Normal",
	"Warning",
	"Minor",
	"Major",
	"Critical",
}

// EventParameter represents a parameter of an OpenNMS Event
type EventParameter struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

// Event represents the simplified version of an OpenNMS Event from the Kafka Producer
type Event struct {
	ID         int              `json:"id"`
	Parameters []EventParameter `json:"parameter"`
}

// NodeCriteria represents the node identifier
type NodeCriteria struct {
	ID            int    `json:"id"`
	ForeignSource string `json:"foreign_source"`
	ForeignID     string `json:"foreign_id"`
}

// Alarm represents the simplified version of an OpenNMS Alarm from the Kafka Producer
type Alarm struct {
	ID            int           `json:"id"`
	UEI           string        `json:"uei"`
	NodeCriteria  *NodeCriteria `json:"node_criteria"`
	LogMessage    string        `json:"log_message"`
	Description   string        `json:"description"`
	Severity      int           `json:"severity"`
	Type          int           `json:"type"`
	Count         int           `json:"count"`
	LastEventTime int           `json:"last_event_time"`
	LastEvent     *Event        `json:"last_event"`
}

// HasNode returns true if the alarm has a valid node criteria
func (alarm Alarm) HasNode() bool {
	return alarm.NodeCriteria != nil && alarm.NodeCriteria.ID > 0
}

// GetNodeLabel returns the node label based on the node criteria
func (alarm Alarm) GetNodeLabel() string {
	nc := alarm.NodeCriteria
	if nc == nil {
		return "Unknown"
	}
	if nc.ForeignID == "" {
		return fmt.Sprintf("ID=%d", nc.ID)
	}
	return fmt.Sprintf("%s:%s(%d)", nc.ForeignSource, nc.ForeignID, nc.ID)
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
				Value: severityNames[alarm.Severity],
				Short: true,
			},
		},
	}
	if alarm.HasNode() {
		att.Fields = append(att.Fields, SlackField{
			Title: "Node",
			Value: alarm.GetNodeLabel(),
			Short: false,
		})
	}
	if alarm.LastEvent != nil && len(alarm.LastEvent.Parameters) > 0 {
		for _, p := range alarm.LastEvent.Parameters {
			att.Fields = append(att.Fields, SlackField{
				Title: p.Name,
				Value: p.Value,
				Short: false,
			})
		}
	}
	return SlackMessage{[]SlackAttachment{att}}
}

// ProcessAlarm build a message based on an OpenNMS alarm and sends it to Slack
func ProcessAlarm(alarm Alarm, onmsURL, slackURL string) {
	if alarm.ID == 0 {
		log.Println("Invalid alarm received, ignoring")
		return
	}
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
	ProcessAlarm(alarm, onmsURL, slackURL)
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
