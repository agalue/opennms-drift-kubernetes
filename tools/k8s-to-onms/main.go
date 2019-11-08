package main

import (
	"flag"
	"fmt"
	"os"

	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	_ "k8s.io/client-go/plugin/pkg/client/auth"
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
	namespace := flag.String("namespace", "opennms", "The namespace where the OpenNMS resources live")
	requisition := flag.String("requisition", "Kubernetes", "The name of the target OpenNMS requisition")
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

	pods, err := client.CoreV1().Pods(*namespace).List(v1.ListOptions{})
	if err != nil {
		panic(err)
	}
	req := model.Requisition{
		Name: *requisition,
	}
	for _, pod := range pods.Items {
		node := &model.RequisitionNode{
			ForeignID: pod.Name,
			NodeLabel: pod.Name,
			Location:  "Kubernetes",
		}
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
			loopback := &model.RequisitionInterface{
				IPAddress:   "127.0.0.1",
				SnmpPrimary: "N",
				Status:      1,
				Services: []model.RequisitionMonitoredService{
					{Name: "OpenNMS-JVM"},
				},
			}
			node.AddInterface(loopback)
		}
		node.AddInterface(intf)
		node.AddMetaData("hostIP", pod.Status.HostIP)
		for key, value := range pod.ObjectMeta.Labels {
			node.AddMetaData(key, value)
		}
		req.AddNode(node)
		fmt.Printf("adding node for pod %s\n", pod.Name)
	}
	svc := services.GetRequisitionsAPI(rest.Instance)
	err = svc.SetRequisition(req)
	if err != nil {
		panic(err)
	}
	err = svc.ImportRequisition(req.Name, "true")
	if err != nil {
		panic(err)
	}
	fmt.Println("Done!")
}
