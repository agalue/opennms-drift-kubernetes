/* @author Alejandro Galue <agalue@opennms.org> */

package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	v1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"
)

var (
	// PodLastResourceVersion holds last cached revision prior start processing
	PodLastResourceVersion string

	// ServiceLastResourceVersion holds last cached revision prior start processing
	ServiceLastResourceVersion string

	// EventLastResourceVersion holds last cached revision prior start processing
	EventLastResourceVersion string
)

// Param represents an event parameter
type Param struct {
	ParmName string `json:"parmName"`
	Value    string `json:"value"`
}

// Event represents an OpenNMS event
type Event struct {
	UEI   string  `json:"uei"`
	Parms []Param `json:"parms"`
}

// ToJSON converts an OpenNMS Event to JSON as string
func (event *Event) ToJSON() string {
	jsonBytes, err := json.Marshal(event)
	if err != nil {
		return "{}"
	}
	return string(jsonBytes)
}

func main() {
	// Configure Kubernetes Client
	var config *rest.Config
	var err error
	kubeconfig := os.Getenv("KUBECONFIG")
	if kubeconfig != "" {
		config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
	} else {
		config, err = rest.InClusterConfig()
	}
	if err != nil {
		panic(err.Error())
	}

	// Creates the clientset
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}

	// Create the shared informer factory and use the client to connect to Kubernetes
	factory := informers.NewSharedInformerFactory(clientset, time.Hour*24)

	// Create a channel to stops the shared informer gracefully
	stopper := make(chan struct{})
	defer close(stopper)

	// Kubernetes serves an utility to handle API crashes
	defer runtime.HandleCrash()

	// Build and start the pod informer
	podInformer := factory.Core().V1().Pods().Informer()
	podInformer.AddEventHandler(cache.FilteringResourceEventHandler{
		FilterFunc: func(obj interface{}) bool {
			if PodLastResourceVersion == "" {
				PodLastResourceVersion = podInformer.LastSyncResourceVersion()
				fmt.Printf("Last resource revision for pods: %s\n", PodLastResourceVersion)
			}
			return isNewer(obj.(*v1.Pod).ResourceVersion, PodLastResourceVersion)
		},
		Handler: cache.ResourceEventHandlerFuncs{
			AddFunc:    onAddPod,    // Triggers when a new pod gets created
			DeleteFunc: onDeletePod, // Triggers when a pod gets deleted
		},
	})
	go podInformer.Run(stopper)

	// Build and start a service informer
	svcInformer := factory.Core().V1().Services().Informer()
	svcInformer.AddEventHandler(cache.FilteringResourceEventHandler{
		FilterFunc: func(obj interface{}) bool {
			if ServiceLastResourceVersion == "" {
				ServiceLastResourceVersion = svcInformer.LastSyncResourceVersion()
				fmt.Printf("Last resource revision for services: %s\n", ServiceLastResourceVersion)
			}
			return isNewer(obj.(*v1.Service).ResourceVersion, ServiceLastResourceVersion)
		},
		Handler: cache.ResourceEventHandlerFuncs{
			AddFunc:    onAddService,    // Triggers when a new service gets created
			DeleteFunc: onDeleteService, // Triggers when a service gets deleted
		},
	})
	go svcInformer.Run(stopper)

	// Build and start an event informer
	eventInformer := factory.Core().V1().Events().Informer()
	eventInformer.AddEventHandler(cache.FilteringResourceEventHandler{
		FilterFunc: func(obj interface{}) bool {
			if EventLastResourceVersion == "" {
				EventLastResourceVersion = eventInformer.LastSyncResourceVersion()
				fmt.Printf("Last resource revision for events: %s\n", EventLastResourceVersion)
			}
			return isNewer(obj.(*v1.Event).ResourceVersion, EventLastResourceVersion)
		},
		Handler: cache.ResourceEventHandlerFuncs{
			AddFunc: onAddEvent, // Triggers when a new event gets created
		},
	})
	go eventInformer.Run(stopper)

	// Wait for Cache
	if !cache.WaitForCacheSync(stopper, podInformer.HasSynced, svcInformer.HasSynced, eventInformer.HasSynced) {
		runtime.HandleError(fmt.Errorf("Timed out waiting for cache to sync"))
		return
	}

	// Graceful Stop
	var gracefulStop = make(chan os.Signal)
	signal.Notify(gracefulStop, syscall.SIGTERM)
	signal.Notify(gracefulStop, syscall.SIGINT)
	go func() {
		sig := <-gracefulStop
		fmt.Printf("\nCaught sig: %+v\n", sig)
		fmt.Println("Last resource versions:")
		fmt.Printf("Pod     : %s\n", podInformer.LastSyncResourceVersion())
		fmt.Printf("Service : %s\n", svcInformer.LastSyncResourceVersion())
		fmt.Printf("Event   : %s\n", eventInformer.LastSyncResourceVersion())
		fmt.Println("Wait to finish processing...")
		time.Sleep(2 * time.Second)
		os.Exit(0)
	}()

	<-stopper
}

func isNewer(currentResourceVersion string, lastResourceVersion string) bool {
	last, _ := strconv.ParseUint(lastResourceVersion, 10, 64)
	current, _ := strconv.ParseUint(currentResourceVersion, 10, 64)
	return current > last
}

func getBaseUEI() string {
	return getEnv("ONMS_BASE_UEI", "uei.opennms.org/kubernetes")
}

func onAddPod(obj interface{}) {
	pod := obj.(*v1.Pod)
	onPodChange("ADDED", *pod)
}

func onDeletePod(obj interface{}) {
	pod := obj.(*v1.Pod)
	onPodChange("DELETED", *pod)
}

func onPodChange(action string, pod v1.Pod) {
	fmt.Printf("%s[%s] pod %s from namespace %s at %s!\n", action, pod.ResourceVersion, pod.Name, pod.Namespace, pod.CreationTimestamp)
	var onmsEvent = Event{
		UEI: getBaseUEI() + "/pod/" + action,
		Parms: []Param{
			{"name", pod.Name},
			{"namespace", pod.Namespace},
			{"creationTimestamp", pod.CreationTimestamp.String()},
		},
	}
	sendEventToOnms(onmsEvent)
}

func onAddService(obj interface{}) {
	svc := obj.(*v1.Service)
	onServiceChange("ADDED", *svc)
}

func onDeleteService(obj interface{}) {
	svc := obj.(*v1.Service)
	onServiceChange("DELETED", *svc)
}

func onServiceChange(action string, svc v1.Service) {
	fmt.Printf("%s[%s] service %s to namespace %s at %s!\n", action, svc.ResourceVersion, svc.Name, svc.Namespace, svc.CreationTimestamp)
	var onmsEvent = Event{
		UEI: getBaseUEI() + "/service/" + action,
		Parms: []Param{
			{"name", svc.Name},
			{"namespace", svc.Namespace},
			{"creationTimestamp", svc.CreationTimestamp.String()},
		},
	}
	sendEventToOnms(onmsEvent)
}

func onAddEvent(obj interface{}) {
	event := obj.(*v1.Event)
	if event.Type != "Normal" {
		fmt.Printf("%s[%s] %s event %s at %s!\n", event.Type, event.ResourceVersion, event.Reason, event.Message, event.CreationTimestamp)
		var onmsEvent = Event{
			UEI: getBaseUEI() + "/event/" + event.Type,
			Parms: []Param{
				{"kind", event.InvolvedObject.Kind},
				{"name", event.InvolvedObject.Name},
				{"namespace", event.InvolvedObject.Namespace},
				{"source", event.Name},
				{"creationTimestamp", event.FirstTimestamp.String()},
				{"nodeName", event.Source.Host},
				{"message", event.Message},
				{"reason", event.Reason},
			},
		}
		sendEventToOnms(onmsEvent)
	}
}

func sendEventToOnms(event Event) {
	url := getEnv("ONMS_URL", "http://localhost:8980/opennms") + "/api/v2/events"
	user := getEnv("ONMS_USER", "admin")
	passwd := getEnv("ONMS_PASSWD", "admin")

	post, err := http.NewRequest("POST", url, bytes.NewBufferString(event.ToJSON()))
	if err != nil {
		fmt.Println(err)
		return
	}
	post.Header.Set("Content-Type", "application/json")
	post.SetBasicAuth(user, passwd)

	client := &http.Client{}
	out, err := client.Do(post)
	if err != nil {
		fmt.Println(err)
		return
	}

	if out.StatusCode == http.StatusNoContent {
		fmt.Printf("OpenNMS event %s has been event.\n", event.UEI)
	} else {
		fmt.Println("There was a problem sending event to OpenNMS")
	}
}

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
