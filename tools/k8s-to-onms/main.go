package main

import (
	"flag"
	"fmt"
	"os"

	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"

	"github.com/OpenNMS/onmsctl/model"
	"github.com/OpenNMS/onmsctl/rest"
	"github.com/OpenNMS/onmsctl/services"
)

func main() {
	flag.StringVar(&rest.Instance.URL, "url", "https://onms.aws.agalue.net/opennms", "OpenNMS URL")
	flag.StringVar(&rest.Instance.Username, "user", rest.Instance.Username, "OpenNMS Username")
	flag.StringVar(&rest.Instance.Password, "passwd", rest.Instance.Password, "OpenNMS Password")
	kubecfg := flag.String("config", os.Getenv("HOME")+"/.kube/config", "Kubernetes Configuration")
	flag.Parse()
	config, err := clientcmd.BuildConfigFromFlags("", *kubecfg)
	if err != nil {
		panic(err)
	}
	client, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err)
	}
	pods, err := client.CoreV1().Pods("opennms").List(v1.ListOptions{})
	if err != nil {
		panic(err)
	}
	requisition := model.Requisition{
		Name: "Kubernetes",
	}
	for _, pod := range pods.Items {
		intf := &model.RequisitionInterface{
			IPAddress:   pod.Status.PodIP,
			SnmpPrimary: "N",
			Status:      1,
		}
		if value, ok := pod.ObjectMeta.Labels["app"]; ok {
			switch value {
			case "kafka":
				intf.AddService(&model.RequisitionMonitoredService{Name: "JMX-Kafka"})
			case "cassandra":
				intf.AddService(&model.RequisitionMonitoredService{Name: "JMX-Cassandra"})
				intf.AddService(&model.RequisitionMonitoredService{Name: "JMX-Cassandra-Newts"})
			case "postgres":
				intf.AddService(&model.RequisitionMonitoredService{Name: "PostgreSQL"})
			case "elasticsearch":
				intf.AddService(&model.RequisitionMonitoredService{Name: "Elasticsearch"})
			}
		}
		node := &model.RequisitionNode{
			ForeignID: pod.Name,
			NodeLabel: pod.Name,
			Location:  "Kubernetes",
		}
		node.AddInterface(intf)
		node.AddMetaData("hostIP", pod.Status.HostIP)
		for key, value := range pod.ObjectMeta.Labels {
			node.AddMetaData(key, value)
		}
		requisition.AddNode(node)
		fmt.Printf("adding node for pod %s\n", pod.Name)
	}
	svc := services.GetRequisitionsAPI(rest.Instance)
	err = svc.SetRequisition(requisition)
	if err != nil {
		panic(err)
	}
	err = svc.ImportRequisition(requisition.Name, "true")
	if err != nil {
		panic(err)
	}
	fmt.Println("Done!")
}
