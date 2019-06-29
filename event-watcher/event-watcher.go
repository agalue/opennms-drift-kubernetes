/* @author Alejandro Galue <agalue@opennms.org> */

package main

import (
  "bytes"
  b64 "encoding/base64"
  "encoding/json"
  "fmt"
  "net/http"
  "os"
  "os/signal"
  "syscall"
  "time"

  v1 "k8s.io/api/core/v1"
  metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
  "k8s.io/apimachinery/pkg/util/runtime"
  "k8s.io/client-go/informers"
  "k8s.io/client-go/kubernetes"
  "k8s.io/client-go/rest"
  "k8s.io/client-go/tools/cache"
  "k8s.io/client-go/tools/clientcmd"
)

type Param struct {
  ParmName string `json:"parmName"`
  Value    string `json:"value"`
}

type Event struct {
  UEI   string  `json:"uei"`
  Parms []Param `json:"parms"`
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

  // Access the API to list namespaces
  namespaces, err := clientset.CoreV1().Namespaces().List(metav1.ListOptions{})
  if err != nil {
    panic(err.Error())
  }
  fmt.Printf("There are %d namespaces in the cluster\n", len(namespaces.Items))

  // Create the shared informer factory and use the client to connect to Kubernetes
  factory := informers.NewSharedInformerFactory(clientset, time.Hour*24)

  // Create a channel to stops the shared informer gracefully
  stopper := make(chan struct{})
  defer close(stopper)

  // Kubernetes serves an utility to handle API crashes
  defer runtime.HandleCrash()

  // Build and start the pod informer
  podInformer := factory.Core().V1().Pods().Informer()
  podInformer.AddEventHandler(cache.ResourceEventHandlerFuncs{
    AddFunc:    onAddPod,    // Triggers when a new pod gets created
    DeleteFunc: onDeletePod, // Triggers when a pod gets deleted
  })
  go podInformer.Run(stopper)
  if !cache.WaitForCacheSync(stopper, podInformer.HasSynced) {
    runtime.HandleError(fmt.Errorf("Timed out waiting for pod caches to sync"))
    return
  }

  // Build and start a service informer
  svcInformer := factory.Core().V1().Services().Informer()
  svcInformer.AddEventHandler(cache.ResourceEventHandlerFuncs{
    AddFunc:    onAddService,    // Triggers when a new service gets created
    DeleteFunc: onDeleteService, // Triggers when a service gets deleted
  })
  go svcInformer.Run(stopper)
  if !cache.WaitForCacheSync(stopper, svcInformer.HasSynced) {
    runtime.HandleError(fmt.Errorf("Timed out waiting for service caches to sync"))
    return
  }

  // Build and start an event informer
  eventInformer := factory.Core().V1().Events().Informer()
  eventInformer.AddEventHandler(cache.ResourceEventHandlerFuncs{
    AddFunc: onAddEvent, // Triggers when a new event gets created
  })
  go eventInformer.Run(stopper)
  if !cache.WaitForCacheSync(stopper, eventInformer.HasSynced) {
    runtime.HandleError(fmt.Errorf("Timed out waiting for event caches to sync"))
    return
  }

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
    fmt.Println("Wait for 2 second to finish processing")
    time.Sleep(2 * time.Second)
    os.Exit(0)
  }()

  <-stopper
}

func getUEI() string {
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
    UEI: getUEI() + "/pod/" + action,
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
    UEI: getUEI() + "/service/" + action,
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
      UEI: getUEI() + "/event/" + event.Type,
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
  auth := "Basic " + b64.StdEncoding.EncodeToString([]byte(user+":"+passwd))

  jsonBytes, _ := json.Marshal(event)
  post, err := http.NewRequest("POST", url, bytes.NewBuffer(jsonBytes))
  if err != nil {
    fmt.Println(err)
    return
  }

  post.Header.Set("Content-Type", "application/json")
  post.Header.Set("Authorization", auth)

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
