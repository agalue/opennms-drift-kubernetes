package main

import (
    "encoding/xml"
	"context"
	"flag"
	"fmt"
	"log"
	"os"

	"k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	_ "k8s.io/client-go/plugin/pkg/client/auth"
	"k8s.io/client-go/tools/clientcmd"

	"github.com/OpenNMS/onmsctl/model"
	"github.com/OpenNMS/onmsctl/rest"
	"github.com/OpenNMS/onmsctl/services"
)

func main() {
	log.SetOutput(os.Stdout)

	flag.StringVar(&rest.Instance.URL, "url", "https://onms.aws.agalue.net/opennms", "OpenNMS URL")
	flag.StringVar(&rest.Instance.Username, "user", rest.Instance.Username, "OpenNMS Username")
	flag.StringVar(&rest.Instance.Password, "passwd", rest.Instance.Password, "OpenNMS Password")
	flag.BoolVar(&rest.Instance.Insecure, "insecure", rest.Instance.Insecure, "Skip Certificate Validation")
	namespace := flag.String("namespace", "opennms", "The namespace where the OpenNMS resources live")
	location := flag.String("location", "Kubernetes", "The name of the Location for the target nodes")
	kubecfg := flag.String("config", os.Getenv("HOME")+"/.kube/config", "Kubernetes Configuration")
	show := flag.Bool("show", false, "Only show requisition in YAML")
	flag.Parse()

	ctx := context.Background()

	config, err := clientcmd.BuildConfigFromFlags("", *kubecfg)
	if err != nil {
		panic(err)
	}
	client, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err)
	}

	req := model.Requisition{
		Name: "Kubernetes-NS-" + *namespace,
	}

	svcs, err := client.CoreV1().Services(*namespace).List(ctx, v1.ListOptions{})
	if err != nil {
		panic(err)
	}

	for _, svc := range svcs.Items {
		if svc.Spec.ClusterIP != "None" {
			node := &model.RequisitionNode{
				ForeignID: "svc-" + svc.Name,
				NodeLabel: "svc-" + svc.Name,
				Location:  *location,
				Building:  svc.Namespace,
			}
			intf := &model.RequisitionInterface{
				IPAddress:   svc.Spec.ClusterIP,
				Description: "ClusterIP",
				SnmpPrimary: "N",
				Status:      1,
			}
			for _, p := range svc.Spec.Ports {
				name := p.Name
				port := fmt.Sprintf("%d", p.Port)
				if name == "" {
					name = string(p.Protocol)
				}
				node.AddMetaData("port-"+name, port)
			}
			node.AddInterface(intf)
			for key, value := range svc.ObjectMeta.Labels {
				node.AddMetaData(key, value)
			}
			req.AddNode(node)
		}
	}

	pods, err := client.CoreV1().Pods(*namespace).List(ctx, v1.ListOptions{})
	if err != nil {
		panic(err)
	}

	for _, pod := range pods.Items {
		isStateful := false
		if pod.OwnerReferences != nil && len(pod.OwnerReferences) > 0 {
			for _, owner := range pod.OwnerReferences {
				if owner.Kind == "StatefulSet" {
					isStateful = true
					break
				}
			}
		}
		if !isStateful {
			log.Printf("%s is not part of a StatefulSet, ignoring", pod.Name)
			continue
		}
		node := &model.RequisitionNode{
			ForeignID: "pod-" + pod.Name,
			NodeLabel: "pod-" + pod.Name,
			Location:  *location,
			Building:  pod.Namespace,
		}
		intf := &model.RequisitionInterface{
			IPAddress:   pod.Status.PodIP,
			Description: "Volatile-IP",
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
			case "onms":
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
		}
		node.AddInterface(intf)
		node.AddMetaData("hostIP", pod.Status.HostIP)
		for key, value := range pod.ObjectMeta.Labels {
			node.AddMetaData(key, value)
		}
		req.AddNode(node)
		if !*show {
			log.Printf("adding node for pod %s\n", pod.Name)
		}
	}
	if *show {
		xmlBytes, _ := xml.MarshalIndent(&req, "", "  ")
		log.Printf("Generated requisition:\n%s", string(xmlBytes))
	} else {
		svc := services.GetRequisitionsAPI(rest.Instance)
		err = svc.SetRequisition(req)
		if err != nil {
			panic(err)
		}
		err = svc.ImportRequisition(req.Name, "true")
		if err != nil {
			panic(err)
		}
	}
	fmt.Println("Done!")
}
