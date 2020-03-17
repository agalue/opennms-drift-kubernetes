package main

import (
	"github.com/agalue/kafka-converter/api/producer"
	"github.com/golang/protobuf/proto"
	"gopkg.in/confluentinc/confluent-kafka-go.v1/kafka"
)

func main() {
	alarm := &producer.Alarm{
		Id:  1,
		Uei: "uei.opennms.org/test",
		NodeCriteria: &producer.NodeCriteria{
			Id: 1,
		},
	}
	alarmBytes, err := proto.Marshal(alarm)
	if err != nil {
		panic(err)
	}
	config := &kafka.ConfigMap{"bootstrap.servers": "127.0.0.1:9092"}
	kafkaProducer, err := kafka.NewProducer(config)
	topic := "OpenNMS-alarms"
	if err != nil {
		panic(err)
	}
	kafkaProducer.Produce(&kafka.Message{
		TopicPartition: kafka.TopicPartition{Topic: &topic, Partition: kafka.PartitionAny},
		Value:          alarmBytes,
	}, nil)
	kafkaProducer.Close()
}
