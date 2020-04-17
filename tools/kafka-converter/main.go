// Simple consumer/producer
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"

	"github.com/agalue/kafka-converter/api/producer"
	"github.com/confluentinc/confluent-kafka-go/kafka"
	"github.com/golang/protobuf/proto"
	"github.com/jeremywohl/flatten"
)

const (
	eventKind  = "event"
	alarmKind  = "alarm"
	nodeKind   = "node"
	edgeKind   = "edge"
	metricKind = "metric"
)

var kinds = []string{eventKind, alarmKind, nodeKind, edgeKind, metricKind}

// KafkaClient represents a Kafka consumer/producer client application.
type KafkaClient struct {
	Bootstrap        string
	SourceTopic      string
	DestTopic        string
	FlatDestTopic    string
	MessageKind      string
	GroupID          string
	ProducerSettings string
	ConsumerSettings string
	Debug            bool
	producer         *kafka.Producer
	consumer         *kafka.Consumer
}

func (cli *KafkaClient) getKafkaConfig(properties string) *kafka.ConfigMap {
	config := &kafka.ConfigMap{"bootstrap.servers": cli.Bootstrap}
	if properties != "" {
		for _, kv := range strings.Split(properties, ", ") {
			array := strings.Split(kv, "=")
			if len(array) == 2 {
				if err := config.SetKey(array[0], array[1]); err != nil {
					fmt.Printf("invalid property %s=%s: %v", array[0], array[1], err)
				}
			} else {
				fmt.Printf("invalid key-value pair %s", kv)
			}
		}
	}
	return config
}

func (cli *KafkaClient) validate() error {
	if cli.SourceTopic == "" {
		return fmt.Errorf("source topic cannot be empty")
	}
	if cli.DestTopic == "" {
		return fmt.Errorf("destination topic cannot be empty")
	}
	if cli.MessageKind == "" {
		return fmt.Errorf("message kind cannot be empty")
	}
	set := make(map[string]bool, len(kinds))
	for _, s := range kinds {
		set[s] = true
	}
	if _, ok := set[cli.MessageKind]; !ok {
		return fmt.Errorf("invalid message kind %s. Valid options: %s", cli.MessageKind, strings.Join(kinds, ", "))
	}
	return nil
}

func (cli *KafkaClient) start() error {
	var err error
	jsonBytes, _ := json.MarshalIndent(cli, "", "  ")
	log.Println(string(jsonBytes))

	if err = cli.validate(); err != nil {
		return err
	}

	// Build producer
	cli.producer, err = kafka.NewProducer(cli.getKafkaConfig(cli.ProducerSettings))
	if err != nil {
		return fmt.Errorf("could not create producer: %v", err)
	}

	// Build consumer
	config := cli.getKafkaConfig(cli.ConsumerSettings)
	config.SetKey("group.id", cli.GroupID)
	cli.consumer, err = kafka.NewConsumer(config)
	if err != nil {
		return fmt.Errorf("could not create consumer: %v", err)
	}
	cli.consumer.SubscribeTopics([]string{cli.SourceTopic}, nil)

	// Start producer messages handler
	go func() {
		for e := range cli.producer.Events() {
			switch ev := e.(type) {
			case *kafka.Message:
				if ev.TopicPartition.Error != nil {
					log.Printf("message delivery failed: %v\n", ev.TopicPartition.Error)
				} else {
					log.Printf("message delivered to %v\n", ev.TopicPartition)
				}
			default:
				log.Printf("kafka producer event: %s\n", ev)
			}
		}
	}()

	// Start consumer Loop
	go func() {
		for {
			msg, err := cli.consumer.ReadMessage(-1)
			if err == nil {
				var data proto.Message
				switch cli.MessageKind {
				case eventKind:
					data = &producer.Event{}
				case alarmKind:
					data = &producer.Alarm{}
				case nodeKind:
					data = &producer.Node{}
				case edgeKind:
					data = &producer.TopologyEdge{}
				case metricKind:
					data = &producer.CollectionSet{}
				}
				if err := proto.Unmarshal(msg.Value, data); err != nil {
					log.Printf("invalid %s message received: %v\n", cli.MessageKind, err)
				}
				jsonBytes, err := json.Marshal(data)
				if err == nil {
					cli.producer.Produce(&kafka.Message{
						TopicPartition: kafka.TopicPartition{Topic: &cli.DestTopic, Partition: kafka.PartitionAny},
						Value:          jsonBytes,
						Key:            msg.Key,
					}, nil)
					if cli.Debug {
						log.Printf("JSON message: %s\n", string(jsonBytes))
					}
					if cli.FlatDestTopic != "" {
						flat, err := flatten.FlattenString(string(jsonBytes), "", flatten.UnderscoreStyle)
						if err == nil {
							cli.producer.Produce(&kafka.Message{
								TopicPartition: kafka.TopicPartition{Topic: &cli.FlatDestTopic, Partition: kafka.PartitionAny},
								Value:          []byte(flat),
								Key:            msg.Key,
							}, nil)
							if cli.Debug {
								log.Printf("JSON flat message: %s\n", string(jsonBytes))
							}
						} else {
							log.Printf("cannot flat JSON: %v\n", err)
						}
					}
				} else {
					fmt.Printf("cannot convert GPB to JSON: %v\n", err)
				}
			} else {
				log.Printf("kafka consumer error: %v\n", err)
			}
		}
	}()

	log.Printf("kafka consumer/producer started against %s\n", cli.Bootstrap)
	return nil
}

func (cli *KafkaClient) stop() {
	cli.consumer.Close()
	cli.producer.Close()
	log.Println("good bye!")
}

// Bootstrap function

func main() {
	client := KafkaClient{}
	flag.StringVar(&client.Bootstrap, "bootstrap", "localhost:9092", "kafka bootstrap server")
	flag.StringVar(&client.SourceTopic, "source-topic", "", "kafka source topic with OpenNMS Producer GPB messages")
	flag.StringVar(&client.DestTopic, "dest-topic", "", "kafka destination topic for JSON generated payload")
	flag.StringVar(&client.FlatDestTopic, "dest-topic-flat", "", "when specified, the flat content goes to this topic, and the non-flat version goes to dest-topic")
	flag.StringVar(&client.GroupID, "group-id", "kafka-converter", "kafka consumer group ID")
	flag.StringVar(&client.MessageKind, "message-kind", alarmKind, "source topic message kind; valid options: "+strings.Join(kinds, ", "))
	flag.StringVar(&client.ProducerSettings, "producer-params", "", "optional kafka producer parameters as a CSV of Key-Value pairs")
	flag.StringVar(&client.ConsumerSettings, "consumer-params", "", "optional kafka consumer parameters as a CSV of Key-Value pairs")
	debug := flag.String("debug", "false", "enable debug, to visualize the JSON content to be sent")
	flag.Parse()
	client.Debug = *debug == "true"

	err := client.start()
	if err != nil {
		log.Fatal(err)
	}

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt)
	<-stop
	client.stop()
}
